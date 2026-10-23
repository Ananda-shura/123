# Проверка полной папки

Проверено в текущем Linux-окружении:

- PASS: CMD uses ASCII/CRLF, inline readable command below Windows CMD length limit, clears check mode, no policy override
- PASS: PowerShell parser: delivered inline command
- PASS: PowerShell parser: readable source
- PASS: Full package contains all 59 original files byte-for-byte, including 27 bin components
- PASS: Actual inline command completes file/hash validation without elevation or executable loading
- PASS: Actual inline argument construction: two YouTube-only TCP/UDP443 profiles; all references resolve and are quoted
- PASS: Validation and argv with spaces, Cyrillic, apostrophe, ! and & in folder path (Windows ShellExecute itself unrun)
- PASS: Fault tests: empty hostlist, changed EXE hash, missing driver all refuse startup and produce local error log
- PASS: Hostlist model includes YouTube/CDN; Steam, unrelated Google, Discord and suffix lookalike excluded

Выполнялись только безопасные проверочные ветви точной команды, извлечённой из START.cmd.
Компактизация PowerShell в одну строку проверена официальным парсером PowerShell 7.4.7.
Фактическое исполнение Windows CMD, ShellExecute/UAC и загрузка Windows EXE/драйвера не
проверены здесь. Эти результаты не доказывают работу YouTube или отсутствие влияния на CS2.

Не выполнено:

- UNRUN: Windows cmd/ShellExecute/UAC
- UNRUN: Windows PowerShell 5.1 native argv handling
- UNRUN: WinDivert driver load/Authenticode trust
- UNRUN: YouTube video/HTTP3 on user ISP
- UNRUN: Steam downloads, CS2 RTT/jitter/loss
- UNRUN: Windows reboot

Контрольные суммы исходных бинарников совпадают с официальным релизом 1.10.4.
Для библиотек включены полные upstream-исходники соответствующих версий и лицензии,
с отдельным описанием границ подтверждения в sources-and-licenses/SOURCE-README.md.
Воспроизводимость оригинальной сборки и цифровые подписи Windows не заявляются.

START.cmd не устанавливает постоянную службу Zapret и не создаёт автозапуск. При запуске
сам WinDivert может зарегистрировать/запустить свою kernel-службу, как в оригинальном релизе.
Исключение других обходчиков проверяется по именам процессов и известных служб; это не
полный аудит всех сторонних сетевых драйверов и не устранение любой возможной гонки запуска.
