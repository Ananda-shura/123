using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

/// <summary>
/// Owns an anonymous Windows Job whose member processes are terminated when its
/// final handle closes. Add must only receive newly started child processes from
/// this launcher. This class never opens a process by PID or searches by name.
/// </summary>
public sealed class ZapretOwnedJob : IDisposable
{
    private const UInt32 JobObjectLimitKillOnJobClose = 0x00002000;
    private const Int32 JobObjectExtendedLimitInformation = 9;
    private readonly Object gate = new Object();
    private SafeJobHandle job;
    private Boolean disposed;

    public ZapretOwnedJob()
    {
        SafeJobHandle created = NativeCreateJobObject(IntPtr.Zero, null);
        if (created == null || created.IsInvalid)
        {
            Int32 error = Marshal.GetLastWin32Error();
            if (created != null) created.Dispose();
            throw new Win32Exception(error, "CreateJobObject failed.");
        }

        try
        {
            ExtendedLimitInformation limits = new ExtendedLimitInformation();
            limits.BasicLimitInformation.LimitFlags = JobObjectLimitKillOnJobClose;
            UInt32 size = checked((UInt32)Marshal.SizeOf(typeof(ExtendedLimitInformation)));
            if (!NativeSetInformationJobObject(created,
                JobObjectExtendedLimitInformation, ref limits, size))
            {
                Int32 error = Marshal.GetLastWin32Error();
                throw new Win32Exception(error,
                    "SetInformationJobObject(KILL_ON_JOB_CLOSE) failed.");
            }
            job = created;
        }
        catch
        {
            // A partially initialized Job must not leak a handle.
            created.Dispose();
            throw;
        }
    }

    /// <summary>
    /// Assign a fresh child returned by Process.Start in this launcher. On
    /// failure the caller must stop that child through its Process object.
    /// </summary>
    public void Add(Process child)
    {
        if (child == null) throw new ArgumentNullException("child");
        lock (gate)
        {
            if (disposed) throw new ObjectDisposedException("ZapretOwnedJob");
            if (child.HasExited)
                throw new InvalidOperationException("The owned child has already exited.");

            // SafeHandle arguments are held alive by the P/Invoke marshaler for
            // the duration of the call. No numeric PID can be reused here.
            if (!NativeAssignProcessToJobObject(job, child.SafeHandle))
            {
                Int32 error = Marshal.GetLastWin32Error();
                throw new Win32Exception(error, "AssignProcessToJobObject failed.");
            }
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return;
            disposed = true;
            // SafeHandle supplies finalization during normal managed cleanup.
            // On forced host termination Windows closes its handles instead.
            // This handle is non-inheritable (null SECURITY_ATTRIBUTES), so a
            // child cannot keep the Job alive after its launcher has exited.
            if (job != null) job.Dispose();
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BasicLimitInformation
    {
        public Int64 PerProcessUserTimeLimit;
        public Int64 PerJobUserTimeLimit;
        public UInt32 LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public UInt32 ActiveProcessLimit;
        public UIntPtr Affinity;
        public UInt32 PriorityClass;
        public UInt32 SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        public UInt64 ReadOperationCount;
        public UInt64 WriteOperationCount;
        public UInt64 OtherOperationCount;
        public UInt64 ReadTransferCount;
        public UInt64 WriteTransferCount;
        public UInt64 OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ExtendedLimitInformation
    {
        public BasicLimitInformation BasicLimitInformation;
        public IoCounters IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    private sealed class SafeJobHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        public SafeJobHandle() : base(true) { }
        protected override Boolean ReleaseHandle()
        {
            return NativeCloseHandle(handle);
        }
    }

    [DllImport("kernel32.dll", EntryPoint = "CreateJobObjectW",
        CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeJobHandle NativeCreateJobObject(
        IntPtr securityAttributes, String name);

    [DllImport("kernel32.dll", EntryPoint = "SetInformationJobObject",
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern Boolean NativeSetInformationJobObject(
        SafeJobHandle job, Int32 informationClass,
        ref ExtendedLimitInformation information, UInt32 informationLength);

    [DllImport("kernel32.dll", EntryPoint = "AssignProcessToJobObject",
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern Boolean NativeAssignProcessToJobObject(
        SafeJobHandle job, SafeProcessHandle process);

    [DllImport("kernel32.dll", EntryPoint = "CloseHandle", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern Boolean NativeCloseHandle(IntPtr handle);
}
