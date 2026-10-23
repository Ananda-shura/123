# Результаты проверки

Проверки текущего запуска в Linux (24 октября 2026, дата клиента):

- PASS: 59 original files unchanged and match original manifest
- PASS: PowerShell parser: diagnose-readonly.ps1
- PASS: PowerShell parser: start-youtube.ps1
- PASS: PowerShell parser: test zapret.ps1
- PASS: Actual generated argv: two scoped profiles, TCP-only mode and all data references resolve
- PASS: PrintArguments with spaces and Cyrillic path preserves quoted values (native Windows launch unrun)
- PASS: CMD/PS1/list CRLF; PowerShell UTF-8 BOM for Windows PowerShell 5.1
- PASS: Hostlist coverage cases: YouTube/CDN included, Steam/Google/Discord and suffix lookalike excluded; original QUIC list misses YouTube
- PASS: Original IP lists including 33048 backup CIDRs parse successfully
- PASS: Read-only integrity branch executes: valid overlay passes; empty hostlist, changed EXE hash and missing QUIC payload fail closed (no binary execution)

Проверено соответствие всего исходного ZIP официальному asset (SHA-256 совпадает).
Подготовка PowerShell 7.4.7 из официального архива выполнена дважды; оба раза версия 7.4.7,
SHA-256 прошёл. Парсер запущен из этого проверенного инструмента, исполнялись только ветви
-PrintArguments нового запуска. Это реальное выполнение построения argv, без запуска WinDivert.
Проверка списка доменов использует модель документированного сопоставления поддоменов;
это не тест сетевого движка winws или разбора QUIC Initial.

НЕ ВЫПОЛНЕНЫ:

- UNRUN: Windows PowerShell 5.1 native execution
- UNRUN: WinDivert load and signatures on Windows
- UNRUN: YouTube video playback/QUIC on user ISP
- UNRUN: Steam downloads and CS2 latency
- UNRUN: Windows reboot/autostart

Наборов тестов самого приложения, выполненных на Windows: 0. Проверки Linux не выдаются
за Windows-интеграционные испытания. Значения пинга, скорости и воспроизведения не выдумывались.
Нет подтверждения, что все возможные программы/драйверы-конкуренты выявляются по именам.
Mutex предотвращает два новых запуска между собой; инвентаризация не устраняет гонку
с запуском стороннего обходчика после проверки.

В облаке сохранены install_script и start_skill для повторяемого статического анализа.
Они не запускают Windows EXE и не создают сетевых служб. Сохранение черновика не означает
публикацию среды или проверку восстановления в новой задаче.
