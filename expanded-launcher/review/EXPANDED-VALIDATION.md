# Проверка расширенной конфигурации

В текущей Linux-среде:

- PASS: Parser and all pure branches execute; original binaries, support files, domain lists and Telegram bootstrap validate
- PASS: Combined arguments preserve YouTube prefix exactly, six groups each include hostname/IP selector; MTProto rule restricted to Telegram IPSet/unknown TCP443
- PASS: OpenAI authentication/assets and Telegram endpoints covered; representative Russian sites, Steam and unrelated Cloudflare excluded; bootstrap uses only 11 exact endpoints
- PASS: All 59 original release files remain byte-for-byte unchanged
- PASS: Independent strict CIDR validator fixtures pass: valid public networks accepted; empty, malformed, broad/private/host-bit ranges and oversized inputs rejected
- PASS: Exact service probe preserves TLS verification and classifies HTTP403 as response, not verified app; official-list cache writes atomically only after strict validation and preserves prior data on invalid input
- PASS: Independent expanded profile/lifecycle/service-selection fixtures pass

Успех YouTube в предыдущей версии подтверждён пользователем. Новые OpenAI/Telegram правила
в его Windows ещё не выполнены. В контрольных фикстурах использовались безопасные подставные
curl-процессы и данные; результаты не выдаются за реальные проверки сервиса.
Контроль российской страницы и Steam сравнивает наличие HTTP-ответа и сохранение успешного
2xx/3xx статуса с повторением спорного результата. Это не тест всех сайтов/игр.

НЕ ВЫПОЛНЕНЫ:

- UNRUN: New profiles with Windows WinDivert and this ISP
- UNRUN: ChatGPT login/region/JS challenge
- UNRUN: Telegram Desktop MTProto/media/calls
- UNRUN: Real official CIDR retrieval from user connection
- UNRUN: All Russian websites and game performance

Индивидуальные профили YouTube и схема владения дочерними процессами сохранены из предыдущей
версии. Полная проверка Windows Job/UAC/WinDivert остаётся целевой проверкой Windows.
Ни HTTP403, ни доступность Telegram Web не считаются подтверждением успешного ChatGPT-входа
или native MTProto. В отчёте AppVerified/NativeTelegramVerified остаются false.
