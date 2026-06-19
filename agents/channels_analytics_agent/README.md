# Freedom Media API Docs MVP

Первый комплект файлов для Custom GPT Action по отчёту просмотров телеканалов.

## Файлы

- `openapi/fm_reports_actions.yaml` — схема для Custom GPT Actions.
- `docs/api/endpoints/channel_views_report.md` — Markdown-документация метода.
- `docs/dictionaries/google_sheets_sources.md` — ссылки на справочники Google Sheets.
- `examples/channel_views_response_example.csv` — пример ответа.
- `custom_gpt_instructions.md` — текст инструкций для Custom GPT.

## Как использовать

1. Вставить `openapi/fm_reports_actions.yaml` в Custom GPT → Configure → Actions → Schema.
2. В Authentication выбрать API Key → Custom header.
3. Header name: `authorization`.
4. Value: токен отчётного API в том форматеe, который ожидает API.
5. В Instructions вставить текст из `custom_gpt_instructions.md`.
