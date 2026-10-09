{{ config(
    pre_hook=["
        INSTALL spatial;
        LOAD spatial;
    "]
)}}

with deltas as (
    SELECT 
        *,    
        time - LAG(time) OVER (PARTITION BY track_uid ORDER BY time) AS time_delta,
        LAG(lat) OVER (PARTITION BY track_uid ORDER BY time) AS last_lat,
        LAG(lon) OVER (PARTITION BY track_uid ORDER BY time) AS last_lon,
        ST_Point(lat, lon) AS p1,
        ST_Point(last_lat, last_lon) AS p2,
        -- ST_SetCRS(ST_Point(lat, lon), 'EPSG:4326') AS p1,
        -- ST_SetCRS(ST_Point(last_lat, last_lon), 'EPSG:4326') AS p2,
        ST_Distance_Spheroid(p1, p2) AS distance_delta
    FROM {{ ref('01b_subtrack') }}
), split_marks AS (
  SELECT 
    *,
    CASE 
      WHEN epoch(time_delta) > 3600 THEN true
      ELSE false
    END AS split
    FROM deltas
    WHERE
        time_delta IS NULL
        OR epoch(time_delta) > 0
),
segmented as (
    select
        *,
        -- Genera un contador incremental (0, 1, 2...) dentro de cada track cada vez que split es TRUE
        sum(case when split then 1 else 0 end) over (
            partition by track_uid
            order by time
            rows between unbounded preceding and current row
        ) as segment_id,
        
        -- Cuenta cuántos splits totales tiene el track para saber si fue dividido
        count(case when split then 1 end) over (
            partition by track_uid
        ) as total_splits
    from split_marks
)
select
    -- Mantiene todas las columnas originales salvo track_uid
    * exclude (track_uid, segment_id, total_splits),
    -- Si el track tuvo algún split, concatena '_segX', si no, conserva el original
    case 
        when total_splits > 0 
        then track_uid::VARCHAR || '_seg' || (segment_id + 1)
        else track_uid::VARCHAR 
    end as track_uid
from segmented
