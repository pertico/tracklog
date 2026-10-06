{{ config (
    post_hook=["
        CREATE OR REPLACE VIEW summary AS
            SELECT 
                track_uid,
                min(time) AS start_time, 
                max(time) AS end_time, 
                count(*) AS points,
                max(time)-min(time) AS duration,
                SUM(distance_delta)/1000 AS distance_km,
                3.6 * SUM(distance_delta)/(epoch(max(time))-epoch(min(time))) AS avg_speed_kmh
            FROM '03_split'
            GROUP BY track_uid
        "]
)}}

with split_marks AS (
  SELECT 
    *,
    CASE 
      WHEN epoch(time_delta) > 3600 THEN true
      ELSE false
    END AS split
    FROM {{ ref('02_delta') }}
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
