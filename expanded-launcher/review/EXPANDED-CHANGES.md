# Изменения относительно работающего профиля YouTube

- Исходные 59 файлов ZIP 1.10.4 сохранены, все бинарники/драйверы неизменны.
- START.cmd загружает проверенный по SHA256 expanded/expanded.ps1.
- Прежний подбор YouTube сохраняется отдельным блоком. Новые сервисы не меняют его TLS-флаги.
- lists/list-openai.txt: chatgpt.com, openai.com, oaistatic.com, oaiusercontent.com,
  challenges.cloudflare.com. Это минимальный список, а не утверждённый исчерпывающий allowlist.
- lists/list-telegram-web.txt: telegram.org, t.me, telegram.me, telegram-cdn.org.
- lists/list-services-web.txt: отдельный QUIC hostlist для добавленных сервисов.
- Оригинальный list-exclude.txt применяется к дополнительным веб-правилам.
- Telegram Desktop: unknown TCP443, IPSet только Telegram, multisplit pos1/cutoff n3;
  правило экспериментальное до проверки приложения. Другие TCP/UDP-порты не добавлены.
- Резервный IPSet содержит только 11 production bootstrap endpoints из официального Telegram
  Desktop; source commit и ограничение покрытия записаны в TELEGRAM-SOURCE-PROVENANCE.json.
- Если доступен официальный CIDR endpoint, по проверенному HTTPS загружается его список,
  строго проверяется, атомарно сохраняется в state и применяется при перезапуске только
  собственного процесса. Пустые, широкие, локальные, повреждённые диапазоны отвергаются.
- Тест HTTP403 сохраняет факт доступности TLS, но не означает успешный вход в ChatGPT.
- При ухудшении YouTube, ya.ru/Steam расширение откатывается до YouTube-профиля.
- DNS, маршруты, глобальные прокси/политики, службы, Defender и настройки Telegram не меняются.

Официальные страницы OpenAI о сетевых требованиях/странах и Telegram CIDR endpoint были
недоступны из среды подготовки (egress CONNECT/HTTP403). Это не результаты из сети пользователя.
Работа браузерной авторизации, региональные ограничения и MTProto требуют целевой проверки.
Широкие Cloudflare IPSet, IPSet any, Game Filter, автоматический VPN и сторонние прокси не добавлены.
Проверенный сторонний кандидат tg-ws-proxy не включён: просмотренные ветки ослабляют hostname
verification в части fallback-подключений, что не соответствует сохранению полной TLS-проверки.
