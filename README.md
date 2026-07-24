# Analytics Documentation

Репозиторий хранит документацию и воспроизводимые аналитические материалы
Freedom Media:

- событийную модель web-зоны, собранную из GTM-контейнера;
- описания источников и витрин DWH;
- SQL, методологии и результаты продуктовых исследований;
- справочники и бизнес-маппинги;
- проектную настройку read-only подключения к Greenplum.

Документация ведётся в Git, чтобы изменения аналитической логики, схем данных и
результатов исследований можно было проследить и проверить.

## Быстрая навигация

| Направление | Точка входа | Что внутри |
|---|---|---|
| Событийная модель | [`events/README.md`](events/README.md) | Связи GTM-триггеров, тегов, параметров и унифицированных событий |
| User properties Amplitude | [`events/amplitude_user_properties/README.md`](events/amplitude_user_properties/README.md) | Текущая логика установки `user_id`, `lang`, `profile_type`, `is_logged`, `provider_id` и `packets_list` |
| DWH | [`dwh/`](dwh/) | SQL витрин и документация таблиц `spark_bsns_vlt` и `spark_dm` |
| Исследования | [`analyses/`](analyses/) | Дизайн исследований, SQL, ноутбуки, графики, технические и менеджерские отчёты |
| GTM | [`gtm/`](gtm/) | JSON-экспорт контейнера и каталоги для версий документации |
| Greenplum | [`docs/07_mcp_connections.md`](docs/07_mcp_connections.md) | Настройка, проверка и диагностика read-only подключения |

Файлы `docs/01_overview.md` — `docs/06_data_sources.md`, а также CSV в
`dictionaries/` пока являются заготовками и не содержат документации.

## Структура репозитория

```text
analytics-docs/
├── .codex/
│   ├── config.toml
│   └── scripts/                         # запуск и проверка Greenplum MCP
├── analyses/
│   ├── first_subscription_renewal/      # поведение в первой подписке и продление
│   ├── june_churn/                      # анализ июньского оттока
│   ├── june_failed_payment_churn/       # отток после неудачного списания
│   ├── manual_churn_export/             # SQL точечной выгрузки оттока
│   └── trial_retention_30d_vs_7d/       # сравнение удержания trial-когорт
├── dictionaries/                        # заготовки общих справочников
├── docs/                                # общая документация и подключения
├── dwh/
│   ├── datamarts/                       # SQL витрин и описания spark_dm
│   └── sources/spark_bsns_vlt/          # документация таблиц-источников
├── events/
│   ├── amplitude_user_properties/
│   ├── scripts/                         # генерация CSV из GTM JSON
│   ├── README.md
│   └── *.csv                            # технический и бизнес-слои событий
├── gtm/
│   ├── containers/                      # исходные JSON-экспорты GTM
│   ├── exports/
│   └── changelog.md
└── README.md
```

## Событийная модель и GTM

Актуальная событийная документация относится к событиям web-зоны `fmedia.kz`,
настроенным через Google Tag Manager. Она покрывает desktop web, mobile web,
webview-сценарии приложений и Freedom SuperApp miniapp. Платформу нельзя
определять только по названию события: необходимо учитывать URL, параметры
страницы и источник отправки.

Технический слой строится из GTM-экспорта:

```text
gtm/containers/*.json
  → events/scripts/generate_gtm_documentation_csv.py
  → triggers_from_gtm.csv
  → trigger_parameters.csv
  → tag_trigger_map_from_gtm.csv
  → tag_trigger_eventtype_issues.csv
  → tag_params_from_gtm.csv
  → tag_params_extraction_issues.csv
```

Сгенерированные CSV используют разделитель `;` и кодировку `UTF-8 with BOM`.
Пересобрать их из текущего контейнера можно командой:

```powershell
python .\events\scripts\generate_gtm_documentation_csv.py `
  --input .\gtm\containers\GTM-KJCRRRRC_workspace221.json `
  --output .\events
```

Скрипт не создаёт бизнес-маппинг событий. Унифицированные идентификаторы и
описания поддерживаются отдельно в:

- [`events/dictionary.csv`](events/dictionary.csv);
- [`events/event_descriptions.csv`](events/event_descriptions.csv);
- [`events/event_descriptions_lookup_from_documentation.csv`](events/event_descriptions_lookup_from_documentation.csv).

Основной аналитический ключ — `unified_event_id`. Технические `event_name` могут
различаться между Amplitude, web-аналитикой и bridge-событиями SuperApp.

## DWH

Каталог [`dwh/sources/spark_bsns_vlt/`](dwh/sources/spark_bsns_vlt/) содержит
описания таблиц подписок, платежей, VOD- и TV-сессий и каталога контента:

- `msp_ref_subscriptions`;
- `msp_ref_pay_transactions`;
- `msp_content_session`;
- `msp_ref_tv_session`;
- `msp_ref_catalog_content`.

В [`dwh/datamarts/`](dwh/datamarts/) находятся SQL-определения продуктовых и
маркетинговых витрин. Для трёх витрин `spark_dm` есть отдельная документация:

- [`spark_dm.subscriptions_with_revenue`](dwh/datamarts/spark_dm/subscriptions_with_revenue.md);
- [`spark_dm.full_catalog`](dwh/datamarts/spark_dm/full_catalog.md);
- [`spark_dm.user_watch_sub_promo`](dwh/datamarts/spark_dm/user_watch_sub_promo.md).

Документация таблицы должна фиксировать гранулярность, источники, ключевые поля,
логику расчёта, проверки качества и ограничения использования.

## Исследования

Каждое исследование хранится в отдельном каталоге и по возможности включает
исходный SQL, методологию, воспроизводимый анализ и итоговый отчёт.

| Исследование | Результат |
|---|---|
| [`first_subscription_renewal`](analyses/first_subscription_renewal/report.md) | Влияние смотрения и поведения во время первой подписки на продление; есть дизайн, SQL, ноутбук, графики и менеджерский отчёт |
| [`june_churn`](analyses/june_churn/report.md) | Динамика и структура июньского оттока, платёжные сценарии и активность перед уходом |
| [`june_failed_payment_churn`](analyses/june_failed_payment_churn/report.md) | Профиль пользователей, ушедших после неудачной попытки списания |
| [`trial_retention_30d_vs_7d`](analyses/trial_retention_30d_vs_7d/report.md) | Сравнение удержания первых trial-подписок длительностью 30 и 7 дней |
| [`manual_churn_export`](analyses/manual_churn_export/sql/manual_churn_2026_07_07_08.sql) | Отдельный SQL-сценарий для точечной задачи по оттоку |

В репозиторий не следует добавлять сырые пользовательские выгрузки. Итоговые
материалы должны содержать агрегированные результаты, а персональные данные и
пользовательские идентификаторы — оставаться внутри SQL-обработки.

## Подключение к Greenplum

Проектное подключение называется `fmedia_gp` и работает в restricted/read-only
режиме. Для него нужны корпоративный VPN, запущенный Docker Desktop и
пользовательская переменная среды Windows `DATABASE_URI`.

Проверка локальной настройки:

```powershell
.\.codex\scripts\check-fmedia-gp.cmd
```

После успешной проверки соединение подтверждается коротким запросом:

```sql
SELECT 1 AS test_connection;
```

Полная инструкция, включая первичную загрузку Docker-образа и диагностику
ошибок, находится в
[`docs/07_mcp_connections.md`](docs/07_mcp_connections.md). Строки подключения,
пароли, токены и другие секреты нельзя сохранять в Git или вставлять в
документацию.

## Форматы хранения

- Markdown — документация, методология и отчёты.
- CSV с разделителем `;` — событийные таблицы и справочники.
- SQL — определения витрин и воспроизводимые аналитические запросы.
- JSON — экспорты GTM-контейнера.
- Jupyter Notebook и PNG — расчёты и визуализации отдельных исследований.

## Правила работы

1. Одно логическое изменение оформляется отдельным коммитом с понятным
   названием.
2. Перед коммитом нужно проверить `git diff` и убедиться, что в изменениях нет
   секретов, персональных данных и сырых пользовательских выгрузок.
3. GTM JSON проверяется на токены, ключи и чувствительные значения до добавления
   в репозиторий.
4. Технические CSV из GTM пересобираются скриптом; бизнес-маппинги и описания
   событий ведутся вручную.
5. Изменение логики DWH-витрины сопровождается обновлением соответствующей
   документации.
6. Аналитические запросы к DWH должны быть read-only, выполнять тяжёлую
   обработку в SQL и возвращать агрегированные результаты.
