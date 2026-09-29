{{ config(
    materialized='table',
    post_hook="COPY {{ this }} TO 'data/tracklog_clean.parquet' (FORMAT PARQUET)"
) }}

WITH grid_data AS (
    SELECT * FROM {{ ref('int_tracklog_grid_imputed') }}
),
preparado AS (
    SELECT 
        *,
        CASE WHEN ele < 0 THEN NULL ELSE ele END AS ele_valida
    FROM grid_data
),
vecinos AS (
    SELECT 
        *,
        LAST_VALUE(ele_valida IGNORE NULLS) OVER (
            ORDER BY time ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_ele,
        LAST_VALUE(time IGNORE NULLS) OVER (
            ORDER BY time ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_time,
        FIRST_VALUE(ele_valida IGNORE NULLS) OVER (
            ORDER BY time ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
        ) AS next_ele,
        FIRST_VALUE(time IGNORE NULLS) OVER (
            ORDER BY time ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
        ) AS next_time
    FROM preparado
)
SELECT 
    source,
    track_name,
    track_type,
    track_fid,
    track_seg_id,
    track_seg_point_id,
    time,
    lat,
    lon,
    CASE 
        -- Si era un valor negativo (<0), aplicamos la fórmula de interpolación lineal por tiempo
        WHEN ele < 0 AND prev_ele IS NOT NULL AND next_ele IS NOT NULL THEN
            ROUND(
                prev_ele + (next_ele - prev_ele) * 
                (epoch(time) - epoch(prev_time)) / (epoch(next_time) - epoch(prev_time)), 
                2
            )
        -- Si era un valor normal o NULL, se conserva sin modificar
        ELSE ele 
    END AS ele,
    source_file,
    geometry
FROM vecinos