WITH tiktok_ads_dedup AS (
    SELECT *
    FROM (
        SELECT
            t.*,
            ROW_NUMBER() OVER (
                PARTITION BY
                    t.stat_time_day::date,
                    t.advertiser_id,
                    t.campaign_id,
                    t.ad_id
                ORDER BY t."change_timestamp$"::timestamp DESC
            ) AS rn
        FROM freedom_broker_dwh.s18_tiktok_ads_basic t
    ) x
    WHERE rn = 1
),
tiktok_campaign_day AS (
    SELECT
        t.stat_time_day::date AS report_date,
        'tiktok_ads'::text AS source_system,
        'TikTok'::text AS appsflyer_media_source,
        t.advertiser_id::text AS account_id,
        MAX(t.advertiser_name)::text AS account_name,
        t.campaign_id::text AS campaign_id,
        MAX(t.campaign_name)::text AS campaign_name,
        MAX(t.objective_type)::text AS objective_type,
        MAX(t.app_promotion_type)::text AS app_promotion_type,
        MAX(t.promotion_type)::text AS promotion_type,
        MAX(t.smart_target)::text AS smart_target,
        MAX(t.billing_event)::text AS billing_event,
        MAX(t.bid_strategy)::text AS bid_strategy,
        MAX(t.campaign_budget) AS campaign_budget,
        MAX(t.budget) AS adgroup_budget,
        MAX(t.currency)::text AS currency,
        SUM(t.spend) AS cost,
        SUM(t.impressions) AS impressions,
        SUM(t.reach) AS reach_sum_approx,
        SUM(t.clicks) AS clicks,
        SUM(t.video_play_actions) AS video_play_actions,
        SUM(t.video_views_p25) AS video_views_p25,
        SUM(t.video_views_p50) AS video_views_p50,
        SUM(t.video_views_p75) AS video_views_p75,
        SUM(t.video_views_p100) AS video_views_p100,
        SUM(t.engagements) AS engagements,
        SUM(t.shares) AS shares,
        SUM(t.follows) AS follows,
        SUM(t.likes) AS likes,
        SUM(t.comments) AS comments,
        SUM(t.conversion) AS conversions,
        SUM(t.result) AS results,
        SUM(t.real_time_app_install) AS real_time_app_install,
        SUM(t.app_install) AS app_install,
        SUM(t.registration) AS registration,
        SUM(t.purchase) AS purchase,
        SUM(t.total_purchase_value) AS total_purchase_value,
        SUM(t.cta_conversion) AS cta_conversion,
        SUM(t.cta_app_install) AS cta_app_install,
        SUM(t.cta_purchase) AS cta_purchase,
        MAX(t.utm_source)::text AS utm_source,
        MAX(t.utm_medium)::text AS utm_medium,
        MAX(t.utm_campaign)::text AS utm_campaign,
        CASE
            WHEN SUM(t.impressions) > 0
            THEN SUM(t.clicks)::numeric / SUM(t.impressions)
        END AS ctr_rate,
        CASE
            WHEN SUM(t.impressions) > 0
            THEN SUM(t.spend)::numeric * 1000 / SUM(t.impressions)
        END AS cpm,
        CASE
            WHEN SUM(t.clicks) > 0
            THEN SUM(t.spend)::numeric / SUM(t.clicks)
        END AS cpc,
        CASE
            WHEN SUM(t.video_play_actions) > 0
            THEN SUM(t.spend)::numeric / SUM(t.video_play_actions)
        END AS cpv,
        CASE
            WHEN SUM(t.reach) > 0
            THEN SUM(t.impressions)::numeric / SUM(t.reach)
        END AS frequency_approx,
        CASE
            WHEN SUM(t.clicks) > 0
            THEN SUM(t.conversion)::numeric / SUM(t.clicks)
        END AS conversion_rate,
        CASE
            WHEN SUM(t.conversion) > 0
            THEN SUM(t.spend)::numeric / SUM(t.conversion)
        END AS cost_per_conversion,
        CASE
            WHEN SUM(t.app_install) > 0
            THEN SUM(t.spend)::numeric / SUM(t.app_install)
        END AS cost_per_app_install,
        CASE
            WHEN SUM(t.registration) > 0
            THEN SUM(t.spend)::numeric / SUM(t.registration)
        END AS cost_per_registration,
        CASE
            WHEN SUM(t.purchase) > 0
            THEN SUM(t.spend)::numeric / SUM(t.purchase)
        END AS cost_per_purchase
    FROM tiktok_ads_dedup t
    GROUP BY
        t.stat_time_day::date,
        t.advertiser_id::text,
        t.campaign_id::text
)
SELECT *
FROM tiktok_campaign_day;