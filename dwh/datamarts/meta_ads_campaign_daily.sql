SELECT
    day::date AS report_date,
    account_id,
    MAX(account_name) AS account_name,
    MAX(account_currency) AS account_currency,
    campaign_id,
    MAX(campaign_name) AS campaign_name,
    SUM(impressions) AS impressions,
    SUM(reach) AS reach_sum_approx,
    SUM(clicks) AS clicks,
    SUM(inline_link_clicks) AS link_clicks,
    SUM(spend) AS spend,
    SUM(video_view_p25) AS video_view_p25,
    SUM(video_view_p50) AS video_view_p50,
    SUM(video_view_p75) AS video_view_p75,
    SUM(video_view_p100) AS video_view_p100,
    SUM(app_install) AS app_install,
    SUM(mobile_app_install) AS mobile_app_install,
    SUM(content_view) AS content_view,
    SUM(purchase) AS purchase,
    SUM(purchase_value) AS purchase_value,
    CASE
        WHEN SUM(impressions) > 0
        THEN SUM(clicks)::numeric / SUM(impressions)
    END AS ctr,
    CASE
        WHEN SUM(impressions) > 0
        THEN SUM(spend)::numeric * 1000 / SUM(impressions)
    END AS cpm,
    CASE
        WHEN SUM(clicks) > 0
        THEN SUM(spend)::numeric / SUM(clicks)
    END AS cpc,
    CASE
        WHEN SUM(reach) > 0
        THEN SUM(impressions)::numeric / SUM(reach)
    END AS frequency_approx
FROM spark_bsns_vlt.msp_ref_s14_meta_ads
GROUP BY
    day::date,
    account_id,
    campaign_id
ORDER BY
    report_date,
    campaign_name