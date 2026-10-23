# Стратегии оригинального релиза 1.10.4

Источник: тег `1.10.4`, commit `176f56dc3f11ce5915c26abcdde903f93d835b64`. Все 22 исходных `general*.bat` прочитаны. Таблица описывает параметры, а не результаты сравнения провайдеров.

«Профили» — число групп, разделённых `--new`. Колонка TCP описывает правило `list-google.txt`; исключение ALT5 явно отмечено. QUIC — число fake-повторов в исходном правиле общего hostlist, **который не содержит домены из `list-google.txt`**. Это не число повторов для YouTube.

| Файл | Профили | Метод Google TCP | Существенные параметры этого правила | QUIC повторы |
|---|---:|---|---|---:|
| `general.bat` | 9 | `multisplit` | `split-pos=1`; `split-seqovl=681` | 6 |
| `general (ALT).bat` | 9 | `fake,fakedsplit` | `repeats=6`; `fooling=ts` | 6 |
| `general (ALT10).bat` | 9 | `fake` | `repeats=6`; `fooling=ts` | 6 |
| `general (ALT11).bat` | 9 | `fake,multisplit` | `split-pos=1`; `split-seqovl=681`; `repeats=8`; `fooling=ts` | 11 |
| `general (ALT12).bat` | 9 | `hostfakesplit` | `fooling=ts`; `hostfakesplit-mod=host=www.google.com` | 11 |
| `general (ALT13).bat` | 9 | `hostfakesplit` | `fooling=ts`; `hostfakesplit-mod=host=www.google.com` | 11 |
| `general (ALT2).bat` | 9 | `multisplit` | `split-pos=2`; `split-seqovl=652` | 6 |
| `general (ALT3).bat` | 9 | `fake,hostfakesplit` | `fooling=ts`; `fake-tls-mod=rnd,dupsid,sni=www.google.com`; `hostfakesplit-mod=host=www.google.com,altorder=1` | 6 |
| `general (ALT4).bat` | 9 | `fake,multisplit` | `repeats=6`; `fooling=badseq`; `badseq-increment=1000` | 6 |
| `general (ALT5).bat` | 6 | `syndata,multidisorder` | `широкий IPv4 TCP, без hostlist` | 6 |
| `general (ALT6).bat` | 9 | `multisplit` | `split-pos=1`; `split-seqovl=681` | 6 |
| `general (ALT7).bat` | 9 | `multisplit` | `split-pos=2,sniext+1`; `split-seqovl=679` | 6 |
| `general (ALT8).bat` | 9 | `fake` | `repeats=6`; `fooling=badseq`; `badseq-increment=2`; `fake-tls-mod=none` | 6 |
| `general (ALT9).bat` | 9 | `hostfakesplit` | `repeats=4`; `fooling=ts`; `hostfakesplit-mod=host=www.google.com` | 6 |
| `general (EXP).bat` | 9 | `hostfakesplit` | `fooling=ts`; `hostfakesplit-mod=host=www.google.com` | 11 |
| `general (FAKE TLS AUTO ALT).bat` | 9 | `fake,fakedsplit` | `split-pos=1`; `repeats=8`; `fooling=badseq`; `badseq-increment=2`; `fake-tls-mod=rnd,dupsid,sni=www.google.com` | 11 |
| `general (FAKE TLS AUTO ALT2).bat` | 9 | `fake,multisplit` | `split-pos=1`; `split-seqovl=681`; `repeats=8`; `fooling=badseq`; `badseq-increment=10000000`; `fake-tls-mod=rnd,dupsid,sni=www.google.com` | 11 |
| `general (FAKE TLS AUTO ALT3).bat` | 9 | `fake,multisplit` | `split-pos=1`; `split-seqovl=681`; `repeats=8`; `fooling=ts`; `fake-tls-mod=rnd,dupsid,sni=www.google.com` | 11 |
| `general (FAKE TLS AUTO).bat` | 9 | `fake,multidisorder` | `split-pos=1,midsld`; `repeats=11`; `fooling=badseq`; `fake-tls-mod=rnd,dupsid,sni=www.google.com` | 11 |
| `general (SIMPLE FAKE ALT).bat` | 9 | `fake` | `repeats=6`; `fooling=badseq`; `badseq-increment=2` | 6 |
| `general (SIMPLE FAKE ALT2).bat` | 9 | `fake` | `repeats=6`; `fooling=ts` | 6 |
| `general (SIMPLE FAKE).bat` | 9 | `hostfakesplit` | `fooling=ts`; `hostfakesplit-mod=host=www.google.com` | 6 |

## Что следует из таблицы

- Все обычные профили используют общий hostlist для QUIC и отдельный Google hostlist для TCP. Домены YouTube не входят в общий список. В EXP первое QUIC-правило задано через L7 `quic`, но hostlist также общий.
- `general.bat`, ALT2, ALT6, ALT7 используют multisplit с разными позициями и перекрытием. Изменение одной позиции может менять результат у конкретного DPI; эффективность не выводится из имени файла.
- ALT, ALT3, ALT9–13, EXP и SIMPLE FAKE содержат варианты `ts`. Они зависят от корректного поведения TCP timestamps. Новый минимальный профиль наследует multisplit из `general.bat`, не требует включения глобальных timestamps специально ради fake-fooling=ts.
- FAKE TLS AUTO и варианты генерируют/модифицируют fake TLS; больше повторов не означает выше стабильность. Число профилей и повторов не позволяет вычислить нагрузку без измерения фактического трафика.
- **ALT5 помечен авторами `NOT RECOMMENDED`**. Его третий профиль — IPv4 TCP 80,443,2053,2083,2087,2096,8443 без hostlist/IPSet и без доменных исключений. Он может обрабатывать Steam HTTPS даже при выключенном Game Filter и IPSet `none`. Для цели минимального вмешательства непригоден.
- **EXP** добавляет `unknown` и `any-protocol=1` в UDP-профиль 19294–19344,50000–50100. На этих портах это потенциально затрагивает другой UDP-трафик, включая игры; наличие Game Filter не определяет действие этого отдельного профиля.
- Различия профилей Discord, общих доменов и игровых правил остаются существенными, даже когда Google TCP совпадает. Таблица не утверждает полную эквивалентность таких файлов.

## Выбор для первого контролируемого испытания

Новый профиль оставляет базовый `multisplit`, `split-pos=1`, `split-seqovl=681` и оригинальный Google TLS-шаблон; QUIC — оригинальный Google Initial fake с 6 повторами. Изменяется прежде всего область применения: отдельный список YouTube для TCP и UDP 443, без Game/IPSet и широких Discord-портов. Это обоснованный исходный кандидат для A/B, **не доказанная оптимальная стратегия для вашего провайдера**.

Если сайт открывается, но видео зависает, сравните полный профиль с вариантом TCP-only при принудительном HTTP/2 в диагностическом клиенте. TCP-only сам по себе не запрещает браузеру QUIC и не гарантирует его переключение на TCP. Не меняйте одновременно DNS, браузер и стратегию: тогда исчезает возможность установить причину улучшения.
