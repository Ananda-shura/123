# Проверка подбора

В текущей Linux-среде выполнено:

- PASS: PowerShell parser accepts entire selector source
- PASS: Pure branches execute: original/support hashes validated; four scoped profiles contain no Game/IPSet/timestamps strategy
- PASS: All 59 original release files remain unchanged
- PASS: Delivered bootstrap checksum and explicit-root source loading execute without changing execution policy
- PASS: Windows Job helper compiles and x64 native structure sizes match 64/48/144; kernel32 calls not executed in Linux
- PASS: Exact HTTPS probe preserves curl/TLS failures and requires HTTP200 plus body bytes, using --disable and certificate verification
- PASS: Raw TCP checker exercised against real local sockets: accepted connection and refused connection distinguished without TLS
- PASS: Independent selector scenarios pass: failed/probe-error candidates cleaned, normal-DNS rejection, winner retained, fatal assignment abort, all-fail no winner

Дополнительно независимые фикстуры проверили девять сценариев выбора/очистки:
отказ нерабочего профиля, отказ при успехе только фиксированного IP, все варианты неуспешны,
ошибка пробы, фатальная ошибка назначения Job, ошибка завершения, процесс завершился до
пробы и во время пробы, совпадение профилей с оригинальными аргументами.

Тест raw TCP использовал настоящий локальный сокет с доступным и недоступным адресом.
Тест HTTPS использовал безопасный тестовый процесс curl, без реальных Windows EXE.
Компиляция WindowsJob.cs и проверка ABI структур выполнены, kernel32 в Linux не вызывался.

НЕ ВЫПОЛНЕНЫ:

- UNRUN: Windows UAC/native argument passing
- UNRUN: Windows Job assignment and console-close cleanup
- UNRUN: WinDivert capture, ISP strategy selection
- UNRUN: Browser/QUIC/video playback
- UNRUN: Steam/CS2 latency and downloads

Не заявляется, что Windows Job, UAC, реальная сеть/провайдер или браузерная работа уже проверены.
Возможный победитель определяется только локально на компьютере пользователя. До его запуска
результатов четырёх стратегий на этом провайдере нет. При полном отказе никакой победитель
не назначается, процессы подбора останавливаются, RESULT.txt сохраняет результаты.
