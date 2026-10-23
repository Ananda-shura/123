# Изменения

Исходные 59 файлов, включая все BAT, списки и bin, не изменены.
Никакие параметры оригинального general.bat не заменялись.

| Добавленный файл | Назначение и обоснование |
|---|---|
| start-youtube.cmd | Явный запуск отдельного PowerShell-профиля без service.bat |
| utils/start-youtube.ps1 | Два профиля UDP443/TCP443, только YouTube hostlist; контроль SHA256 bin; mutex и отказ при другом обходчике |
| lists/list-youtube-optimized.txt | Общий список 17 доменов YouTube для TLS и QUIC, без Google Play/Discord/Steam |
| utils/diagnose-readonly.ps1 | Локальный отчёт процессов/служб/DNS/подписей и DNS/HTTPS; необязательный ICMP |
| ORIGINAL-SHA256.json | Хэши 59 исходных файлов |
| AUDIT.md, STRATEGIES.md, PROVENANCE.md | Аудит, сравнение стратегий и происхождение |
| README-INSTALL.md, ROLLBACK.md, TEST-MATRIX.csv | Применение, откат и шаблон локального сравнения |
| changes.diff, VALIDATION.md, PACKAGE-SHA256.json | Проверяемые добавления, результаты проверок и целостность дополнения |

UDP: fake, repeats=6, quic_initial_www_google_com.bin — те же параметры, что в general.bat,
но общий список теперь включает YouTube. TCP: multisplit, split-seqovl=681, split-pos=1,
ip-id=zero, tls_clienthello_www_google_com.bin — исходная Google-стратегия general.bat.
Уменьшена область применения: вместо 9 профилей — 2; нет TCP80, Discord-портов, IPSet и GameFilter.
Нет dpi-desync-any-protocol, глобальных изменений TCP timestamps, загрузки обновлений,
создания постоянного автозапуска, удаления служб или принудительного завершения процессов.

Ожидается устранение пробела hostlist YouTube для QUIC и уменьшение посторонней обработки.
Успех у конкретного провайдера и выигрыш пинга требуют Windows-тестов. Не утверждается,
что исходный пробел — единственная причина нестабильности пользователя.
