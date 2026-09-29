{{ config(materialized='ephemeral') }} -- Modelo intermedio en memoria

WITH raw_data AS (
    SELECT * FROM {{ ref('stg_tracklog') }}
),
grid_reference AS (
    -- Matriz de elevación promediada por celda de ~10m
    SELECT 
        ROUND(lat, 4) AS lat_grid,
        ROUND(lon, 4) AS lon_grid,
        AVG(ele) AS ele_media_grid
    FROM raw_data
    WHERE ele IS NOT NULL
    GROUP BY ROUND(lat, 4), ROUND(lon, 4)
)
SELECT 
    t.* EXCLUDE(ele),
    COALESCE(t.ele, ROUND(g.ele_media_grid, 2)) AS ele
FROM raw_data t
LEFT JOIN grid_reference g
  ON ROUND(t.lat, 4) = g.lat_grid 
 AND ROUND(t.lon, 4) = g.lon_grid