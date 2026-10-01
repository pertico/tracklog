INSTALL spatial;
LOAD spatial;

-- COPY (
CREATE OR REPLACE VIEW tracklog_processed AS 
	WITH tracklog_unique AS (
		-- Paso 0: Extraer timestamps únicos con media de lat, lon y ele
		SELECT DISTINCT 
			time, 
			mean(lat) AS lat, 
			mean(lon) AS lon, 
			mean(round(ele)) AS ele
		FROM tracklog
		WHERE time IS NOT NULL
		GROUP BY time
	),
	tracklog_lag AS (
        -- Paso 1: Ordenar y traer el punto anterior
        SELECT 
        	time, 
        	lat, 
        	lon, 
        	ele,
            ST_Point(lat, lon) as geom,
            LAG(ST_Point(lat, lon)) OVER(ORDER BY time) as geom_prev,
            LAG(time) OVER(ORDER BY time) as time_prev
        FROM tracklog_unique
        WHERE time IS NOT NULL AND lat IS NOT NULL AND lon IS NOT NULL
    ),
    tracklog_delta AS (
        -- Paso 2: Calcular tiempo (segundos) e interceptar saltos intercontinentales (> 8 horas)
        SELECT *,
            COALESCE(epoch(time) - epoch(time_prev), 0) as time_delta,            
            CASE 
                WHEN geom_prev IS NULL THEN 0
                WHEN (epoch(time) - epoch(time_prev)) > 28800 THEN 0 
                ELSE COALESCE(ST_Distance_Spheroid(geom, geom_prev), 0)
            END as distance_delta_raw
        FROM tracklog_lag
    ),
    tracklog_delta_nan AS (
        -- Paso 3: Controlar valores NaN de la función espacial
        SELECT *,
            CASE 
                WHEN isnan(distance_delta_raw) OR distance_delta_raw = 'NaN'::DOUBLE THEN 0 
                ELSE distance_delta_raw 
            END as distance_delta
        FROM tracklog_delta
    ),
    tracklog_speed AS (
        -- Paso 4: Calcular velocidad evitando la división por cero y convirtiendo a km/h
        SELECT *,
            CASE 
                WHEN time_delta = 0 THEN 0
                -- (metros / segundos) * 3.6 = km/h
                ELSE (distance_delta / time_delta) * 3.6 
            END as speed_kmh
        FROM tracklog_delta_nan
    ),
    tracklog_new_track AS (
        -- Paso 5: Marcar puntos de corte para los IDs de los tracks
        SELECT *,
            CASE 
                WHEN geom_prev IS NULL THEN 1
                WHEN distance_delta > 1000 THEN 1  -- Más de 1000 metros
                WHEN time_delta > 28800 THEN 1     -- Más de 8 horas
                ELSE 0
            END as new_track
        FROM tracklog_speed
    )
    -- Paso 6: Generar track_id y FILTRAR puntos aberrantes   
    SELECT 
        SUM(new_track) OVER(ORDER BY time) as track_id,
        time,
        lat,
        lon,
        ele,
        distance_delta,
        time_delta,
        ROUND(speed_kmh, 2) as speed_kmh
    FROM tracklog_new_track
    -- >>> FILTRO DE PRECISIÓN <<<
    WHERE speed_kmh <= 120.0     -- Filtramos saltos imposibles provocados por rebotes de señal (ej: > 120 km/h)  
      AND ((distance_delta > 0 AND new_track = 0) OR new_track = 1) -- Elimino puntos intermedios consecutivos en la misma posición
--    ORDER BY time
;
-- ) TO 'tracklog_limpio_velocidad.parquet' (FORMAT PARQUET);
      
      
      
COPY (
        SELECT 
            track_id AS "track",  -- GPSBabel identificará esto como el ID/Nombre del track
            0 AS "trackseg",
            lat AS "latitude",
            lon AS "longitude",
            ele AS "altitude",    -- Altitud en metros
            -- GPSBabel requiere formato ISO: YYYY-MM-DD HH:MM:SS
            strftime(time, '%Y-%m-%d %H:%M:%S') AS "time" 
        FROM tracklog_processed
    --    WHERE date_part('year', time) = 2010 -- El año que quieres exportar
        ORDER BY track_id, time
) TO '../../OneDrive/Documentos/GPS/tracklog.csv' (HEADER TRUE);

-- gpsbabel -t -i unicsv -f trackslog.csv -x track,split,title="%Y%m%d" -o gpx -F tracklog.gpx


