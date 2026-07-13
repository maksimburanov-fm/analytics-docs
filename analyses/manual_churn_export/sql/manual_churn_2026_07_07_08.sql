with churn_subscriptions as (
    select
        user_id,
        end_date,
        real_provider as provider,
        packet,
        subscription_type,
        payment_status,
        start_date,
        packet_id,
        real_provider_id,
        row_number() over (
            partition by user_id, end_date
            order by end_date desc, start_date desc, packet_id desc, real_provider_id desc
        ) as rn
    from spark_dm.subscriptions_with_revenue
    where end_date in (date '2026-07-07', date '2026-07-08')
      and last_sub_dt = end_date
),
churn_users as (
    select
        user_id,
        end_date,
        provider,
        packet,
        subscription_type,
        payment_status
    from churn_subscriptions
    where rn = 1
)
select
    user_id,
    end_date as subscription_end_date,
    provider,
    packet,
    subscription_type,
    payment_status
from churn_users
where payment_status = 'manual'
order by subscription_end_date, user_id;
