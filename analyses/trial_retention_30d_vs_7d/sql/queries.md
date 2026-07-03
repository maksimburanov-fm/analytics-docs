# SQL-запросы для анализа retention 30-day vs 7-day trial

Все запросы read-only, без создания физических таблиц. Промежуточные наборы собраны через CTE.

## 1. Структура таблицы

```sql
-- MCP object details:
-- schema_name = 'spark_bsns_vlt'
-- object_name = 'msp_ref_subscriptions'
-- object_type = 'table'
```

## 2. Cutoff данных

```sql
select
    max(start_date) as max_start_date,
    max(end_date) as max_end_date,
    count(*) as rows_total
from spark_bsns_vlt.msp_ref_subscriptions
where provider in ('Freedom Media', 'SuperApp');
```

## 3. Значения type

```sql
select type, count(*) as rows_cnt
from spark_bsns_vlt.msp_ref_subscriptions
where provider in ('Freedom Media', 'SuperApp')
group by type
order by rows_cnt desc;
```

## 4. Значения groups

```sql
select groups, count(*) as rows_cnt
from spark_bsns_vlt.msp_ref_subscriptions
where provider in ('Freedom Media', 'SuperApp')
  and start_date >= timestamp '2026-05-01'
  and start_date < timestamp '2026-07-01'
group by groups
order by rows_cnt desc
limit 100;
```

## 5. Основные метрики по когортам

```sql
with ordered as (
    select
        user_id, start_date, end_date, type, packet, packet_id, provider, groups, t_w_srcid,
        row_number() over (partition by user_id order by start_date, end_date, t_w_srcid) as sub_num
    from spark_bsns_vlt.msp_ref_subscriptions
    where provider in ('Freedom Media', 'SuperApp')
      and user_id is not null
      and start_date is not null
      and end_date is not null
      and (
          groups is null
          or (
              lower(groups) not like '%test%'
              and lower(groups) not like '%demo%'
              and lower(groups) not like '%демо%'
              and lower(groups) not like '%нагруз%'
              and lower(groups) not like '%alga%'
              and lower(groups) not like '%алга%'
          )
      )
),
pairs as (
    select
        f.user_id,
        f.provider,
        case
            when f.start_date >= timestamp '2026-05-01' and f.start_date < timestamp '2026-06-01' then 'May 2026 / 30-day trial'
            when f.start_date >= timestamp '2026-06-01' and f.start_date < timestamp '2026-07-01' then 'June 2026 / 7-day trial'
        end as cohort,
        case
            when f.start_date >= timestamp '2026-05-01' and f.start_date < timestamp '2026-06-01' then 30
            when f.start_date >= timestamp '2026-06-01' and f.start_date < timestamp '2026-07-01' then 7
        end as trial_length,
        f.start_date as first_start_date,
        f.end_date as first_end_date,
        s.start_date as second_start_date,
        s.type as second_type,
        s.packet as second_packet,
        s.packet_id as second_packet_id,
        extract(epoch from (s.start_date - f.end_date)) / 86400.0 as gap_days
    from ordered f
    left join ordered s
      on s.user_id = f.user_id
     and s.sub_num = 2
    where f.sub_num = 1
      and f.type = 'trial'
      and (
          (
              f.start_date >= timestamp '2026-05-01'
              and f.start_date < timestamp '2026-06-01'
              and extract(epoch from (f.end_date - f.start_date)) / 86400.0 between 28 and 32
          )
          or (
              f.start_date >= timestamp '2026-06-01'
              and f.start_date < timestamp '2026-07-01'
              and extract(epoch from (f.end_date - f.start_date)) / 86400.0 between 6 and 8
          )
      )
),
data_cutoff as (
    select max(start_date) as max_observed_start_date
    from spark_bsns_vlt.msp_ref_subscriptions
    where provider in ('Freedom Media', 'SuperApp')
)
select
    p.cohort,
    p.trial_length,
    count(*) as users,
    count(*) filter (where p.second_start_date is not null) as users_with_second_subscription_observed,
    round((count(*) filter (where p.second_start_date is not null))::numeric / nullif(count(*), 0), 4) as observed_second_sub_rate,
    count(*) filter (where p.first_end_date + interval '0 day' <= d.max_observed_start_date) as eligible_0d,
    count(*) filter (
        where p.first_end_date + interval '0 day' <= d.max_observed_start_date
          and p.second_start_date <= p.first_end_date + interval '0 day'
    ) as retained_0d,
    round((count(*) filter (
        where p.first_end_date + interval '0 day' <= d.max_observed_start_date
          and p.second_start_date <= p.first_end_date + interval '0 day'
    ))::numeric / nullif(count(*) filter (
        where p.first_end_date + interval '0 day' <= d.max_observed_start_date
    ), 0), 4) as retention_0d,
    count(*) filter (where p.first_end_date + interval '3 day' <= d.max_observed_start_date) as eligible_3d,
    count(*) filter (
        where p.first_end_date + interval '3 day' <= d.max_observed_start_date
          and p.second_start_date <= p.first_end_date + interval '3 day'
    ) as retained_3d,
    round((count(*) filter (
        where p.first_end_date + interval '3 day' <= d.max_observed_start_date
          and p.second_start_date <= p.first_end_date + interval '3 day'
    ))::numeric / nullif(count(*) filter (
        where p.first_end_date + interval '3 day' <= d.max_observed_start_date
    ), 0), 4) as retention_3d,
    count(*) filter (where p.first_end_date + interval '7 day' <= d.max_observed_start_date) as eligible_7d,
    count(*) filter (
        where p.first_end_date + interval '7 day' <= d.max_observed_start_date
          and p.second_start_date <= p.first_end_date + interval '7 day'
    ) as retained_7d,
    round((count(*) filter (
        where p.first_end_date + interval '7 day' <= d.max_observed_start_date
          and p.second_start_date <= p.first_end_date + interval '7 day'
    ))::numeric / nullif(count(*) filter (
        where p.first_end_date + interval '7 day' <= d.max_observed_start_date
    ), 0), 4) as retention_7d,
    count(*) filter (where p.first_end_date + interval '14 day' <= d.max_observed_start_date) as eligible_14d,
    round((count(*) filter (
        where p.first_end_date + interval '14 day' <= d.max_observed_start_date
          and p.second_start_date <= p.first_end_date + interval '14 day'
    ))::numeric / nullif(count(*) filter (
        where p.first_end_date + interval '14 day' <= d.max_observed_start_date
    ), 0), 4) as retention_14d,
    count(*) filter (where p.first_end_date + interval '30 day' <= d.max_observed_start_date) as eligible_30d,
    round((count(*) filter (
        where p.first_end_date + interval '30 day' <= d.max_observed_start_date
          and p.second_start_date <= p.first_end_date + interval '30 day'
    ))::numeric / nullif(count(*) filter (
        where p.first_end_date + interval '30 day' <= d.max_observed_start_date
    ), 0), 4) as retention_30d,
    round((avg(p.gap_days) filter (where p.second_start_date is not null))::numeric, 2) as avg_gap_days,
    min(p.first_end_date) as min_first_end_date,
    max(p.first_end_date) as max_first_end_date,
    max(d.max_observed_start_date) as max_observed_start_date
from pairs p
cross join data_cutoff d
group by p.cohort, p.trial_length
order by p.trial_length desc;
```

## 6. Медианный gap

```sql
with ordered as (
    select
        user_id, start_date, end_date, type, packet, packet_id, provider, groups, t_w_srcid,
        row_number() over (partition by user_id order by start_date, end_date, t_w_srcid) as sub_num
    from spark_bsns_vlt.msp_ref_subscriptions
    where provider in ('Freedom Media', 'SuperApp')
      and user_id is not null
      and start_date is not null
      and end_date is not null
      and (
          groups is null
          or (
              lower(groups) not like '%test%'
              and lower(groups) not like '%demo%'
              and lower(groups) not like '%демо%'
              and lower(groups) not like '%нагруз%'
              and lower(groups) not like '%alga%'
              and lower(groups) not like '%алга%'
          )
      )
),
pairs as (
    select
        f.user_id,
        case
            when f.start_date >= timestamp '2026-05-01' and f.start_date < timestamp '2026-06-01' then 'May 2026 / 30-day trial'
            when f.start_date >= timestamp '2026-06-01' and f.start_date < timestamp '2026-07-01' then 'June 2026 / 7-day trial'
        end as cohort,
        extract(epoch from (s.start_date - f.end_date)) / 86400.0 as gap_days
    from ordered f
    join ordered s
      on s.user_id = f.user_id
     and s.sub_num = 2
    where f.sub_num = 1
      and f.type = 'trial'
      and (
          (
              f.start_date >= timestamp '2026-05-01'
              and f.start_date < timestamp '2026-06-01'
              and extract(epoch from (f.end_date - f.start_date)) / 86400.0 between 28 and 32
          )
          or (
              f.start_date >= timestamp '2026-06-01'
              and f.start_date < timestamp '2026-07-01'
              and extract(epoch from (f.end_date - f.start_date)) / 86400.0 between 6 and 8
          )
      )
),
ranked as (
    select
        cohort,
        gap_days,
        row_number() over (partition by cohort order by gap_days) as rn,
        count(*) over (partition by cohort) as cnt
    from pairs
)
select
    cohort,
    round(avg(gap_days)::numeric, 2) as median_gap_days
from ranked
where rn in ((cnt + 1) / 2, (cnt + 2) / 2)
group by cohort
order by cohort;
```

## 7. Provider metrics

Provider query uses the same `ordered`, `pairs`, and `data_cutoff` CTE definitions as the main query, then aggregates by provider:

```sql
select
    p.cohort,
    p.trial_length,
    p.provider,
    count(*) as users,
    count(*) filter (where p.second_start_date is not null) as users_with_second_subscription_observed,
    round((count(*) filter (where p.second_start_date is not null))::numeric / nullif(count(*), 0), 4) as observed_second_sub_rate,
    count(*) filter (where p.first_end_date + interval '3 day' <= d.max_observed_start_date) as eligible_3d,
    round((count(*) filter (
        where p.first_end_date + interval '3 day' <= d.max_observed_start_date
          and p.second_start_date <= p.first_end_date + interval '3 day'
    ))::numeric / nullif(count(*) filter (
        where p.first_end_date + interval '3 day' <= d.max_observed_start_date
    ), 0), 4) as retention_3d,
    count(*) filter (where p.first_end_date + interval '7 day' <= d.max_observed_start_date) as eligible_7d,
    round((count(*) filter (
        where p.first_end_date + interval '7 day' <= d.max_observed_start_date
          and p.second_start_date <= p.first_end_date + interval '7 day'
    ))::numeric / nullif(count(*) filter (
        where p.first_end_date + interval '7 day' <= d.max_observed_start_date
    ), 0), 4) as retention_7d,
    round((avg(p.gap_days) filter (where p.second_start_date is not null))::numeric, 2) as avg_gap_days
from pairs p
cross join data_cutoff d
group by p.cohort, p.trial_length, p.provider
order by p.cohort, p.provider;
```

## 8. Gap buckets

Gap bucket query uses the same `ordered` and `pairs` CTE definitions as the main query, then aggregates:

```sql
select
    cohort,
    case
        when gap_days is null then 'no_second_subscription'
        when gap_days <= 0 then 'same_day_or_before'
        when gap_days <= 3 then '1_3_days'
        when gap_days <= 7 then '4_7_days'
        when gap_days <= 14 then '8_14_days'
        when gap_days <= 30 then '15_30_days'
        else '31_plus_days'
    end as gap_bucket,
    count(*) as users
from pairs
group by cohort, gap_bucket
order by cohort, gap_bucket;
```

## 9. Sanity checks

```sql
with ordered as (
    select
        user_id, start_date, end_date, type, provider, groups,
        row_number() over (partition by user_id order by start_date, end_date, t_w_srcid) as sub_num
    from spark_bsns_vlt.msp_ref_subscriptions
    where provider in ('Freedom Media', 'SuperApp')
      and user_id is not null
      and start_date is not null
      and end_date is not null
      and (
          groups is null
          or (
              lower(groups) not like '%test%'
              and lower(groups) not like '%demo%'
              and lower(groups) not like '%демо%'
              and lower(groups) not like '%нагруз%'
              and lower(groups) not like '%alga%'
              and lower(groups) not like '%алга%'
          )
      )
)
select
    case
        when start_date >= timestamp '2026-05-01' and start_date < timestamp '2026-06-01' then 'May 2026 / 30-day trial'
        when start_date >= timestamp '2026-06-01' and start_date < timestamp '2026-07-01' then 'June 2026 / 7-day trial'
    end as cohort,
    round((extract(epoch from (end_date - start_date)) / 86400.0)::numeric, 0) as duration_days_rounded,
    count(*) as users
from ordered
where sub_num = 1
  and type = 'trial'
  and start_date >= timestamp '2026-05-01'
  and start_date < timestamp '2026-07-01'
group by 1, 2
order by 1, users desc;
```

```sql
with base as (
    select
        user_id,
        start_date::date as start_day,
        count(*) as subs_on_day
    from spark_bsns_vlt.msp_ref_subscriptions
    where provider in ('Freedom Media', 'SuperApp')
      and user_id is not null
      and start_date >= timestamp '2026-05-01'
      and start_date < timestamp '2026-07-01'
      and (
          groups is null
          or (
              lower(groups) not like '%test%'
              and lower(groups) not like '%demo%'
              and lower(groups) not like '%демо%'
              and lower(groups) not like '%нагруз%'
              and lower(groups) not like '%alga%'
              and lower(groups) not like '%алга%'
          )
      )
    group by user_id, start_date::date
    having count(*) > 1
)
select
    count(*) as user_days_with_multiple_subs_same_day,
    sum(subs_on_day) as subscriptions_in_these_user_days,
    max(subs_on_day) as max_subs_same_day
from base;
```

## 10. Z-test

Z-test was calculated outside SQL from aggregate counts only:

```text
May: retained_3d = 7526, eligible_3d = 32672
June: retained_3d = 565, eligible_3d = 3430
two-proportion z = -8.7684
p-value = 1.8128469188882046e-18
```
