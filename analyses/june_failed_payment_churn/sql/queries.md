# SQL notes for June failed-payment churn analysis

Дата запуска: 2026-07-09.

Все запросы read-only. Телефон используется только внутри SQL-связки и не выводится.

## Cohort definition

```sql
with sub_next as (
    select
        user_id,
        phone,
        start_date,
        end_date,
        sub_num,
        subscription_type,
        payment_status,
        provider_id,
        packet_id,
        packet,
        first_sub_dt,
        lead(start_date) over (
            partition by user_id
            order by start_date, end_date, sub_num
        ) as next_start_date
    from spark_dm.subscriptions_with_revenue
    where start_date < date '2026-08-01'
      and end_date >= date '2026-06-01'
      and provider_id in (1, 8)
),
month_last as (
    select
        *,
        row_number() over (
            partition by user_id
            order by end_date desc, start_date desc, sub_num desc
        ) as rn
    from sub_next
    where end_date >= date '2026-06-01'
      and end_date < date '2026-07-01'
      and end_date + interval '7 day' <= current_date
),
labeled as (
    select
        *,
        case
            when next_start_date is null
              or next_start_date > end_date + interval '7 day'
            then 1 else 0
        end as churn_7d
    from month_last
    where rn = 1
),
attempt_matches as (
    select
        l.user_id,
        p.id,
        p.status,
        p.payment_type,
        p.merchant_id,
        p.created_at,
        p.bill_amount,
        'superapp_phone' as match_rule
    from labeled l
    join spark_bsns_vlt.msp_ref_pay_transactions p
      on p.merchant_id = 563748
     and p.user_phone is not null
     and btrim(p.user_phone) <> ''
     and regexp_replace(p.user_phone, '[^0-9]', '', 'g') =
         regexp_replace(l.phone, '[^0-9]', '', 'g')
     and p.created_at::date between l.end_date - 3 and l.end_date + 7
     and coalesce(p.test_mode, false) = false

    union all

    select
        l.user_id,
        p.id,
        p.status,
        p.payment_type,
        p.merchant_id,
        p.created_at,
        p.bill_amount,
        'superapp_param1_fallback' as match_rule
    from labeled l
    join spark_bsns_vlt.msp_ref_pay_transactions p
      on p.merchant_id = 563748
     and (p.user_phone is null or btrim(p.user_phone) = '')
     and p.param1 ~ '^[0-9]+$'
     and p.param1::numeric = l.user_id
     and p.created_at::date between l.end_date - 3 and l.end_date + 7
     and coalesce(p.test_mode, false) = false

    union all

    select
        l.user_id,
        p.id,
        p.status,
        p.payment_type,
        p.merchant_id,
        p.created_at,
        p.bill_amount,
        'other_param1' as match_rule
    from labeled l
    join spark_bsns_vlt.msp_ref_pay_transactions p
      on p.merchant_id <> 563748
     and p.param1 ~ '^[0-9]+$'
     and p.param1::numeric = l.user_id
     and p.created_at::date between l.end_date - 3 and l.end_date + 7
     and coalesce(p.test_mode, false) = false
),
pay_attempts as (
    select
        l.user_id,
        max(case when am.status = 'success' then 1 else 0 end) as success_attempt,
        max(case when am.status in ('error', 'incomplete', 'waiting', 'new', 'process') then 1 else 0 end) as failed_attempt,
        count(distinct am.id) as attempts,
        count(distinct case when am.status in ('error', 'incomplete', 'waiting', 'new', 'process') then am.id end) as failed_attempts
    from labeled l
    left join attempt_matches am
        on am.user_id = l.user_id
    group by l.user_id
),
failed_users as (
    select
        l.user_id,
        l.start_date,
        l.end_date,
        l.first_sub_dt,
        case
            when l.provider_id = 1 then 'StandAlone'
            when l.provider_id = 8 then 'SuperApp'
        end as channel,
        l.subscription_type,
        l.payment_status,
        l.packet_id,
        l.packet,
        l.sub_num,
        l.end_date - l.first_sub_dt as lifetime_days,
        coalesce(pa.attempts, 0) as payment_attempts,
        coalesce(pa.failed_attempts, 0) as failed_attempts
    from labeled l
    join pay_attempts pa
        on pa.user_id = l.user_id
    where l.churn_7d = 1
      and pa.failed_attempt = 1
      and pa.success_attempt = 0
)
select count(*) as failed_payment_churn_users
from failed_users;
```

Контрольный результат: `15 452` пользователей.

## Key aggregate results

### Channel summary

| Channel | Churn users | Failed-payment churn | No-attempt churn | Renewed users |
| --- | ---: | ---: | ---: | ---: |
| StandAlone | 18 286 | 12 091 | 5 855 | 6 846 |
| SuperApp | 25 866 | 3 361 | 22 229 | 226 966 |

### Top failed-payment packages

| Segment | Users | Share |
| --- | ---: | ---: |
| StandAlone / MEDIA / trial | 8 376 | 54.21% |
| SuperApp / SUPER / trial | 2 374 | 15.36% |
| StandAlone / MEDIA packet 72 / trial | 2 212 | 14.32% |
| StandAlone / MEDIA / promo | 944 | 6.11% |
| StandAlone / MEDIA / paid | 466 | 3.02% |
| SuperApp / SUPER / promo | 404 | 2.61% |
| SuperApp / SUPER / paid | 280 | 1.81% |

### Payment status/type

| Status / type | Users | Share |
| --- | ---: | ---: |
| error / g2g_forward | 14 547 | 94.14% |
| waiting / forward | 642 | 4.15% |
| new / forward | 477 | 3.09% |
| incomplete / forward | 243 | 1.57% |

### June VOD bins

| VOD views in June | Users |
| --- | ---: |
| 0 | 5 652 |
| 1 | 640 |
| 2 | 892 |
| 3-5 | 2 342 |
| 6-7 | 1 301 |
| 8-15 | 2 670 |
| 16+ | 1 955 |

| VOD active days in June | Users |
| --- | ---: |
| 0 | 5 652 |
| 1 | 1 884 |
| 2 | 1 949 |
| 3-5 | 4 081 |
| 6-7 | 1 026 |
| 8+ | 860 |

### June TV bins

| TV views in June | Users |
| --- | ---: |
| 0 | 13 982 |
| 1 | 303 |
| 2 | 161 |
| 3-5 | 235 |
| 6-7 | 81 |
| 8-15 | 205 |
| 16+ | 485 |

## Query execution notes

The combined VOD+TV user-level query exceeded database memory in the interactive MCP session. The report therefore uses narrower successful aggregates:

- user-level profile and first view from `spark_dm.user_watch_sub_promo`;
- exact June VOD bins from `spark_bsns_vlt.msp_content_session`;
- exact June TV bins from `spark_bsns_vlt.msp_ref_tv_session`;
- VOD genres and titles for the last 30 days before subscription end;
- TV channels and sport-like viewers for the last 30 days before subscription end.

This keeps the analysis read-only and aggregate-only.
