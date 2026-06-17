CREATE OR REPLACE VIEW VW_USER_WATCH_SUB_PROMO AS
with
    all_sessions as (
        select
            session_start_ts::date as dt,
            session_start_ts,
            user_id,
            content_id as id,
            content_title as title,
            content_type,
            device_type,
            'vod' as video_type,
            extract(
                epoch
                from
                    (session_end_ts - session_start_ts)
            ) as duration_s
        from
            spark_bsns_vlt.msp_content_session
        union all
        select
            (session_start_ts + interval '2 hour')::date as dt,
            session_start_ts + interval '2 hour' as session_start_ts,
            user_id,
            channel_id as id,
            channel_title as title,
            'tv_program' as content_type,
            device_type,
            'tv' as video_type,
            extract(
                epoch
                from
                    (session_end_ts - session_start_ts)
            ) as duration_s
        from
            spark_bsns_vlt.msp_ref_tv_session
    ),
    all_sessions_agg as (
        select
            dt,
            user_id,
            id,
            title,
            content_type,
            device_type,
            video_type,
            min(session_start_ts) as sess_start,
            sum(duration_s) as duration_s
        from
            all_sessions
        where
            duration_s > 0
        group by
            dt,
            user_id,
            id,
            title,
            content_type,
            device_type,
            video_type
        having
            sum(duration_s) >= 120
    ),
    first_session as (
        select
            *
        from
            (
                select
                    user_id,
                    dt as first_view_dt,
                    id as first_view_id,
                    title as first_title,
                    device_type as first_view_device_type,
                    video_type as first_view_video_type,
                    row_number() over (
                        partition by
                            user_id
                        order by
                            sess_start asc
                    ) as rn
                from
                    all_sessions_agg
            ) t
        where
            rn = 1
    ),
    last_session as (
        select
            *
        from
            (
                select
                    user_id,
                    dt as last_view_dt,
                    id as last_view_id,
                    title as last_title,
                    device_type as last_view_device_type,
                    video_type as last_view_video_type,
                    row_number() over (
                        partition by
                            user_id
                        order by
                            sess_start desc
                    ) as rn
                from
                    all_sessions_agg
            ) t
        where
            rn = 1
    ),
    agg as (
        select
            user_id,
            sum(duration_s) as total_watch_sec,
            sum(
                case
                    when dt >= current_date - interval '30 day' then duration_s
                    else 0
                end
            ) as watch_sec_30d,
            count(
                distinct case
                    when dt >= current_date - interval '30 day' then id
                end
            ) as unique_id_30d,
            sum(
                case
                    when dt >= current_date - interval '7 day' then duration_s
                    else 0
                end
            ) as watch_sec_7d,
            count(
                distinct case
                    when dt >= current_date - interval '7 day' then id
                end
            ) as unique_id_7d
        from
            all_sessions_agg
        group by
            user_id
    ),
    watching_profile as (
        select
            a.user_id,
            f.first_view_dt,
            f.first_view_id,
            f.first_view_device_type,
            f.first_view_video_type,
            coalesce(c.content_title_ru, f.first_title) as first_title,
            a.total_watch_sec,
            a.watch_sec_30d,
            a.unique_id_30d,
            a.watch_sec_7d,
            a.unique_id_7d,
            l.last_view_dt,
            l.last_view_id,
            l.last_view_device_type,
            l.last_view_video_type,
            coalesce(ct.content_title_ru, l.last_title) as last_title
        from
            agg a
            left join first_session f on a.user_id = f.user_id
            left join last_session l on a.user_id = l.user_id
            left join spark_dm.full_catalog c on f.first_view_id = c.content_id
            and f.first_view_video_type = 'vod'
            left join spark_dm.full_catalog ct on l.last_view_id = ct.content_id
            and l.last_view_video_type = 'vod'
    ),
    filtred_sub as (
        select
            phone,
            user_id,
            end_date::date - start_date::date as f_duration,
            min(start_date) over (
                partition by
                    user_id
            ) as first_sub_dt,
            max(end_date) over (
                partition by
                    user_id
            ) as last_sub_dt,
            "type",
            row_number() over (
                partition by
                    user_id
                order by
                    start_date
            ) as sub_num,
            case
                when "type" = 'promo' then 'Promocode'
                when "type" = 'trial' then 'Trial'
                else 'Payment'
            end as f_subscription_type,
            case
                when packet_id in (4, 9, 12, 14, 56, 57, 72) then 'Stand Alone'
                when packet_id = 7 then 'Telecom'
                when packet_id in (10, 16, 54, 58, 59, 66, 71, 73) then 'Super App'
                when packet_id in (64) then 'Friends'
                when packet_id in (52, 61, 62)  then 'Amediateka'
                when packet_id = 60 then 'All Line'
                else 'Other'
            end as f_source,
            case
                when packet_id in (4, 9, 12, 14, 56, 57, 72) then 1
                when packet_id = 7 then 4
                when packet_id in (10, 16, 54, 58, 59, 66, 71, 73)  then 8
                when packet_id in (64) then 43
                when packet_id in (52, 61, 62) then provider_id
                when packet_id = 60 then 41
                else provider_id
            end as f_id,
            packet as f_packet,
            packet_id as f_packet_id,
            provider as f_provider,
            provider_id as f_provider_id,
            register_date
        FROM
            spark_bsns_vlt.msp_ref_subscriptions
        where
            packet_id not in (1, 2, 3, 5, 6, 8, 11, 13, 15, 17, 18, 19, 53, 55, 63, 65, 67, 68, 69, 70)
            and provider_id not in (2, 3, 5, 6, 7, 44, 42, 45)
            and end_date::date - start_date::date != 0
            and user_id not in 
                (
                    select distinct user_id
                    from spark_bsns_vlt.msp_ref_users
                    where
                        user_role = 'test'
                        or provider_name in (
                            'Freedom Telecom (test)',
                            'Сертификация приложений',
                            'Провайдер для тестов',
                            'Тест Setanta + Netflix',
                            'Закрытые показы',
                            '140 ball',
                            'Fmedia',
                            'Коммерческая витрина'
                        ))
    ),
    first_sub as (
        select
            phone,
            user_id,
            f_duration,
            first_sub_dt::date as first_sub_dt,
            last_sub_dt::date as last_sub_dt,
            "type" as platform_type,
            f_subscription_type,
            f_source,
            f_packet,
            f_packet_id,
            f_provider,
            f_provider_id,
            register_date,
            f_id
        from
            filtred_sub
        where
            sub_num = 1
    ),
    promokeys_raw as (
    select
        p.user_id,
        p.promo_title,
        p.marketing,
        (p.activated_at - interval '1 hours')::date as dt,
        p.activated_at,
        row_number() over (
            partition by 
                p.user_id,
                (p.activated_at - interval '1 hours')::date
            order by 
                p.activated_at
        ) as rn
    from spark_bsns_vlt.msp_promo_fer_act p
    join first_sub f
        on f.user_id = p.user_id
       and f.first_sub_dt = (p.activated_at - interval '1 hours')::date
    where coalesce(lower(p.promo_title), '') not like '%test%'
      and coalesce(lower(p.promo_title), '') not like '%тест%'
      and not exists (
          select 1
          from spark_bsns_vlt.msp_ref_users u
          where u.user_id = p.user_id
            and (
                u.user_role = 'test'
                or u.provider_name in (
                    'Freedom Telecom (test)',
                    'Сертификация приложений',
                    'Провайдер для тестов',
                    'Тест Setanta + Netflix',
                    'Закрытые показы',
                    '140 ball',
                    'Fmedia',
                    'Коммерческая витрина'
                )
            )
      )
    ),
    promokeys as (
        select
            user_id,
            promo_title,
            marketing,
            dt
        from promokeys_raw
        where rn = 1
    ),
    first_sub_info as (
        select
            f.*,
            p.promo_title,
            p.marketing
        from first_sub f
        left join promokeys p 
            on f.user_id = p.user_id
        and f.first_sub_dt = p.dt
    ),
    registrations as (
        select
            user_id,
            registration_dt,
            phone,
            provider_name,
            user_role,
            row_number() over (
                partition by
                    user_id
                order by
                    registration_dt
            ) as rn
        from
            spark_bsns_vlt.msp_ref_users
        where
            user_role != 'test'
            and provider_name is not Null
            and provider_name not in (
                            'Freedom Telecom (test)',
                            'Сертификация приложений',
                            'Провайдер для тестов',
                            'Тест Setanta + Netflix',
                            'Закрытые показы',
                            '140 ball',
                            'Fmedia',
                            'Коммерческая витрина'
                            )
    ),
    reg_with_first_sub as (
        SELECT
            coalesce(u.user_id, sb.user_id) as user_id,
            coalesce(u.registration_dt, sb.register_date) as registration_dt,
            coalesce(u.registration_dt, sb.register_date)::date as reg_date,
            coalesce(u.phone, sb.phone) as phone,
            u.provider_name as registration_provider,
            coalesce(
                sb.f_id,
                case
                    when u.provider_name = 'All line' then 41
                    when u.provider_name = 'Freedom Media' then 1
                    when u.provider_name = 'Freedom Telecom' then 4
                    when u.provider_name = 'SuperApp' then 8
                    when u.provider_name = 'Тест Setanta + Netflix' then 6
                    when u.provider_name = 'Freedom Telecom (test)' then 7
                    when u.provider_name = 'Сертификация приложений' then 2
                    when u.provider_name = 'Закрытые показы' then 5
                    when u.provider_name = 'Провайдер для тестов' then 3
                    else 3
                end
            ) as reg_provider_id,
            u.user_role,
            sb.f_duration,
            sb.first_sub_dt,
            sb.last_sub_dt,
            sb.platform_type,
            sb.f_subscription_type,
            sb.f_source,
            sb.f_packet,
            sb.f_packet_id,
            sb.f_provider,
            sb.f_provider_id,
            sb.promo_title, 
            sb.marketing
        FROM
            registrations u
            full join first_sub_info sb on u.user_id = sb.user_id
        where
            coalesce(u.rn, 1) = 1
            and coalesce(u.phone, sb.phone) is not null
    ),
    age_gender as (
        SELECT distinct
            user_phone as phone,
            to_Date(
                CASE SUBSTRING(param3, 7, 1)
                    WHEN '1' THEN '18'
                    WHEN '2' THEN '18'
                    WHEN '3' THEN '19'
                    WHEN '4' THEN '19'
                    WHEN '5' THEN '20'
                    WHEN '6' THEN '20'
                    else case SUBSTRING(param3, 1, 1)
                        when '0' then '20'
                        when '1' then '20'
                        when '2' then '20'
                        else '19'
                    end
                END || SUBSTRING(param3, 1, 2) || SUBSTRING(param3, 3, 2) || SUBSTRING(param3, 5, 2),
                'YYYYMMDD'
            ) as birthdate,
            CASE SUBSTRING(param3, 7, 1)
                WHEN '1' THEN 'Мужчина'
                WHEN '2' THEN 'Женщина'
                WHEN '3' THEN 'Мужчина'
                WHEN '4' THEN 'Женщина'
                WHEN '5' THEN 'Мужчина'
                WHEN '6' THEN 'Женщина'
                ELSE 'Неизвестно'
            END AS gender
        FROM
            spark_bsns_vlt.msp_ref_pay_transactions
        WHERE
            merchant_id = 563748
            AND user_phone IS NOT NULL
            AND param3 IS NOT NULL
    ),
    age_gender_birthdate AS (
        SELECT
            phone,
            MIN(birthdate) AS birthdate,
            DATE_PART('year', AGE (MIN(birthdate))) AS age,
            COALESCE(
                MAX(
                    CASE
                        WHEN gender <> 'Неизвестно' THEN gender
                    END
                ),
                'Неизвестно'
            ) AS gender
        FROM
            age_gender
        GROUP BY
            phone
    )
select
    r.*,
    a.birthdate,
    a.age,
    a.gender,
    wp.first_view_dt,
    wp.first_view_id,
    wp.first_view_device_type,
    wp.first_view_video_type,
    wp.first_title,
    wp.total_watch_sec,
    wp.watch_sec_30d,
    wp.unique_id_30d,
    wp.watch_sec_7d,
    wp.unique_id_7d,
    wp.last_view_dt,
    wp.last_view_id,
    wp.last_view_device_type,
    wp.last_view_video_type,
    wp.last_title
from
    reg_with_first_sub r
    left join age_gender_birthdate a on r.phone = a.phone
    left join watching_profile wp on r.user_id = wp.user_id