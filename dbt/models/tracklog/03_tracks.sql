{{ config(
    pre_hook=["
        -- Asegurarse de tener cargada la extensión espacial
        install spatial;
        load spatial;    
    "],
    post_hook=["
        copy {{ this }} to '../data/tracks.parquet' (format parquet)
    "]
)}}

WITH deltas AS (
    SELECT 
        * EXCLUDE (time_delta, distance_delta),    
        time - LAG(time) OVER (PARTITION BY track_uid ORDER BY time) AS time_delta,
        LAG(lat) OVER (PARTITION BY track_uid ORDER BY time) AS last_lat,
        LAG(lon) OVER (PARTITION BY track_uid ORDER BY time) AS last_lon,
        ST_Point(lat, lon) AS p1,
        ST_Point(last_lat, last_lon) AS p2,
        -- ST_SetCRS(ST_Point(lat, lon), 'EPSG:4326') AS p1,
        -- ST_SetCRS(ST_Point(last_lat, last_lon), 'EPSG:4326') AS p2,
        ST_Distance_Spheroid(p1, p2) AS distance_delta
FROM {{ ref('02_split') }}
), summary AS (
    SELECT 
        track_uid,
        min(time) AS start_time, 
        max(time) AS end_time, 
        count(1) AS points
    FROM deltas
    GROUP BY track_uid    
)
select
    s.*,
    -- Genera un LINESTRING ordenado por tiempo para cada track
    g.track_geometry AS geometry
from summary as s
left join (
    select
        track_uid,
        st_makeline(
            list(st_point(lon, lat) order by time)
        ) as track_geometry
    from {{ ref('02_split') }}
    group by track_uid
    having count(1) > 1
) as g on s.track_uid::VARCHAR = g.track_uid
where s.points > 1
