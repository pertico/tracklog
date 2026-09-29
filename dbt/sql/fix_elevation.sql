INSTALL spatial;
LOAD spatial;

-- Con JOIN espacial, se queda colgado
CREATE OR REPLACE VIEW tracklog_ele_imputed AS
WITH puntos_con_ele AS (
    -- Puntos de referencia con elevación válida
    -- ST_Point(lat, lon) para funciones esferoidales
    SELECT 
        time,
        ST_Point(lat, lon) AS geom_esferoide,
        ele
    FROM tracklog
    WHERE ele IS NOT NULL AND lat IS NOT NULL AND lon IS NOT NULL
),
puntos_sin_ele AS (
    -- Puntos a imputar
    SELECT 
        t.time,
        t.lat,
        t.lon,
        ST_Point(t.lat, t.lon) AS geom_esferoide
    FROM tracklog t
    WHERE t.ele IS NULL AND t.lat IS NOT NULL AND t.lon IS NOT NULL
),
imputacion AS (
    -- Unimos puntos sin ele con los puntos con ele a <= 5 metros
    SELECT 
        s.time,
        s.lat,
        s.lon,
        AVG(r.ele) AS ele_imputada
    FROM puntos_sin_ele s
    JOIN puntos_con_ele r 
      ON ST_DWithin_Spheroid(s.geom_esferoide, r.geom_esferoide, 5.0) -- Radio de 5 metros
    GROUP BY s.time, s.lat, s.lon
)
-- Reconstrucción final de la tabla
SELECT 
    t.source,
    t.track_name,
    t.track_type,
    t.track_fid,
    t.track_seg_id,
    t.track_seg_point_id,
    t.time,
    t.lat,
    t.lon,
    -- Si ele existe, se conserva; si era NULL, toma la media imputada redondeada
    COALESCE(t.ele, ROUND(i.ele_imputada, 2)) AS ele,
    t.source_file,
    t.geometry
FROM tracklog t
LEFT JOIN imputacion i 
  ON t.time = i.time AND t.lat = i.lat AND t.lon = i.lon;

-- Con cuadrícula 10x10
CREATE OR REPLACE VIEW tracklog_ele_imputed AS
WITH grid_elevations AS (
    -- Paso 1: Crear una matriz/cuadrícula con la media de elevación 
    -- redondeando coordenadas a 4 decimales (~10-11 metros)
    SELECT 
        ROUND(lat, 4) AS lat_grid,
        ROUND(lon, 4) AS lon_grid,
        AVG(ele) AS ele_media_grid
    FROM tracklog
    WHERE ele IS NOT NULL AND lat IS NOT NULL AND lon IS NOT NULL
    GROUP BY ROUND(lat, 4), ROUND(lon, 4)
)
-- Paso 2: Unir los puntos originales con la cuadrícula de elevaciones
SELECT 
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
    COALESCE(t.ele, ROUND(g.ele_media_grid, 2)) AS ele,
    t.source_file,
    t.geometry
FROM tracklog t
LEFT JOIN grid_elevations g
  ON ROUND(t.lat, 4) = g.lat_grid 
 AND ROUND(t.lon, 4) = g.lon_grid;

--
SELECT 
    count(*) as total,
    count(ele) as con_ele,
    ROUND(count(ele) * 100.0 / count(*), 2) as pct_con_ele
FROM tracklog_ele_imputed;  


---
- Interpolación de valores de elevación negativos
WITH limpia AS (
    SELECT 
        time,
        lat,
        lon,
        CASE WHEN ele < 0 THEN NULL ELSE ele END AS ele
    FROM 'tracklog.parquet'
),
vecinos AS (
    SELECT 
        time,
        ele,
        -- Último valor válido anterior
        LAST_VALUE(ele IGNORE NULLS) OVER (ORDER BY time ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prev_ele,
        LAST_VALUE(time IGNORE NULLS) OVER (ORDER BY time ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prev_time,
        -- Primer valor válido posterior
        FIRST_VALUE(ele IGNORE NULLS) OVER (ORDER BY time ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING) AS next_ele,
        FIRST_VALUE(time IGNORE NULLS) OVER (ORDER BY time ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING) AS next_time
    FROM limpia
)
SELECT 
    time,
    CASE 
        WHEN ele IS NOT NULL THEN ele
        WHEN prev_ele IS NOT NULL AND next_ele IS NOT NULL THEN
            ROUND(
                prev_ele + (next_ele - prev_ele) * 
                (epoch(time) - epoch(prev_time)) / (epoch(next_time) - epoch(prev_time)), 
                2
            )
        ELSE NULL 
    END AS ele_interpolada
FROM vecinos;