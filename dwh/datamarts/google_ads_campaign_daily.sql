WITH google_ads_dedup AS (
    SELECT *
    FROM (
        SELECT
            g.*,
            ROW_NUMBER() OVER (
                PARTITION BY
                    g.date::date,
                    g.customer_id,
                    g.campaign_id,
                    g.platform
                ORDER BY g."change_timestamp"::timestamp DESC
            ) AS rn
        FROM spark_bsns_vlt.msp_ref_s14_google_ads g
    ) t
    WHERE rn = 1
),
google_ads_day AS (
    SELECT
        g.date::date AS report_date,
        g.customer_id::text AS account_id,
        MAX(g.account_name)::text AS account_name,
        g.campaign_id::text AS campaign_id,
        MAX(g.campaign_name)::text AS campaign_name,
        MAX(g.status::text) AS campaign_status_code,
        MIN(g.start_date::date) AS campaign_start_date,
        MAX(g.end_date::date) AS campaign_end_date,
        MAX(g.campaign_budget) AS campaign_budget,
        STRING_AGG(DISTINCT g.platform::text, ', ') AS platform_codes,
        STRING_AGG(DISTINCT g.bidding_strategy::text, ', ') AS bidding_strategy_codes,
        SUM(g.cost_micros) AS cost_micros,
        SUM(g.cost_micros)::numeric / 1000000 AS cost,
        NULL::text AS currency,
        SUM(g.impressions) AS impressions,
        SUM(g.clicks) AS clicks,
        SUM(g.video_views) AS video_views,
        SUM(g.conversions) AS google_conversions,
        SUM(g.conversion_value) AS google_conversion_value,
        SUM(g.all_conversions) AS google_all_conversions,
        SUM(g.interactions) AS interactions,
        CASE
            WHEN SUM(g.impressions) > 0
            THEN SUM(g.clicks)::numeric / SUM(g.impressions)
        END AS ctr,
        CASE
            WHEN SUM(g.impressions) > 0
            THEN (SUM(g.cost_micros)::numeric / 1000000) * 1000 / SUM(g.impressions)
        END AS cpm,
        CASE
            WHEN SUM(g.clicks) > 0
            THEN (SUM(g.cost_micros)::numeric / 1000000) / SUM(g.clicks)
        END AS cpc,
        CASE
            WHEN SUM(g.video_views) > 0
            THEN (SUM(g.cost_micros)::numeric / 1000000) / SUM(g.video_views)
        END AS cpv,
        CASE
            WHEN SUM(g.clicks) > 0
            THEN SUM(g.conversions)::numeric / SUM(g.clicks)
        END AS conversion_rate,
        CASE
            WHEN SUM(g.conversions) > 0
            THEN (SUM(g.cost_micros)::numeric / 1000000) / SUM(g.conversions)
        END AS cost_per_conversion,
        CASE
            WHEN SUM(g.video_views) > 0
            THEN SUM(g.video_views * g.video_quartile_p25_rate)::numeric / SUM(g.video_views)
        END AS video_quartile_p25_rate,
        CASE
            WHEN SUM(g.video_views) > 0
            THEN SUM(g.video_views * g.video_quartile_p50_rate)::numeric / SUM(g.video_views)
        END AS video_quartile_p50_rate,
        CASE
            WHEN SUM(g.video_views) > 0
            THEN SUM(g.video_views * g.video_quartile_p75_rate)::numeric / SUM(g.video_views)
        END AS video_quartile_p75_rate,
        CASE
            WHEN SUM(g.video_views) > 0
            THEN SUM(g.video_views * g.video_quartile_p100_rate)::numeric / SUM(g.video_views)
        END AS video_quartile_p100_rate
    FROM google_ads_dedup g
    GROUP BY
        g.date::date,
        g.customer_id::text,
        g.campaign_id::text
),
google_cpi_dedup AS (
    SELECT *
    FROM (
        SELECT
            c.*,
            ROW_NUMBER() OVER (
                PARTITION BY
                    c.date::date,
                    c.customer_id,
                    c.campaign_id,
                    c.conversion_action_name
                ORDER BY c."change_timestamp"::timestamp DESC
            ) AS rn
        FROM spark_bsns_vlt.msp_ref_s14_google_ads_cpi c
    ) t
    WHERE rn = 1
),
google_cpi_day AS (
    SELECT
        c.date::date AS report_date,
        c.customer_id::text AS account_id,
        MAX(c.account_name)::text AS account_name,
        c.campaign_id::text AS campaign_id,
        MAX(c.campaign_name)::text AS campaign_name,
        SUM(c.conversions) AS cpi_conversions_total,
        SUM(
            CASE
                WHEN c.conversion_action_name = 'YouTube channel subscriptions'
                THEN c.conversions ELSE 0
            END
        ) AS youtube_subscriptions,
        SUM(
            CASE
                WHEN c.conversion_action_name ILIKE '%применение промокода%'
                    OR c.conversion_action_name ILIKE '%promocode%'
                THEN c.conversions ELSE 0
            END
        ) AS promocode_apply_conversions,
        SUM(
            CASE
                WHEN c.conversion_action_name ILIKE '%установки приложения%'
                THEN c.conversions ELSE 0
            END
        ) AS app_install_conversions,
        SUM(
            CASE
                WHEN c.conversion_action_name ILIKE '%auth_success%'
                THEN c.conversions ELSE 0
            END
        ) AS web_auth_success_conversions,
        SUM(
            CASE
                WHEN c.conversion_action_name ILIKE '%payment_success%'
                THEN c.conversions ELSE 0
            END
        ) AS web_payment_success_conversions,
        SUM(
            CASE
                WHEN c.conversion_action_name ILIKE '%success_payment_promocode_trial%'
                THEN c.conversions ELSE 0
            END
        ) AS trial_payment_success_conversions,
        SUM(
            CASE
                WHEN c.conversion_action_name ILIKE '%first_open%'
                THEN c.conversions ELSE 0
            END
        ) AS superapp_first_open_conversions,
        SUM(
            CASE
                WHEN c.conversion_action_name ILIKE '%first_open%'
                 AND c.conversion_action_name ILIKE '%Android%'
                THEN c.conversions ELSE 0
            END
        ) AS superapp_first_open_android_conversions,
        SUM(
            CASE
                WHEN c.conversion_action_name ILIKE '%first_open%'
                 AND c.conversion_action_name ILIKE '%iOS%'
                THEN c.conversions ELSE 0
            END
        ) AS superapp_first_open_ios_conversions
    FROM google_cpi_dedup c
    GROUP BY
        c.date::date,
        c.customer_id::text,
        c.campaign_id::text
)
SELECT
    COALESCE(g.report_date, c.report_date) AS report_date,
    'google_ads'::text AS source_system,
    'googleadwords_int'::text AS appsflyer_media_source,
    COALESCE(g.account_id, c.account_id) AS account_id,
    COALESCE(g.account_name, c.account_name) AS account_name,
    COALESCE(g.campaign_id, c.campaign_id) AS campaign_id,
    COALESCE(g.campaign_name, c.campaign_name) AS campaign_name,
    g.campaign_status_code,
    g.campaign_start_date,
    g.campaign_end_date,
    g.campaign_budget,
    g.platform_codes,
    g.bidding_strategy_codes,
    g.cost_micros,
    g.cost,
    g.currency,
    g.impressions,
    g.clicks,
    g.video_views,
    g.interactions,
    g.google_conversions,
    g.google_conversion_value,
    g.google_all_conversions,
    c.cpi_conversions_total,
    c.youtube_subscriptions,
    c.promocode_apply_conversions,
    c.app_install_conversions,
    c.web_auth_success_conversions,
    c.web_payment_success_conversions,
    c.trial_payment_success_conversions,
    c.superapp_first_open_conversions,
    c.superapp_first_open_android_conversions,
    c.superapp_first_open_ios_conversions,
    g.ctr,
    g.cpm,
    g.cpc,
    g.cpv,
    g.conversion_rate,
    g.cost_per_conversion,
    g.video_quartile_p25_rate,
    g.video_quartile_p50_rate,
    g.video_quartile_p75_rate,
    g.video_quartile_p100_rate
FROM google_ads_day g
FULL OUTER JOIN google_cpi_day c
    ON g.report_date = c.report_date
    AND g.account_id = c.account_id
    AND g.campaign_id = c.campaign_id;