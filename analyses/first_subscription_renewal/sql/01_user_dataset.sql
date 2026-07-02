-- User-level dataset for first subscription renewal research.
-- One row = one user.
-- Read-only query: no DDL/DML, no SELECT *, no phone/IP/device_id fields.

with
subscription_ranked as (
    select
        s.user_id,
        s.start_date as sub_start,
        s.end_date as sub_end,
        s.type as sub_type,
        s.provider,
        row_number() over (
            partition by s.user_id
            order by s.start_date asc, s.end_date asc
        ) as sub_num
    from spark_bsns_vlt.msp_ref_subscriptions s
    where s.user_id is not null
      and s.start_date is not null
      and s.end_date is not null
),
first_sub as (
    select
        r.user_id,
        r.sub_start as first_sub_start,
        r.sub_end as first_sub_end,
        r.sub_type as first_sub_type,
        r.provider
    from subscription_ranked r
    where r.sub_num = 1
),
cohort as (
    select
        f.user_id,
        f.first_sub_start,
        f.first_sub_end,
        f.first_sub_type,
        f.provider
    from first_sub f
    where f.first_sub_start >= timestamp '2026-01-01 00:00:00'
      and f.first_sub_start < timestamp '2026-05-01 00:00:00'
      and f.first_sub_end + interval '7 day' <= current_date
),
target as (
    select
        c.user_id,
        case
            when min(n.sub_start) <= c.first_sub_end + interval '7 day' then 1
            else 0
        end as renewed_7d
    from cohort c
    left join subscription_ranked n
        on n.user_id = c.user_id
       and n.sub_start > c.first_sub_end
    group by
        c.user_id,
        c.first_sub_end
),
vod_sessions as (
    select
        c.user_id,
        v.session_start_ts,
        v.content_id,
        v.content_type,
        v.duration_s
    from cohort c
    join spark_bsns_vlt.msp_content_session v
        on v.user_id = c.user_id
       and v.session_start_ts >= c.first_sub_start
       and v.session_start_ts <= c.first_sub_end
),
vod_agg as (
    select
        v.user_id,
        count(*) as vod_sessions_cnt,
        count(distinct v.session_start_ts::date) as vod_active_days,
        count(distinct v.content_id) as distinct_titles,
        sum(case when v.duration_s > 0 then v.duration_s else 0 end) / 3600.0 as vod_watch_hours,
        count(*) filter (where v.content_type = 'series' or v.content_type = 'episode') as series_sessions_cnt,
        count(*) filter (where v.content_type = 'movie') as movie_sessions_cnt
    from vod_sessions v
    group by v.user_id
),
catalog_latest as (
    select
        t.content_id,
        t.genres
    from (
        select
            c.content_id,
            c.genres,
            row_number() over (
                partition by c.content_id
                order by c.start_date desc nulls last
            ) as rn
        from spark_bsns_vlt.msp_ref_catalog_content c
        where c.content_id is not null
    ) t
    where t.rn = 1
),
vod_genres as (
    select
        v.user_id,
        lower(btrim(g.genre)) as genre_norm
    from (
        select distinct
            vs.user_id,
            vs.content_id
        from vod_sessions vs
        where vs.content_id is not null
    ) v
    join catalog_latest c
        on c.content_id = v.content_id
    cross join lateral regexp_split_to_table(coalesce(c.genres, ''), ';') as g(genre)
    where btrim(g.genre) <> ''
),
vod_genres_agg as (
    select
        vg.user_id,
        count(distinct vg.genre_norm) as distinct_genres
    from vod_genres vg
    group by vg.user_id
),
tv_sessions as (
    select
        c.user_id,
        t.session_start_ts,
        t.duration_s
    from cohort c
    join spark_bsns_vlt.msp_ref_tv_session t
        on t.user_id = c.user_id
       and t.session_start_ts >= c.first_sub_start
       and t.session_start_ts <= c.first_sub_end
),
tv_agg as (
    select
        t.user_id,
        count(*) as tv_sessions_cnt,
        count(distinct t.session_start_ts::date) as tv_days,
        sum(case when t.duration_s > 0 then t.duration_s else 0 end) / 3600.0 as tv_watch_hours
    from tv_sessions t
    group by t.user_id
),
activity_events as (
    select
        v.user_id,
        v.session_start_ts,
        v.duration_s
    from vod_sessions v

    union all

    select
        t.user_id,
        t.session_start_ts,
        t.duration_s
    from tv_sessions t
),
activity_agg as (
    select
        c.user_id,
        count(a.session_start_ts) as sessions_cnt,
        count(distinct a.session_start_ts::date) as active_days,
        sum(case when a.duration_s > 0 then a.duration_s else 0 end) / 3600.0 as total_watch_hours,
        max(case
            when a.session_start_ts >= c.first_sub_start
             and a.session_start_ts < c.first_sub_start + interval '24 hour'
            then 1 else 0
        end) as viewed_first_24h,
        max(case
            when a.session_start_ts >= c.first_sub_start
             and a.session_start_ts < c.first_sub_start + interval '3 day'
            then 1 else 0
        end) as viewed_first_3d,
        max(case
            when a.session_start_ts >= c.first_sub_end - interval '3 day'
             and a.session_start_ts <= c.first_sub_end
            then 1 else 0
        end) as viewed_last_3d
    from cohort c
    left join activity_events a
        on a.user_id = c.user_id
    group by
        c.user_id,
        c.first_sub_start,
        c.first_sub_end
)
select
    c.user_id,
    c.first_sub_start,
    c.first_sub_end,
    c.first_sub_type,
    case
        when c.first_sub_type in ('trial', 'promo') then c.first_sub_type
        else 'paid'
    end as first_sub_type_group,
    c.provider,
    t.renewed_7d,
    coalesce(a.total_watch_hours, 0) as total_watch_hours,
    coalesce(a.active_days, 0) as active_days,
    coalesce(a.sessions_cnt, 0) as sessions_cnt,
    coalesce(v.distinct_titles, 0) as distinct_titles,
    coalesce(g.distinct_genres, 0) as distinct_genres,
    coalesce(a.viewed_first_24h, 0) as viewed_first_24h,
    coalesce(a.viewed_first_3d, 0) as viewed_first_3d,
    coalesce(a.viewed_last_3d, 0) as viewed_last_3d,
    case when coalesce(tv.tv_sessions_cnt, 0) > 0 then 1 else 0 end as has_tv,
    coalesce(tv.tv_days, 0) as tv_days,
    coalesce(v.vod_watch_hours, 0) as vod_watch_hours,
    coalesce(tv.tv_watch_hours, 0) as tv_watch_hours,
    coalesce(v.vod_sessions_cnt, 0) as vod_sessions_cnt,
    coalesce(tv.tv_sessions_cnt, 0) as tv_sessions_cnt,
    case
        when coalesce(v.vod_sessions_cnt, 0) > 0 and coalesce(tv.tv_sessions_cnt, 0) > 0 then 'VOD + TV'
        when coalesce(v.vod_sessions_cnt, 0) > 0 then 'VOD only'
        when coalesce(tv.tv_sessions_cnt, 0) > 0 then 'TV only'
        else 'No views'
    end as consumption_segment,
    coalesce(v.series_sessions_cnt, 0) as series_sessions_cnt,
    coalesce(v.movie_sessions_cnt, 0) as movie_sessions_cnt
from cohort c
join target t
    on t.user_id = c.user_id
left join activity_agg a
    on a.user_id = c.user_id
left join vod_agg v
    on v.user_id = c.user_id
left join vod_genres_agg g
    on g.user_id = c.user_id
left join tv_agg tv
    on tv.user_id = c.user_id;
