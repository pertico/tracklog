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

WITH summary AS (
    SELECT 
        track_uid,
        min(time) AS start_time, 
        max(time) AS end_time, 
        count(1) AS points
    FROM {{ ref('04_delta') }}
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
    from {{ ref('04_delta') }}
    group by track_uid
    having count(1) > 1
) as g on s.track_uid::VARCHAR = g.track_uid
where s.points > 1
