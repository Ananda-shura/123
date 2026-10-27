# Zapret 1.10.4: доработанные исходные файлы релиза

**[Скачать готовую полную папку — ZIP, около 13 МБ](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-reworked.zip)**

Неофициальная модификация [официального релиза Flowseal 1.10.4](https://github.com/Flowseal/zapret-discord-youtube/releases/tag/1.10.4). Официальный архив скачан повторно и совпал со всеми 59 файлами пользовательской копии. Изменены сами 22 стратегии `general*.bat`, `service.bat` и защитный вход старого тестировщика — **24 исходных текстовых файла**. Все **27 файлов bin** сохранены без изменений.

1. Закройте старое окно START.cmd. Прежние папки сохраните.
2. Распакуйте **весь** архив в **C:\Zapret**. Нужен короткий путь: у команд BAT есть ограничение CMD в 8191 символ.
3. Откройте `Zapret-1.10.4-reworked`, нажмите **START.cmd** и подтвердите запрос Windows.
4. Оставьте окно открытым, перезапустите браузер и проверьте YouTube, нужные сайты, Steam и игры. Для остановки закройте окно или нажмите Ctrl+C.

## Что исправлено

- Во всех стратегиях QUIC добавлен узкий список YouTube: в исходнике он применялся только к TCP. Основной Google/OpenAI TCP использует уже сработавший у пользователя FAKE TLS AUTO ALT.
- Добавлены отдельные списки OpenAI и Telegram Web, а для Telegram Web — отдельный профиль с ранее сработавшими параметрами. Google/OpenAI/Telegram TCP учитывают пользовательские доменные и IP-исключения.
- Обычный запуск больше не включает глобальные TCP timestamps. Диагностика не удаляет общие службы драйвера и не очищает кэши с завершением приложений.
- Обнаруженный другой обходчик или повреждённые исполняемые файлы останавливают запуск. Пустой/повреждённый IPSet отклоняется; обновление проверяется до атомарной замены с резервной копией.
- Широкий ALT5 отключён. EXP больше не обрабатывает неизвестный UDP на Discord-портах. Game Filter выключен; активный IPSet сохраняет исходную документационную заглушку, режим ANY не создаётся.
- Старый тестировщик, завершавший все winws и временно включавший IPSet ANY, заблокирован. **CHECK.cmd** выполняет проверку файлов и активного IPSet без сетевых тестов.

Исходные общие списки проекта и исключения Steam/российских сайтов сохранены. Некоторые общие CDN-домены исходного hostlist широкие: работа всех сайтов/игр и нулевая нагрузка WinDivert не гарантируются. Проверка процессов перед запуском не является mutex для одновременных стартов; запускайте одну стратегию. Ручные служебные действия по-прежнему требуют отдельного выбора и подтверждения в менеджере; перед установкой службы закройте standalone-окно.

Региональная ошибка ChatGPT уже подтверждена пользователем: доработка DPI не меняет внешний IP/страну. Работа Telegram Web не подтверждает работу Telegram Desktop; его предыдущий отдельный DPI-профиль в этой сети не помог. Пользователь подтвердил, что ChatGPT и Telegram Desktop работают через существующий Happ. Эта модификация исходного релиза **не настраивает Happ и не объявляется исправлением этих двух ограничений**.

Проверки структуры правил, PowerShell, неизменности бинарников, официального каталога IPSet и сценариев отказа прошли в Linux. **Windows CMD/UAC/SCM/WinDivert и работа новой сборки у провайдера ещё не проверены.** Упакованы лицензии, исходники зависимостей и оригинальные версии изменённых файлов для отката.

- [Инструкция](reworked-original/СНАЧАЛА-ПРОЧИТАЙ.txt), [изменённый general.bat](reworked-original/general.bat), [изменённый service.bat](reworked-original/service.bat)
- [Точный diff](reworked-original/review/changes.diff), [аудит изменений](reworked-original/review/AUDIT-CHANGES.md), [результаты проверок](reworked-original/review/VALIDATION.md)
- [Исходные версии изменённых файлов](reworked-original/original-files), [происхождение](reworked-original/review/SOURCE.json), [SHA256 архива](zapret-1.10.4-reworked.zip.sha256)

## Предыдущие варианты

- [Happ + YouTube-only Zapret](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-happ-ready.zip): отдельный выборочный профиль Happ для ChatGPT/Telegram через уже работающий сервер. [Инструкция](happ-launcher/СНАЧАЛА-ПРОЧИТАЙ.txt), [проверки](happ-launcher/review/HAPP-VALIDATION.md). Новый выборочный импорт требует проверки на Windows.
- [Предыдущий подтверждённый подбор YouTube](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-auto-test.zip), [исходник](auto-launcher/autopick.ps1), [проверки](auto-launcher/AUTO-VALIDATION.md).
- [Расширенный вариант только с DPI-правилами](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-expanded.zip): подтверждены YouTube и Telegram Web, регион ChatGPT/Telegram Desktop этим способом не устранены.
- [Первая полная папка](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-ready-full.zip), [дополнение без бинарников](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-optimized.zip), [диагностика DNS/HTTPS](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/youtube-diagnostic.zip).

[Первоначальный аудит релиза](zapret-files/AUDIT.md), [таблица исходных стратегий](zapret-files/STRATEGIES.md), [происхождение оригиналов](zapret-files/PROVENANCE.md).
