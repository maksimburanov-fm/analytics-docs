# spark_dm.pay_transactions

## Назначение и гранулярность

`spark_dm.pay_transactions` содержит успешные платежи с нормализованным телефоном. Одна строка соответствует сочетанию `phone`, `order_id`, `merchant_id`, `cr_date`.

Source view формируется скриптом `dwh/datamarts/pay_transaction.sql` и возвращает шесть полей без изменения схемы целевой таблицы:

- `phone`;
- `order_id`;
- `merchant_id`;
- `price`;
- `cr_date`;
- `bank_alias`.

Телефон берется из `user_phone`; если он пуст после нормализации, используется телефон из `msp_ref_users`, найденный по `param1 = user_id`. Логика восстановления по `pan_mask` удалена. Для `merchant_id = 563748` сохраняется правило `bank_alias = 'superapp'`.

## Граница новой логики

Дата перехода — `2025-05-01`.

- строки с `cr_date < DATE '2025-05-01'` остаются в target в текущем виде;
- новая версия source view применяется только к секциям с `cr_date >= DATE '2025-05-01'`;
- ни ежедневный запуск, ни ручной backfill не должны начинаться раньше этой даты;
- фиксированный фильтр даты в source view намеренно отсутствует: диапазон передает платформа по `SECTION_KEY`, а исторические строки защищает конфигурация запуска.

Если запустить `INC` без дат или выполнить `FULL`, старая история может быть пересчитана уже без `pan_mask`. Такой запуск для этой миграции запрещен.

## Конфигурация инкремента

Параметры метаданных:

- target: `PAY_TRANSACTIONS`;
- source view: `VW_PAY_TRANSACTIONS`;
- код процесса: `BV_TO_DM`;
- тип репликации: `INC`;
- `SECTION_KEY`: `cr_date`;
- отчетный период: день.

`INC` удаляет выбранные секции target по `cr_date` и вставляет их заново. Поэтому `cr_date` включен в `GROUP BY` source view, а внешний фильтр по нему проталкивается до чтения `msp_ref_pay_transactions`.

Диапазон обязан передаваться внешним Airflow/`AutoManagerDagRun`. Рекомендуемое ежедневное окно:

```text
begin_date = current_date - 7
end_date   = current_date - 1
```

Семь дней покрывают обычную задержку источника в один-два дня. Исторические дозагрузки нужно обнаруживать отдельно по `t_w_loaddate` и пересчитывать только затронутые даты, но не раньше `2025-05-01`.

## Порядок перехода

1. Остановить текущий запуск или выключить витрину до замены source view. Сейчас запуск с пустыми границами фактически пересчитывает всю историю.
2. Установить новую версию `VW_PAY_TRANSACTIONS`.
3. Настроить обязательную передачу `begin_date` и `end_date` из `AutoManagerDagRun`.
4. Один раз пересчитать диапазон от `2025-05-01` до последней закрытой даты. Для снижения риска выполнять backfill последовательными диапазонами не больше 31 дня.
5. Проверить количество строк и сумму `price` по каждому дню, сохранность истории до отсечки и идемпотентность повторного запуска одного диапазона.
6. Включить ежедневное семидневное окно.
7. После приемки данных выполнить согласованный `VACUUM`/компактацию target.

Перед первым шагом нужно сохранить агрегаты истории до отсечки:

```sql
SELECT
    COUNT(*) AS row_count,
    SUM(price) AS total_price,
    MIN(cr_date) AS min_cr_date,
    MAX(cr_date) AS max_cr_date
FROM spark_dm.pay_transactions
WHERE cr_date < DATE '2025-05-01';
```

После backfill результат этого запроса должен полностью совпасть с исходным.

## Проверки качества

Сверка source view и target для одного пересчитанного диапазона:

```sql
WITH source_stats AS (
    SELECT cr_date, COUNT(*) AS row_count, SUM(price) AS total_price
    FROM VW_PAY_TRANSACTIONS
    WHERE cr_date BETWEEN :begin_date AND :end_date
    GROUP BY cr_date
),
target_stats AS (
    SELECT cr_date, COUNT(*) AS row_count, SUM(price) AS total_price
    FROM spark_dm.pay_transactions
    WHERE cr_date BETWEEN :begin_date AND :end_date
    GROUP BY cr_date
)
SELECT
    COALESCE(s.cr_date, t.cr_date) AS cr_date,
    s.row_count AS source_rows,
    t.row_count AS target_rows,
    s.total_price AS source_price,
    t.total_price AS target_price
FROM source_stats s
FULL JOIN target_stats t USING (cr_date)
WHERE s.row_count IS DISTINCT FROM t.row_count
   OR s.total_price IS DISTINCT FROM t.total_price
ORDER BY cr_date;
```

Также обязательны проверки:

- повторный запуск одного диапазона не меняет количество строк и сумму;
- в target нет дублей по `phone`, `order_id`, `merchant_id`, `cr_date`;
- `bank_alias = 'superapp'` для `merchant_id = 563748`;
- операции без телефона и без найденного пользователя по `param1` не попадают в витрину;
- история до `2025-05-01` не изменилась;
- `EXPLAIN` контрольного запроса показывает фильтр по `date(created_at)` на скане `msp_ref_pay_transactions`.

Проверка поздних исторических дозагрузок:

```sql
SELECT
    MIN(created_at::date) AS min_affected_date,
    MAX(created_at::date) AS max_affected_date,
    COUNT(*) AS source_rows
FROM spark_bsns_vlt.msp_ref_pay_transactions
WHERE t_w_loaddate >= current_date - INTERVAL '1 day'
  AND created_at::date >= DATE '2025-05-01'
  AND created_at::date < current_date - 7;
```

Если запрос возвращает строки, затронутые даты нужно передать отдельным backfill-запуском.
