/*
Dataset for June churn analysis.

Granularity: one row = one user-month at risk of churn.

Churn definition:
- take the last valid subscription ending in a month for each user;
- user is at risk only when `end_date + interval '7 day' <= current_date`;
- `churn_7d = 1` when there is no next valid subscription start within 7 days after `end_date`.

The query intentionally does not expose phone, email, pan_mask or other personal fields.
Phone is used inside upstream subscription logic and is not selected.
*/

with sub_next as (
    select
        user_id,
        phone,
        start_date,
        end_date,
        sub_num,
        sub_type,
        subscription_type,
        payment_status,
        provider_id,
        real_provider_id,
        real_provider,
        packet_id,
        packet,
        bank_alias,
        price,
        duration,
        std_duration,
        first_sub_dt,
        lead(start_date) over (
            partition by user_id
            order by start_date, end_date, sub_num
        ) as next_start_date
    from spark_dm.subscriptions_with_revenue
    where start_date < date '2026-08-01'
      and end_date >= date '2026-01-01'
),
month_last as (
    select
        *,
        date_trunc('month', end_date)::date as end_month,
        row_number() over (
            partition by user_id, date_trunc('month', end_date)::date
            order by end_date desc, start_date desc, sub_num desc
        ) as rn_month
    from sub_next
    where end_date >= date '2026-03-01'
      and end_date < date '2026-07-01'
      and end_date + interval '7 day' <= current_date
),
labeled as (
    select
        ml.*,
        case
            when next_start_date is null
              or next_start_date > end_date + interval '7 day'
            then 1 else 0
        end as churn_7d,
        case
            when next_start_date is null
              or next_start_date > end_date + interval '30 day'
            then 1 else 0
        end as churn_30d
    from month_last ml
    where rn_month = 1
),
pay_attempts as (
    select
        l.end_month,
        l.user_id,
        max(case when p.id is not null then 1 else 0 end) as any_payment_attempt_near_end,
        max(case when p.status = 'success' and coalesce(p.test_mode, false) = false then 1 else 0 end) as success_payment_attempt_near_end,
        max(case when p.status in ('error', 'incomplete', 'waiting', 'new', 'process')
                  and coalesce(p.test_mode, false) = false then 1 else 0 end) as failed_or_pending_payment_attempt_near_end,
        count(*) filter (
            where p.status in ('error', 'incomplete', 'waiting', 'new', 'process')
              and coalesce(p.test_mode, false) = false
        ) as failed_or_pending_payment_attempt_rows
    from labeled l
    left join spark_bsns_vlt.msp_ref_pay_transactions p
        on p.param1 ~ '^[0-9]+$'
       and p.param1::numeric = l.user_id
       and p.created_at::date between l.end_date - 3 and l.end_date + 7
    group by l.end_month, l.user_id
),
vod_activity as (
    select
        l.end_month,
        l.user_id,
        max(cs.session_start_ts::date) as last_vod_dt_before_end,
        count(distinct cs.session_start_ts::date) as vod_active_days_30d,
        sum(extract(epoch from (cs.session_end_ts - cs.session_start_ts))) as vod_watch_sec_30d
    from labeled l
    join spark_bsns_vlt.msp_content_session cs
        on cs.user_id = l.user_id
       and cs.session_start_ts::date between l.end_date - 30 and l.end_date
       and cs.session_end_ts > cs.session_start_ts
    group by l.end_month, l.user_id
),
tv_activity as (
    select
        l.end_month,
        l.user_id,
        max((ts.session_start_ts + interval '2 hour')::date) as last_tv_dt_before_end,
        count(distinct (ts.session_start_ts + interval '2 hour')::date) as tv_active_days_30d,
        sum(extract(epoch from (ts.session_end_ts - ts.session_start_ts))) as tv_watch_sec_30d
    from labeled l
    join spark_bsns_vlt.msp_ref_tv_session ts
        on ts.user_id = l.user_id
       and (ts.session_start_ts + interval '2 hour')::date between l.end_date - 30 and l.end_date
       and ts.session_end_ts > ts.session_start_ts
    group by l.end_month, l.user_id
),
activity as (
    select
        l.end_month,
        l.user_id,
        case
            when v.last_vod_dt_before_end is not null and t.last_tv_dt_before_end is not null
            then greatest(v.last_vod_dt_before_end, t.last_tv_dt_before_end)
            else coalesce(v.last_vod_dt_before_end, t.last_tv_dt_before_end)
        end as last_view_dt_before_end,
        coalesce(v.vod_active_days_30d, 0) + coalesce(t.tv_active_days_30d, 0) as active_days_30d,
        coalesce(v.vod_watch_sec_30d, 0) + coalesce(t.tv_watch_sec_30d, 0) as watch_sec_30d
    from labeled l
    left join vod_activity v
        on l.end_month = v.end_month
       and l.user_id = v.user_id
    left join tv_activity t
        on l.end_month = t.end_month
       and l.user_id = t.user_id
)
select
    l.end_month,
    l.user_id,
    l.start_date,
    l.end_date,
    l.first_sub_dt,
    l.sub_num,
    l.sub_type,
    l.subscription_type,
    l.payment_status,
    l.provider_id,
    l.real_provider_id,
    l.real_provider,
    l.packet_id,
    l.packet,
    l.bank_alias,
    l.price,
    l.duration,
    l.std_duration,
    l.next_start_date,
    l.churn_7d,
    l.churn_30d,
    case
        when l.sub_num = 1 then '1 first sub'
        when l.sub_num between 2 and 3 then '2-3'
        when l.sub_num between 4 and 10 then '4-10'
        else '11+'
    end as sub_num_bin,
    case
        when l.end_date - l.first_sub_dt <= 7 then '0-7d'
        when l.end_date - l.first_sub_dt <= 30 then '8-30d'
        when l.end_date - l.first_sub_dt <= 90 then '31-90d'
        when l.end_date - l.first_sub_dt <= 180 then '91-180d'
        else '180d+'
    end as lifetime_bin,
    case
        when coalesce(pa.failed_or_pending_payment_attempt_near_end, 0) = 1
          and coalesce(pa.success_payment_attempt_near_end, 0) = 0
        then 'failed_or_pending_only'
        when coalesce(pa.success_payment_attempt_near_end, 0) = 1
        then 'success_attempt_near_end'
        when coalesce(pa.any_payment_attempt_near_end, 0) = 0
        then 'no_payment_attempt_by_param1'
        else 'mixed_payment_attempts'
    end as payment_proxy,
    coalesce(pa.failed_or_pending_payment_attempt_rows, 0) as failed_or_pending_payment_attempt_rows,
    a.last_view_dt_before_end,
    l.end_date - a.last_view_dt_before_end as days_from_last_view_to_end,
    coalesce(a.active_days_30d, 0) as active_days_30d,
    coalesce(a.watch_sec_30d, 0) as watch_sec_30d
from labeled l
left join pay_attempts pa
    on l.end_month = pa.end_month
   and l.user_id = pa.user_id
left join activity a
    on l.end_month = a.end_month
   and l.user_id = a.user_id;
