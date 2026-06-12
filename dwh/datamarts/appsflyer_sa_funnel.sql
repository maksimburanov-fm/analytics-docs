WITH events_prepared AS (
    SELECT
        e.appsflyer_id,
        e.event_name,
        e.event_time::timestamp AS event_time,
        e.install_time::timestamp AS event_install_time,
        e.event_value,
        CASE
            WHEN (e.event_value::json ->> 'uid') ~ '^[0-9]+$'
                THEN (e.event_value::json ->> 'uid')::bigint
            ELSE NULL
        END AS uid
    FROM spark_bsns_vlt.msp_ref_appsflyer_events e
),
uid_by_appsflyer AS (
    SELECT
        appsflyer_id,
        uid
    FROM (
        SELECT
            appsflyer_id,
            uid,
            event_time,
            ROW_NUMBER() OVER (
                PARTITION BY appsflyer_id
                ORDER BY event_time
            ) AS rn
        FROM events_prepared
        WHERE uid IS NOT NULL
    ) t
    WHERE rn = 1
),
events_agg AS (
    SELECT
        appsflyer_id,
        MIN(event_time) AS first_event_time,
        MIN(CASE
            WHEN event_name = 'reg_step_8_registration_success'
            THEN event_time
        END) AS registration_success_time,
        MIN(CASE
            WHEN event_name = 'media_start_page_viewed'
            THEN event_time
        END) AS media_start_page_viewed_time,
        MIN(CASE
            WHEN event_name = 'media_payment_completed'
            THEN event_time
        END) AS media_payment_completed_time,
        MAX(CASE
            WHEN event_name = 'reg_step_8_registration_success'
            THEN 1 ELSE 0
        END) AS has_registration_success,
        MAX(CASE
            WHEN event_name = 'media_start_page_viewed'
            THEN 1 ELSE 0
        END) AS has_media_start_page_viewed,
        MAX(CASE
            WHEN event_name = 'media_payment_completed'
            THEN 1 ELSE 0
        END) AS has_media_payment_completed,
        COUNT(*) AS appsflyer_events_cnt
    FROM events_prepared
    GROUP BY appsflyer_id
),
sa_funnel as 
(
SELECT
    i.install_time::timestamp AS install_time,
    i.install_time::date AS install_date,
    i.appsflyer_id,
    u.uid AS user_id,
    i.media_source,
    i.campaign_id,
    i.campaign,
    i.adset_id,
    i.adset,
    i.ad_id,
    i.ad,
    i.channel,
    i.platform,
    i.site_id,
    i.original_url,
    i.attributed_touch_time,
    i.attributed_touch_type,
    i.is_retargeting,
    i.is_primary_attribution,
    a.first_event_time,
    a.registration_success_time,
    a.media_start_page_viewed_time,
    a.media_payment_completed_time,
    a.has_registration_success,
    a.has_media_start_page_viewed,
    a.has_media_payment_completed,
    a.appsflyer_events_cnt
FROM spark_bsns_vlt.msp_ref_appsflyer_installs i
LEFT JOIN uid_by_appsflyer u
    ON i.appsflyer_id = u.appsflyer_id
LEFT JOIN events_agg a
    ON i.appsflyer_id = a.appsflyer_id
   ) 
select * 
from sa_funnel