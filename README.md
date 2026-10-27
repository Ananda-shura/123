# Happ + Zapret: ChatGPT, Telegram Desktop и YouTube

**[Скачать готовую полную папку — ZIP, около 13 МБ](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-happ-ready.zip)**

Проверка на компьютере пользователя показала: YouTube работает с отдельным методом Zapret, ChatGPT сообщает о недоступности региона, Telegram Desktop остаётся на подключении. При закрытом START.cmd и включённом существующем Happ оба последних сервиса работают. Поэтому новая папка сочетает отдельный профиль маршрутизации Happ для ChatGPT/Telegram и прежний YouTube-only запуск Zapret.

1. Закройте старое окно START.cmd и распакуйте новый архив в отдельную папку. Прежние папки и профиль Happ сохраните.
2. Подключите в Happ ваш проверенный рабочий сервер. Запустите **SETUP-HAPP.cmd** из `Zapret-Happ-ready`.
3. Добавьте открывшийся новый профиль `ChatGPT-Telegram-Selective-…` в Happ, выберите его в маршрутизации и включите использование профиля. Переподключите прежний сервер в том же режиме, с которым работал Telegram.
4. Запустите **START.cmd**, подтвердите запрос Windows и дождитесь проверки YouTube. Оставьте окно открытым, перезапустите браузер и Telegram Desktop.

SETUP-HAPP.cmd нужен один раз и при обновлении списка адресов Telegram. Он получает только официальный список Telegram по проверенному HTTPS, строго проверяет диапазоны и создаёт отдельный профиль с уникальным именем. При ошибке загрузки или проверки импорт не запускается. Ссылка и JSON сохраняются в `happ-state/<имя>/` для ручного импорта при необходимости. Скрипт открывает импорт в Happ; выбор профиля и подключение выполняет пользователь. Серверы и подписки в JSON отсутствуют.

По правилам профиля через ваш сервер идут только домены ChatGPT/OpenAI, точечный `challenges.cloudflare.com`, домены Telegram и его официальные IPv4/IPv6-сети. Остальной трафик, включая российские сайты, Steam и YouTube, направляется напрямую. Для YouTube используется неизменённый предыдущий запуск Zapret. Общие сети Cloudflare, Game Filter и правила для всех IP не добавлены.

Новый профиль задаёт **DNS внутри Happ**: Google DoH для удалённого DNS и Yandex DoH для внутреннего. Это собственные параметры нового профиля, а не сохранение DNS прежнего профиля Happ. Скрипты не меняют системный DNS Windows, hosts, реестр, службы, брандмауэр или автозапуск. Откат: выбрать прежний профиль Happ, переподключиться и при необходимости вернуться к прежней папке YouTube.

Работа обоих сервисов через существующий Happ подтверждена пользователем. **Импорт нового выборочного профиля и его совместную работу с YouTube-only Zapret ещё нужно проверить на Windows.** Проверки кода/JSON/Base64/границ правил и отказов выполнены в Linux PowerShell; они не подтверждают реальную маршрутизацию, TUN/sniffing, все российские сайты, медиа/звонки Telegram или игровые показатели. Все 59 исходных файлов Zapret, бинарники и драйверы сохранены. Лицензии и исходники зависимостей включены в ZIP.

- [Инструкция](happ-launcher/СНАЧАЛА-ПРОЧИТАЙ.txt)
- [Исходник настройки Happ](happ-launcher/happ/setup-happ.ps1)
- [Причина и изменения](happ-launcher/review/HAPP-CHANGES.md), [проверки](happ-launcher/review/HAPP-VALIDATION.md), [официальные источники](happ-launcher/review/HAPP-SOURCE-PROVENANCE.json)
- [SHA256 архива](zapret-happ-ready.zip.sha256)

## Предыдущие варианты

- [YouTube-only: подтверждённый предыдущий подбор](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-auto-test.zip), [исходник](auto-launcher/autopick.ps1), [проверки](auto-launcher/AUTO-VALIDATION.md).
- [Расширенный вариант только с DPI-правилами](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-expanded.zip), [исходник](expanded-launcher/expanded/expanded.ps1), [изменения](expanded-launcher/review/EXPANDED-CHANGES.md). Проверка подтвердила YouTube и Telegram Web; региональный отказ ChatGPT и Telegram Desktop этим способом не устранены.
- [Исходная полная папка с фиксированной стратегией](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-ready-full.zip), [дополнение без бинарников](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-optimized.zip), [диагностика DNS/HTTPS](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/youtube-diagnostic.zip).

[Аудит релиза](zapret-files/AUDIT.md), [таблица стратегий](zapret-files/STRATEGIES.md), [происхождение файлов](zapret-files/PROVENANCE.md).
