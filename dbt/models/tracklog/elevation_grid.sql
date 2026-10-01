
WITH grid_elevations AS (
    -- Paso 1: Crear una matriz/cuadrícula con la media de elevación 
    -- redondeando coordenadas a 4 decimales (~10-11 metros)
    SELECT 
        ROUND(lat, 4) AS lat_grid,
        ROUND(lon, 4) AS lon_grid,
        AVG(ele) AS ele_media_grid
    FROM {{ ref('clean_phase_1') }} 
    WHERE ele IS NOT NULL AND lat IS NOT NULL AND lon IS NOT NULL
    GROUP BY ROUND(lat, 4), ROUND(lon, 4)
)
-- Paso 2: Unir los puntos originales con la cuadrícula de elevaciones
SELECT 
    t.track_uid,
    t.source,
    t.track_name,
    t.track_type,
    t.track_fid,
    t.track_seg_id,
    t.track_seg_point_id,
    t.time,
    t.lat,
    t.lon,
    -- Si ele es NULL, busca la media del grid de 10 metros
    COALESCE(t.ele, ROUND(g.ele_media_grid, 3)) AS ele,
    t.source_file,
    t.geometry
FROM {{ ref('clean_phase_1') }} t
LEFT JOIN grid_elevations g
  ON ROUND(t.lat, 4) = g.lat_grid 
 AND ROUND(t.lon, 4) = g.lon_grid
