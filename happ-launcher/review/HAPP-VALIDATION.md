# Проверки новой папки

В Linux с PowerShell, без запуска Windows-клиента Happ, WinDivert или winws:

- PASS: Setup source parses and pure validation/profile branches execute without network or Windows changes
- PASS: All 59 original release files and the previous YouTube-only launcher, profiles and helper remain byte-for-byte unchanged
- PASS: Exact delivered bootstrap verifies both SHA256 pins and loads explicit root with non-ASCII, spaces and shell-special path characters
- PASS: Independent full-schema, domain-boundary, negative-site, CIDR-refusal and Base64/JSON fixtures pass
- PASS: Exact official-list fetch uses verified HTTPS and bounded curl; valid fixture accepted, empty/HTML/catch-all/private/TLS-failure cases rejected

ПОДТВЕРЖДЕНО ПОЛЬЗОВАТЕЛЕМ:

- ChatGPT and Telegram Desktop work through the existing Happ connection with START.cmd closed
- Previous YouTube method FAKE-TLS-AUTO-ALT works

ЕЩЁ НЕ ВЫПОЛНЕНО:

- Actual Happ routing-profile import/selection and DNS behavior on Windows
- Joint selective Happ plus YouTube-only WinDivert behavior
- New-profile routing of Telegram messages/media/calls and OpenAI login
- All Russian websites and game performance

Фикстуры используют тестовые публичные адреса Telegram и подставной curl.
Они подтверждают структуру/отказы кода, а не фактическую маршрутизацию Windows.
Новый профиль содержит явные DNS-настройки Happ. Откат — выбор прежнего профиля Happ.
Скрипт не переключает TUN, не активирует маршрутизацию и не меняет системный DNS.
