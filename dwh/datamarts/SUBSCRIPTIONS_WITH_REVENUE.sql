CREATE OR REPLACE VIEW VW_SUBSCRIPTIONS_WITH_REVENUE AS
with
    pay_tr as (
        SELECT
            phone,
            price,
            cr_date,
            case
                when merchant_id = 563748 then 'superapp'
                when bank_alias = 'bankfreedomfinancekazakhstanjointstockcompan' then 'freedom'
                when bank_alias = 'jsckaspibank' then 'kaspi'
                when bank_alias = 'halyksavingsbankofkazakhstan' then 'halyk'
                else bank_alias
            end as bank_alias,
            row_number() over (
                partition by
                    phone,
                    cr_date
                order by
                    price
            ) as rn
        FROM
            spark_dm.pay_transactions
        where
            price not in (10, 100, 500)
    ),
    sub_base as (
        select
            phone,
            user_id,
            start_date::date as start_date,
            end_date::date as end_date,
            end_date::date - start_date::date as duration,
            min(start_date) over (
                partition by
                    user_id
                order by
                    start_date
            ) as first_sub_dt,
            max(end_date) over (
                partition by
                    user_id
                order by
                    end_date desc
            ) as last_sub_dt,
            "type" as sub_type,
            row_number() over (
                partition by
                    user_id
                order by
                    start_date
            ) as sub_num,
            case
                when "type" = 'promo' then 'Промокод'
                when "type" = 'trial' then 'Триальный период'
                else 'Платная'
            end as subscription_type,
            case
                when packet_id in (4, 9, 12, 14, 56, 57, 72) then 'Stand Alone'
                when packet_id = 7 then 'Telecom'
                when packet_id in (10, 16, 54, 58, 59, 66, 71, 73) then 'Super App'
                when packet_id in (64) then 'Friends'
                when packet_id in (52, 61, 62)  then 'Amediateka'
                when packet_id = 60 then 'All Line'
                else 'Other'
            end as source,
            case
                when packet_id in (4, 9, 12, 14, 56, 57, 72) then 1
                when packet_id = 7 then 4
                when packet_id in (10, 16, 54, 58, 59, 66, 71, 73)  then 8
                when packet_id in (64) then 43
                when packet_id in (52, 61, 62, 65) then provider_id
                when packet_id = 60 then 41
                else provider_id
            end as provider_id,
            packet,
            packet_id,
            provider as real_provider,
            provider_id as real_provider_id,
            row_number() over (
                partition by
                    phone,
                    start_date
                order by
                    value
            ) as rn
        FROM
            spark_bsns_vlt.msp_ref_subscriptions
        where
            packet_id not in (1, 2, 3, 5, 6, 8, 11, 13, 15, 17, 18, 19, 53, 55, 63, 67, 68, 69, 70)
            and provider_id not in (2, 3, 5, 6, 7, 44, 42, 45)
            and end_date::date - start_date::date != 0
            and user_id not in (
                SELECT distinct
                    user_id
                FROM
                    spark_bsns_vlt.msp_ref_users
                where
                    user_role = 'test'
            )
    ),
    sub_with_pay as (
        select
            s.phone,
            s.user_id,
            s.start_date,
            s.end_date,
            s.duration,
            s.first_sub_dt,
            s.last_sub_dt,
            s.sub_type,
            s.sub_num,
            s.subscription_type,
            s.provider_id,
            s.packet,
            s.packet_id,
            s.real_provider,
            s.real_provider_id,
            case
                when s.packet_id in (7, 60) then 25
                when s.packet_id in (64) then 450
                else p.price
            end as price,
            case
                when s.packet_id in (7, 60, 64) then 'partner_billing'
                when p.bank_alias is Null then 'no_transaction'
                else p.bank_alias
            end as bank_alias
        from
            sub_base as s
            left join pay_tr p on s.phone = p.phone
            and s.rn = p.rn
            and s.start_date = p.cr_date
    ),
    payment_types as (
        select
            phone,
            user_id,
            start_date,
            end_date,
            duration,
            first_sub_dt::date as first_sub_dt,
            last_sub_dt::date as last_sub_dt,
            sub_type,
            sub_num,
            subscription_type,
            provider_id,
            packet,
            packet_id,
            real_provider,
            real_provider_id,
            coalesce(price, 0) as price,
            bank_alias,
            case
                when (price is null or price = 0) and sub_type not in ('trial','promo') then 'manual'
                when  sub_type in ('trial','promo') then 'promo/trial'
                else 'full_price'
            end as payment_status
        from
            sub_with_pay
    ),
    durations as (
        select
            1 as std_duration
        union all
        select
            14
        union all
        select
            30
        union all
        select
            60
        union all
        select
            90
        union all
        select
            120
        union all
        select
            180
        union all
        select
            365
        union all
        select
            777
    )
select
    p.phone,
    p.user_id,
    p.start_date,
    p.end_date,
    p.duration,
    d.std_duration,
    p.first_sub_dt,
    p.last_sub_dt,
    p.sub_type,
    p.sub_num,
    p.subscription_type,
    p.provider_id,
    p.packet,
    p.packet_id,
    p.real_provider,
    p.real_provider_id,
    p.price,
    p.bank_alias,
    p.payment_status
from
    payment_types p
    cross join lateral (
        select
            std_duration
        from
            durations
        order by
            abs(p.duration - std_duration),
            std_duration desc
        limit
            1
    ) d