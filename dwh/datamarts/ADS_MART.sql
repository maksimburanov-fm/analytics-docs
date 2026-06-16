SELECT
    report_date,
    source_system,
    account_id::text AS account_id,
    account_name,
    'USD' account_currency,
    campaign_id::text AS campaign_id,
    campaign_name,
    impressions,
    clicks,
    "cost" AS cost
FROM spark_dm.google_ads_daily
UNION ALL
SELECT
    report_date,
    'meta_ads' AS source_system,
    account_id::text AS account_id,
    account_name,
    account_currency,
    campaign_id::text AS campaign_id,
    campaign_name,
    impressions,
    clicks,
    spend AS cost
FROM spark_dm.meta_ads_daily
UNION ALL
SELECT
    report_date,
    source_system,
    account_id::text AS account_id,
    account_name,
    currency AS account_currency,
    campaign_id::text AS campaign_id,
    campaign_name,
    impressions,
    clicks,
    "cost" AS cost
FROM spark_dm.tiktok_ads_daily;