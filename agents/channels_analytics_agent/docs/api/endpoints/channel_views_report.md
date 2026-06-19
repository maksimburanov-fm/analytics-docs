# Отчёт по просмотрам телеканалов

## Назначение

Метод возвращает агрегированный отчёт по просмотрам телеканалов за выбранный период с фильтрами по каналам, провайдерам, устройствам, типу просмотра, пакетам и состоянию пользователя.

## Endpoint

```http
POST https://reports-freedommedia.platform24.tv/api/queries/18/results
```

## Авторизация

Токен передаётся в HTTP-header `authorization`.

Формат значения:

```http
authorization: Key <REPORT_API_TOKEN>
```

Пример:

```http
authorization: Key gjkgkgkgkDJHJSDAM4pCpw
```

Важно: для этого метода используется префикс `Key`. Формат `Bearer <token>` не используется.


## Тело запроса

```json
{
  "id": 18,
  "parameters": {
    "channel": ["0"],
    "period": {
      "start": "2026-06-01",
      "end": "2026-06-07"
    },
    "provider": ["0"],
    "application_type": ["'all'"],
    "sort_field": "user_c",
    "is_live": "все",
    "packet": ["0"],
    "user_state": ["'all'"]
  },
  "apply_auto_limit": false
}
```

## Параметры запроса

| parameter | type | required | example | description | allowed_values |
|---|---|---:|---|---|---|
| `id` | integer | yes | `18` | ID сохранённого запроса отчёта. Для этого метода всегда `18`. | `18` |
| `parameters.channel` | array[string] | yes | `["0"]` | Список id телеканалов. `"0"` означает все доступные каналы. Для запроса по конкретным каналам нужно взять id из справочника телеканалов. | `"0"` или список id из справочника телеканалов |
| `parameters.period.start` | string/date | yes | `"2026-06-01"` | Дата начала отчётного периода включительно. | Формат `YYYY-MM-DD` |
| `parameters.period.end` | string/date | yes | `"2026-06-07"` | Дата конца отчётного периода включительно. | Формат `YYYY-MM-DD` |
| `parameters.provider` | array[string] | yes | `["0"]` | Список id провайдеров, по просмотрам пользователей которых нужен отчёт. `"0"` означает все доступные провайдеры. | `"0"` или список id из справочника провайдеров |
| `parameters.application_type` | array[string] | yes | `["'all'"]` | Список типов устройств. `["'all'"]` означает все устройства. Важно: значения кроме `all` передаются со внутренними одинарными кавычками. | `["'all'"], ["'android-mobile'"], ["'android-tv'"], ["'ios'"], ["'tvos'"], ["'webkit'"], ["'web'"], ["'dune'"]` |
| `parameters.sort_field` | string | yes | `"user_c"` | Поле сортировки результата. Сейчас безопасное значение по умолчанию — `user_c`. | `user_c` |
| `parameters.is_live` | string | yes | `"все"` | Тип просмотра. `все` — все типы; `эфир` — live-просмотр в момент трансляции; `запись` — catch-up просмотр. Не все телеканалы поддерживают записи. | `"все"`, `"эфир"`, `"запись"` |
| `parameters.packet` | array[string] | yes | `["0"]` | Список id пакетов. `"0"` означает все доступные пакеты. | `"0"` или список id из справочника пакетов |
| `parameters.user_state` | array[string] | yes | `["'all'"]` | Тип пользователя. Важно: значения передаются со внутренними одинарными кавычками. | `["'all'"], ["'free'"], ["'guest'"], ["'promo'"], ["'full_payment'"], ["'trial'"]` |
| `apply_auto_limit` | boolean | yes | `false` | Автоматическое ограничение выдачи. Для этого метода использовать `false`. | `false` |

## Поля ответа

Данные находятся в JSON-ответе по пути:

```text
query_result.data.rows
```

| field | type | description | business_logic |
|---|---|---|---|
| `num` | integer | Номер строки в результате | Порядковый номер строки в выдаче. |
| `channel_name` | string | Название телеканала | Отображаемое название канала. |
| `session_c` | integer | Количество сессий просмотра | Количество сессий просмотра одного телеканала. При прерывании просмотра создаётся новая сессия. |
| `user_c` | integer | Количество пользователей | Количество уникальных пользователей, которые просматривали канал за период. |
| `user_5min_c` | integer | Количество пользователей с просмотром больше 5 минут | Количество пользователей, которые просматривали канал более 300 секунд. Считается сумма всех сессий пользователя по каналу. |
| `view_time_h` | float | Общее время просмотра в часах | Суммарное время просмотра телеканала в часах. |
| `median_view_time_m` | float | Медианное время просмотра в минутах | Медиана времени просмотра в минутах. |

## Справочники

Актуальные id каналов, провайдеров и пакетов ведутся отдельно в Google Sheets:

| dictionary | URL |
|---|---|
| Телеканалы | https://docs.google.com/spreadsheets/d/e/2PACX-1vQ0CtKBvuvSGsjAve6o3WYAViB3ALx5zipmrpNNItN89oDO3RQgCH_IBefZ66yiyfEoujbwZHgYWaMd/pub?gid=0&single=true&output=csv |
| Провайдеры | https://docs.google.com/spreadsheets/d/e/2PACX-1vRT3LziYqZHcLREhd0K6pMCpfqeHQVN2iH3M0a-CLj3shgzEobZuM3waJ6WgInD3oRvt5xMg0eBswMc/pub?gid=0&single=true&output=csv |
| Пакеты | https://docs.google.com/spreadsheets/d/e/2PACX-1vS6-qVAuiYdvJJXqQKcfDRLnRu6emBOo0ihGNTpkaNAei1IQ-ohyY0PPtUXVMm7N4s3AIx4NaCO0_F4/pub?gid=0&single=true&output=csv |

## Правила для агента

1. Если пользователь задаёт канал, провайдера или пакет названием, сначала получить соответствующий справочник и найти нужный id.
2. Если пользователь не указал канал, использовать `channel: ["0"]`.
3. Если пользователь не указал провайдера, использовать `provider: ["0"]`.
4. Если пользователь не указал пакет, использовать `packet: ["0"]`.
5. Если пользователь не указал тип устройства, использовать `application_type: ["'all'"]`.
6. Если пользователь не указал тип просмотра, использовать `is_live: "все"`.
7. Если пользователь не указал тип пользователя, использовать `user_state: ["'all'"]`.
8. `apply_auto_limit` всегда передавать как `false`.
9. Не придумывать данные: если API вернул ошибку или пустой ответ, прямо сообщить об этом.

## Пример ответа

Пример выгрузки лежит в файле:

```text
examples/channel_views_response_example.csv
```
