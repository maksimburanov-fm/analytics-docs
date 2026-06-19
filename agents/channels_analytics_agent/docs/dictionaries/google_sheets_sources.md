# Источники справочников

Справочники ведутся в Google Sheets и опубликованы как CSV. Их можно подключать как отдельные `GET`-методы в Custom GPT Actions.

| Справочник | Назначение | URL |
|---|---|---|
| `channels` | Поиск `channel_id` по названию телеканала | https://docs.google.com/spreadsheets/d/e/2PACX-1vQ0CtKBvuvSGsjAve6o3WYAViB3ALx5zipmrpNNItN89oDO3RQgCH_IBefZ66yiyfEoujbwZHgYWaMd/pub?gid=0&single=true&output=csv |
| `providers` | Поиск `provider_id` по названию провайдера | https://docs.google.com/spreadsheets/d/e/2PACX-1vRT3LziYqZHcLREhd0K6pMCpfqeHQVN2iH3M0a-CLj3shgzEobZuM3waJ6WgInD3oRvt5xMg0eBswMc/pub?gid=0&single=true&output=csv |
| `packets` | Поиск `packet_id` по названию пакета | https://docs.google.com/spreadsheets/d/e/2PACX-1vS6-qVAuiYdvJJXqQKcfDRLnRu6emBOo0ihGNTpkaNAei1IQ-ohyY0PPtUXVMm7N4s3AIx4NaCO0_F4/pub?gid=0&single=true&output=csv |

## Рекомендованные колонки

### channels

```csv
channel_id,	channel_name,	slag_on_website,	days_catchup,	category
```

### providers

```csv
provider_id, provider_name, type(prod/test), status, description
```

### packets

```csv
packet_id,	packet_name, price,	type(prod/test),	add_to_providers
```

## Правило обновления

Git хранит описание и ссылки на источники. Актуальные значения справочников берутся из опубликованных CSV-ссылок Google Sheets.
