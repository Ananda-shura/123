# Zapret 1.10.4: YouTube, ChatGPT и Telegram

**[Скачать готовую полную папку — ZIP, около 13 МБ](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-expanded.zip)**

1. Закройте старое окно START.cmd. Сохраните прежнюю рабочую папку.
2. Распакуйте весь новый архив в отдельную папку.
3. Откройте `Zapret-1.10.4-expanded`, дважды нажмите **START.cmd** и подтвердите запрос Windows.
4. Дождитесь окончания проверок. Оставьте окно открытым, полностью перезапустите браузер и Telegram Desktop.
5. Проверьте YouTube, вход в ChatGPT, сообщения и медиа Telegram, российские сайты. При проблеме пришлите `RESULT.txt` из `logs/expanded-...`.

Прежняя сборка обрабатывала только YouTube. Здесь сохранены его четыре метода подбора и добавлены отдельные правила OpenAI/ChatGPT, Telegram Web и Telegram Desktop. У приложения Telegram используется прямое подключение по IP, поэтому для него добавлено отдельное правило неизвестного TCP-протокола на порту 443 с ограниченным списком адресов Telegram. Полный список запрашивается с официального HTTPS-источника и применяется после строгой проверки; если он недоступен, остаются 11 стартовых адресов из исходников Telegram Desktop.

Списки сервисов ограничивают обработку. Общего обхода для всех IP, Game Filter и широких сетей Cloudflare нет. DNS, маршруты, системный прокси, Happ, службы и настройки безопасности Windows не меняются. При обнаруженном ухудшении контрольных проверок YouTube, ya.ru или Steam расширение отключается и сохраняется только профиль YouTube. Это контроль нескольких страниц, а не проверка всех сайтов и игр.

YouTube в предыдущей версии уже подтверждён пользователем. **Новые правила ChatGPT и Telegram Desktop ещё требуют проверки на его компьютере.** Код и сценарии ошибок проверены в Linux с PowerShell и тестовыми данными; это не испытание Windows/WinDivert или провайдера. HTTP 403 не означает успешный вход в ChatGPT. Zapret не меняет внешний IP и не решает серверные ограничения региона либо блокировку маршрута к IP Telegram. Работа Telegram Web не подтверждает работу приложения, медиа и звонков.

Все 59 файлов исходного релиза, включая бинарники и драйверы, сохранены без изменений. Полная папка содержит лицензии и исходники зависимостей.

- [Инструкция внутри архива](expanded-launcher/СНАЧАЛА-ПРОЧИТАЙ.txt)
- [Исходник запуска и подбора](expanded-launcher/expanded/expanded.ps1)
- [Описание изменений](expanded-launcher/review/EXPANDED-CHANGES.md) и [результаты проверок](expanded-launcher/review/EXPANDED-VALIDATION.md)
- [SHA256 нового архива](zapret-1.10.4-expanded.zip.sha256)

## Предыдущая сборка YouTube

[Скачать прежнюю папку с подбором YouTube](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-auto-test.zip). Она сохранена для возврата к подтверждённому пользователем варианту. [Исходник](auto-launcher/autopick.ps1), [проверки](auto-launcher/AUTO-VALIDATION.md), [SHA256](zapret-1.10.4-auto-test.zip.sha256).

## Предыдущие версии и аудит

[Исходная полная папка с фиксированной стратегией](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-ready-full.zip), [дополнение без бинарников](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/zapret-1.10.4-optimized.zip) и [диагностика DNS/HTTPS](https://github.com/Ananda-shura/123/raw/refs/heads/zapret-audit-1.10.4/youtube-diagnostic.zip) сохранены для сравнения и отката.

[Аудит релиза](zapret-files/AUDIT.md), [таблица стратегий](zapret-files/STRATEGIES.md), [происхождение файлов](zapret-files/PROVENANCE.md).
