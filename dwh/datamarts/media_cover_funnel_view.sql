-- Source view for PythonSparkDMJob.
--
-- The view deliberately contains no fixed dates and no invented template variables.
-- PythonSparkDMJob applies START_DATE/END_DATE to the EVENT_DATE column configured
-- as METADATA_DM.SECTION_KEY and performs the period delete + insert itself.
--
-- Important performance condition:
-- Before production rollout, confirm with EXPLAIN that the outer EVENT_DATE
-- predicate pushed by PythonSparkDMJob is propagated far enough into this view.
-- If it is not, this all-history view will require a platform-supported parameter
-- mechanism or physical upstream preparation; no such SQL-variable mechanism is
-- documented in the reviewed Confluence pages.

CREATE OR REPLACE VIEW spark_bsns_vlt.v_media_cover_funnel_user_daily AS
WITH event_base_raw AS (
    SELECT
        e.event_id,
        e.event_name::text AS event_name,
        e.device_id::text AS device_id,
        e.event_date::timestamp AS event_ts,
        e.path::text AS path,
        e.row_id::text AS row_id,
        e.subhead::text AS subhead,
        e."type"::text AS item_type,
        CASE
            WHEN e."count"::text ~ '^[0-9]+$'
            THEN e."count"::integer
            ELSE NULL::integer
        END AS position,
        e.title::text AS title,
        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REPLACE(
                        REPLACE(e.title::text, CHR(160), ' '),
                        'ё',
                        'е'
                    ),
                    '[[:space:]]+',
                    ' ',
                    'g'
                )
            )
        )::text AS title_norm,
        CASE
            WHEN e.param_client_id::text ~ '^[0-9]+$'
            THEN e.param_client_id::numeric(38, 0)
            ELSE NULL::numeric(38, 0)
        END AS user_id,
        CASE
            WHEN LOWER(e.is_logged::text) IN ('1', 'true') THEN 1::smallint
            WHEN LOWER(e.is_logged::text) IN ('0', 'false') THEN 0::smallint
            ELSE NULL::smallint
        END AS is_logged,
        CASE
            WHEN e.content_id::text ~ '^[0-9]+$'
            THEN e.content_id::numeric(38, 0)
            ELSE NULL::numeric(38, 0)
        END AS content_id
    FROM spark_bsns_vlt.msp_ref_clickstream_events e
    WHERE e.event_name IN ('show_media_cover', 'media_cover_click')
      AND e.event_id IS NOT NULL
      AND e.device_id IS NOT NULL
      AND e.title IS NOT NULL
),
event_ranked AS (
    SELECT
        r.event_id,
        r.event_name,
        r.device_id,
        r.event_ts,
        r.path,
        r.row_id,
        r.subhead,
        r.item_type,
        r.position,
        r.title,
        r.title_norm,
        r.user_id,
        r.is_logged,
        r.content_id,
        ROW_NUMBER() OVER (
            PARTITION BY r.event_id
            ORDER BY
                r.event_ts DESC,
                r.event_name DESC,
                r.device_id DESC,
                r.title_norm DESC,
                r.content_id DESC NULLS LAST
        ) AS event_rn
    FROM event_base_raw r
),
event_base AS (
    SELECT
        r.event_id,
        r.event_name,
        r.device_id,
        r.event_ts,
        r.path,
        r.row_id,
        r.subhead,
        r.item_type,
        r.position,
        r.title,
        r.title_norm,
        r.user_id,
        r.is_logged,
        r.content_id
    FROM event_ranked r
    WHERE r.event_rn = 1
),
shows AS (
    SELECT
        e.event_id,
        e.device_id,
        e.event_ts,
        e.path,
        e.row_id,
        e.subhead,
        e.item_type,
        e.position,
        e.title,
        e.title_norm,
        e.user_id,
        e.is_logged
    FROM event_base e
    WHERE e.event_name = 'show_media_cover'
),
clicks AS (
    SELECT
        e.event_id,
        e.device_id,
        e.event_ts,
        e.path,
        e.row_id,
        e.item_type,
        e.position,
        e.title_norm,
        e.content_id
    FROM event_base e
    WHERE e.event_name = 'media_cover_click'
),
shows_numbered AS (
    SELECT
        s.event_id,
        s.device_id,
        s.event_ts,
        s.path,
        s.row_id,
        s.subhead,
        s.item_type,
        s.position,
        s.title,
        s.title_norm,
        s.user_id,
        s.is_logged,
        ROW_NUMBER() OVER (
            PARTITION BY
                s.event_ts::date,
                s.device_id,
                s.path,
                s.row_id,
                s.subhead,
                s.item_type,
                s.position,
                s.title_norm
            ORDER BY s.event_ts, s.event_id
        ) AS show_grain_rn
    FROM shows s
),
show_agg AS (
    SELECT
        s.event_ts::date AS event_date,
        s.device_id,
        s.path,
        s.row_id,
        s.subhead,
        s.item_type,
        s.position,
        s.title_norm,
        MAX(
            CASE WHEN s.show_grain_rn = 1 THEN s.title END
        )::text AS title,
        MAX(
            CASE WHEN s.show_grain_rn = 1 THEN s.user_id END
        )::numeric(38, 0) AS user_id,
        MAX(
            CASE WHEN s.show_grain_rn = 1 THEN s.is_logged END
        )::smallint AS is_logged,
        MIN(s.event_ts)::timestamp AS first_show_ts,
        MAX(s.event_ts)::timestamp AS last_show_ts,
        COUNT(*)::bigint AS show_count
    FROM shows_numbered s
    GROUP BY
        s.event_ts::date,
        s.device_id,
        s.path,
        s.row_id,
        s.subhead,
        s.item_type,
        s.position,
        s.title_norm
),
click_show_candidates AS (
    SELECT
        c.event_id AS click_event_id,
        c.event_ts AS click_ts,
        c.content_id,
        s.event_id AS show_event_id,
        s.device_id,
        s.event_ts AS show_ts,
        s.event_ts::date AS show_date,
        s.path,
        s.row_id,
        s.subhead,
        s.item_type,
        s.position,
        s.title,
        s.title_norm,
        s.user_id,
        s.is_logged,
        ROW_NUMBER() OVER (
            PARTITION BY c.event_id
            ORDER BY s.event_ts DESC, s.event_id
        ) AS attribution_rn
    FROM clicks c
    JOIN shows s
      ON s.device_id = c.device_id
     AND s.path IS NOT DISTINCT FROM c.path
     AND s.row_id IS NOT DISTINCT FROM c.row_id
     AND s.item_type IS NOT DISTINCT FROM c.item_type
     AND s.position IS NOT DISTINCT FROM c.position
     AND s.title_norm = c.title_norm
     AND s.event_ts <= c.event_ts
     AND s.event_ts > c.event_ts - INTERVAL '1 hour'
),
matched_clicks AS (
    SELECT
        c.click_event_id,
        c.click_ts,
        c.content_id,
        c.show_event_id,
        c.device_id,
        c.show_ts,
        c.show_date,
        c.path,
        c.row_id,
        c.subhead,
        c.item_type,
        c.position,
        c.title,
        c.title_norm,
        c.user_id,
        c.is_logged
    FROM click_show_candidates c
    WHERE c.attribution_rn = 1
),
matched_clicks_numbered AS (
    SELECT
        m.click_event_id,
        m.click_ts,
        m.content_id,
        m.show_event_id,
        m.device_id,
        m.show_ts,
        m.show_date,
        m.path,
        m.row_id,
        m.subhead,
        m.item_type,
        m.position,
        m.title,
        m.title_norm,
        m.user_id,
        m.is_logged,
        ROW_NUMBER() OVER (
            PARTITION BY
                m.show_date,
                m.device_id,
                m.path,
                m.row_id,
                m.subhead,
                m.item_type,
                m.position,
                m.title_norm
            ORDER BY m.click_ts, m.click_event_id
        ) AS click_grain_rn
    FROM matched_clicks m
),
click_agg AS (
    SELECT
        m.show_date AS event_date,
        m.device_id,
        m.path,
        m.row_id,
        m.subhead,
        m.item_type,
        m.position,
        m.title_norm,
        MIN(m.click_ts)::timestamp AS first_click_ts,
        MAX(m.click_ts)::timestamp AS last_click_ts,
        COUNT(*)::bigint AS click_count,
        MIN(m.content_id)::numeric(38, 0) AS content_id,
        COUNT(DISTINCT m.content_id)::bigint AS content_id_count,
        MAX(
            CASE
                WHEN m.click_grain_rn = 1
                THEN EXTRACT(EPOCH FROM m.click_ts - m.show_ts)
            END
        )::numeric(20, 3) AS seconds_show_to_first_click
    FROM matched_clicks_numbered m
    GROUP BY
        m.show_date,
        m.device_id,
        m.path,
        m.row_id,
        m.subhead,
        m.item_type,
        m.position,
        m.title_norm
),
valid_matched_clicks AS (
    SELECT
        m.click_event_id,
        m.click_ts,
        m.content_id,
        m.show_event_id,
        m.device_id,
        m.show_ts,
        m.show_date,
        m.path,
        m.row_id,
        m.subhead,
        m.item_type,
        m.position,
        m.title,
        m.title_norm,
        m.user_id,
        m.is_logged
    FROM matched_clicks m
    JOIN click_agg c
      ON c.event_date = m.show_date
     AND c.device_id = m.device_id
     AND c.path IS NOT DISTINCT FROM m.path
     AND c.row_id IS NOT DISTINCT FROM m.row_id
     AND c.subhead IS NOT DISTINCT FROM m.subhead
     AND c.item_type IS NOT DISTINCT FROM m.item_type
     AND c.position IS NOT DISTINCT FROM m.position
     AND c.title_norm = m.title_norm
     AND c.content_id_count = 1
     AND c.content_id = m.content_id
),
show_click AS (
    SELECT
        s.event_date,
        s.device_id,
        s.user_id,
        s.is_logged,
        s.title,
        s.title_norm,
        s.path,
        s.row_id,
        s.subhead,
        s.item_type,
        s.position,
        s.first_show_ts,
        s.last_show_ts,
        s.show_count,
        CASE
            WHEN COALESCE(c.click_count, 0) > 0 THEN 1::smallint
            ELSE 0::smallint
        END AS has_click,
        c.first_click_ts,
        c.last_click_ts,
        COALESCE(c.click_count, 0)::bigint AS click_count,
        CASE
            WHEN c.content_id_count = 1 THEN c.content_id
            ELSE NULL::numeric(38, 0)
        END AS content_id,
        CASE
            WHEN c.content_id_count > 1 THEN 1::smallint
            ELSE 0::smallint
        END AS content_id_conflict_flag,
        c.seconds_show_to_first_click
    FROM show_agg s
    LEFT JOIN click_agg c
      ON c.event_date = s.event_date
     AND c.device_id = s.device_id
     AND c.path IS NOT DISTINCT FROM s.path
     AND c.row_id IS NOT DISTINCT FROM s.row_id
     AND c.subhead IS NOT DISTINCT FROM s.subhead
     AND c.item_type IS NOT DISTINCT FROM s.item_type
     AND c.position IS NOT DISTINCT FROM s.position
     AND c.title_norm = s.title_norm
),
catalog_map AS (
    SELECT
        f.content_id::numeric(38, 0) AS content_id,
        CASE
            WHEN COUNT(DISTINCT f.top_parent_id) <= 1
            THEN COALESCE(
                MIN(f.top_parent_id)::numeric(38, 0),
                f.content_id::numeric(38, 0)
            )
            ELSE NULL::numeric(38, 0)
        END AS parent_content_id,
        CASE
            WHEN COUNT(DISTINCT f.top_parent_id) > 1 THEN 1::smallint
            ELSE 0::smallint
        END AS parent_content_conflict_flag
    FROM spark_dm.full_catalog f
    WHERE f.content_id IS NOT NULL
    GROUP BY f.content_id::numeric(38, 0)
),
vod_base AS (
    SELECT
        CASE
            WHEN v.vod_session_id IS NOT NULL
            THEN
                'id:' ||
                v.device_id::text || '|' ||
                v.vod_session_id::text
            ELSE
                'fallback:' ||
                COALESCE(v.user_id::text, '<null>') || '|' ||
                v.device_id::text || '|' ||
                v.content_id::text || '|' ||
                v.session_start_ts::text
        END::text AS vod_session_key,
        v.user_id::numeric(38, 0) AS user_id,
        v.device_id::text AS device_id,
        v.vod_session_id,
        v.content_id::numeric(38, 0) AS watched_content_id,
        CASE
            WHEN c.parent_content_conflict_flag = 1
            THEN NULL::numeric(38, 0)
            ELSE COALESCE(
                c.parent_content_id,
                v.content_id::numeric(38, 0)
            )
        END AS parent_content_id,
        v.session_start_ts::timestamp AS session_start_ts,
        v.session_end_ts::timestamp AS session_end_ts,
        v.duration_s::numeric(20, 3) AS duration_s,
        v.device_type::text AS device_type,
        v.t_w_crdate::timestamp AS t_w_crdate
    FROM spark_bsns_vlt.msp_content_session v
    LEFT JOIN catalog_map c
      ON c.content_id = v.content_id::numeric(38, 0)
    WHERE v.device_id IS NOT NULL
      AND v.content_id IS NOT NULL
      AND v.session_start_ts IS NOT NULL
),
vod_ranked AS (
    SELECT
        v.vod_session_key,
        v.user_id,
        v.device_id,
        v.vod_session_id,
        v.watched_content_id,
        v.parent_content_id,
        v.session_start_ts,
        v.session_end_ts,
        v.duration_s,
        v.device_type,
        v.t_w_crdate,
        ROW_NUMBER() OVER (
            PARTITION BY v.vod_session_key
            ORDER BY
                v.t_w_crdate DESC NULLS LAST,
                v.duration_s DESC NULLS LAST,
                v.session_end_ts DESC NULLS LAST
        ) AS vod_rn
    FROM vod_base v
),
vod_clean AS (
    SELECT
        v.vod_session_key,
        v.user_id,
        v.device_id,
        v.vod_session_id,
        v.watched_content_id,
        v.parent_content_id,
        v.session_start_ts,
        v.session_end_ts,
        v.device_type,
        v.duration_s::numeric(20, 3) AS raw_duration_s,
        CASE
            WHEN v.duration_s BETWEEN 1 AND 21600
            THEN v.duration_s::numeric(20, 3)
            WHEN v.duration_s IS NULL
             AND v.session_end_ts >= v.session_start_ts
             AND EXTRACT(
                    EPOCH FROM v.session_end_ts - v.session_start_ts
                 ) BETWEEN 1 AND 21600
            THEN EXTRACT(
                EPOCH FROM v.session_end_ts - v.session_start_ts
            )::numeric(20, 3)
            ELSE NULL::numeric(20, 3)
        END AS watch_time_s
    FROM vod_ranked v
    WHERE v.vod_rn = 1
      AND v.parent_content_id IS NOT NULL
),
click_vod_candidates AS (
    SELECT
        m.click_event_id,
        m.click_ts,
        m.content_id AS clicked_content_id,
        m.device_id,
        m.show_date,
        m.path,
        m.row_id,
        m.subhead,
        m.item_type,
        m.position,
        m.title_norm,
        v.vod_session_key,
        v.user_id AS watch_user_id,
        v.vod_session_id,
        v.watched_content_id,
        v.parent_content_id,
        v.session_start_ts,
        v.session_end_ts,
        v.raw_duration_s,
        v.watch_time_s,
        v.device_type,
        EXTRACT(
            EPOCH FROM v.session_start_ts - m.click_ts
        )::numeric(20, 3) AS seconds_click_to_watch,
        ROW_NUMBER() OVER (
            PARTITION BY v.vod_session_key
            ORDER BY m.click_ts DESC, m.click_event_id
        ) AS attribution_rn
    FROM valid_matched_clicks m
    JOIN vod_clean v
      ON v.device_id = m.device_id
     AND v.parent_content_id = m.content_id
     AND v.session_start_ts >= m.click_ts
     AND v.session_start_ts < m.click_ts + INTERVAL '24 hours'
),
attributed_vod AS (
    SELECT
        c.click_event_id,
        c.click_ts,
        c.clicked_content_id,
        c.device_id,
        c.show_date,
        c.path,
        c.row_id,
        c.subhead,
        c.item_type,
        c.position,
        c.title_norm,
        c.vod_session_key,
        c.watch_user_id,
        c.vod_session_id,
        c.watched_content_id,
        c.parent_content_id,
        c.session_start_ts,
        c.session_end_ts,
        c.raw_duration_s,
        c.watch_time_s,
        c.device_type,
        c.seconds_click_to_watch
    FROM click_vod_candidates c
    WHERE c.attribution_rn = 1
),
attributed_vod_numbered AS (
    SELECT
        a.click_event_id,
        a.click_ts,
        a.clicked_content_id,
        a.device_id,
        a.show_date,
        a.path,
        a.row_id,
        a.subhead,
        a.item_type,
        a.position,
        a.title_norm,
        a.vod_session_key,
        a.watch_user_id,
        a.vod_session_id,
        a.watched_content_id,
        a.parent_content_id,
        a.session_start_ts,
        a.session_end_ts,
        a.raw_duration_s,
        a.watch_time_s,
        a.device_type,
        a.seconds_click_to_watch,
        ROW_NUMBER() OVER (
            PARTITION BY
                a.show_date,
                a.device_id,
                a.path,
                a.row_id,
                a.subhead,
                a.item_type,
                a.position,
                a.title_norm
            ORDER BY a.session_start_ts, a.vod_session_key
        ) AS watch_grain_rn
    FROM attributed_vod a
),
watch_agg AS (
    SELECT
        a.show_date AS event_date,
        a.device_id,
        a.path,
        a.row_id,
        a.subhead,
        a.item_type,
        a.position,
        a.title_norm,
        CASE
            WHEN COUNT(DISTINCT a.watch_user_id) = 1
            THEN MIN(a.watch_user_id)::numeric(38, 0)
            ELSE NULL::numeric(38, 0)
        END AS watch_user_id,
        COUNT(DISTINCT a.watch_user_id)::bigint AS watch_user_id_count,
        MIN(a.session_start_ts)::timestamp AS first_watch_ts,
        MAX(a.session_end_ts)::timestamp AS last_watch_ts,
        COUNT(*)::bigint AS watch_session_count,
        COUNT(DISTINCT a.watched_content_id)::bigint AS watched_content_count,
        SUM(COALESCE(a.watch_time_s, 0))::numeric(20, 3) AS watch_time_s,
        MAX(
            CASE
                WHEN a.watch_grain_rn = 1
                THEN a.seconds_click_to_watch
            END
        )::numeric(20, 3) AS seconds_click_to_first_watch
    FROM attributed_vod_numbered a
    GROUP BY
        a.show_date,
        a.device_id,
        a.path,
        a.row_id,
        a.subhead,
        a.item_type,
        a.position,
        a.title_norm
)
SELECT
    s.event_date::date AS event_date,
    s.device_id::text AS device_id,
    s.user_id::numeric(38, 0) AS user_id,
    s.is_logged::smallint AS is_logged,
    s.title::text AS title,
    s.title_norm::text AS title_norm,
    s.path::text AS path,
    s.row_id::text AS row_id,
    s.subhead::text AS subhead,
    s.item_type::text AS item_type,
    s.position::integer AS position,
    s.first_show_ts::timestamp AS first_show_ts,
    s.last_show_ts::timestamp AS last_show_ts,
    s.show_count::bigint AS show_count,
    s.has_click::smallint AS has_click,
    s.first_click_ts::timestamp AS first_click_ts,
    s.last_click_ts::timestamp AS last_click_ts,
    s.click_count::bigint AS click_count,
    s.content_id::numeric(38, 0) AS content_id,
    s.content_id_conflict_flag::smallint AS content_id_conflict_flag,
    s.seconds_show_to_first_click::numeric(20, 3)
        AS seconds_show_to_first_click,
    CASE
        WHEN COALESCE(w.watch_session_count, 0) > 0 THEN 1::smallint
        ELSE 0::smallint
    END AS has_watch,
    w.watch_user_id::numeric(38, 0) AS watch_user_id,
    COALESCE(w.watch_user_id_count, 0)::bigint AS watch_user_id_count,
    w.first_watch_ts::timestamp AS first_watch_ts,
    w.last_watch_ts::timestamp AS last_watch_ts,
    COALESCE(w.watch_session_count, 0)::bigint AS watch_session_count,
    COALESCE(w.watched_content_count, 0)::bigint AS watched_content_count,
    COALESCE(w.watch_time_s, 0)::numeric(20, 3) AS watch_time_s,
    ROUND(
        (COALESCE(w.watch_time_s, 0) / 60.0)::numeric,
        2
    )::numeric(20, 2) AS watch_time_min,
    w.seconds_click_to_first_watch::numeric(20, 3)
        AS seconds_click_to_first_watch,
    CASE
        WHEN COALESCE(w.watch_time_s, 0) >= 30 THEN 1::smallint
        ELSE 0::smallint
    END AS watch_30s_flag,
    CASE
        WHEN COALESCE(w.watch_time_s, 0) >= 120 THEN 1::smallint
        ELSE 0::smallint
    END AS qualified_watch_flag,
    CASE
        WHEN COALESCE(w.watch_time_s, 0) >= 600 THEN 1::smallint
        ELSE 0::smallint
    END AS engaged_watch_flag
FROM show_click s
LEFT JOIN watch_agg w
  ON w.event_date = s.event_date
 AND w.device_id = s.device_id
 AND w.path IS NOT DISTINCT FROM s.path
 AND w.row_id IS NOT DISTINCT FROM s.row_id
 AND w.subhead IS NOT DISTINCT FROM s.subhead
 AND w.item_type IS NOT DISTINCT FROM s.item_type
 AND w.position IS NOT DISTINCT FROM s.position
 AND w.title_norm = s.title_norm
;
