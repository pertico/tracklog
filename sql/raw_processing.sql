INSTALL spatial;
LOAD spatial;

COPY (
    WITH datos_ordenados AS (
        -- Paso 1: Ordenar y traer el punto anterior
        SELECT 
            time,
            lat,
            lon,
            ele,
            ST_Point(lon, lat) as geom,
            LAG(ST_Point(lon, lat)) OVER(ORDER BY time) as geom_prev,
            LAG(time) OVER(ORDER BY time) as time_prev
        FROM '../../OneDrive/Documentos/GPS/tracklog_raw.parquet'
        WHERE time IS NOT NULL AND lat IS NOT NULL AND lon IS NOT NULL
    ),
    calculo_deltas AS (
        -- Paso 2: Calcular tiempo (segundos) e interceptar saltos intercontinentales (> 3 horas)
        SELECT *,
            COALESCE(epoch(time) - epoch(time_prev), 0) as delta_tiempo,
            
            CASE 
                WHEN geom_prev IS NULL THEN 0
                WHEN (epoch(time) - epoch(time_prev)) > 10800 THEN 0 
                ELSE COALESCE(ST_Distance_Spheroid(geom, geom_prev), 0)
            END as delta_distancia_cruda
        FROM datos_ordenados
    ),
    limpieza_nan AS (
        -- Paso 3: Controlar valores NaN de la función espacial
        SELECT *,
            CASE 
                WHEN isnan(delta_distancia_cruda) OR delta_distancia_cruda = 'NaN'::DOUBLE THEN 0 
                ELSE delta_distancia_cruda 
            END as delta_distancia
        FROM calculo_deltas
    ),
    calculo_velocidad AS (
        -- Paso 4: Calcular velocidad evitando la división por cero y convirtiendo a km/h
        SELECT *,
            CASE 
                WHEN delta_tiempo = 0 THEN 0
                -- (metros / segundos) * 3.6 = km/h
                ELSE (delta_distancia / delta_tiempo) * 3.6 
            END as velocidad_kmh
        FROM limpieza_nan
    ),
    banderas_corte AS (
        -- Paso 5: Marcar puntos de corte para los IDs de los tracks
        SELECT *,
            CASE 
                WHEN geom_prev IS NULL THEN 1
                WHEN delta_distancia > 100 THEN 1  -- Más de 100 metros
                WHEN delta_tiempo > 300 THEN 1     -- Más de 5 minutos
                ELSE 0
            END as es_nuevo_track
        FROM calculo_velocidad
    )
    -- Paso 6: Generar track_id y FILTRAR puntos aberrantes
    SELECT 
        SUM(es_nuevo_track) OVER(ORDER BY time) as track_id,
        time,
        lat,
        lon,
        ele,
        delta_distancia,
        delta_tiempo,
        ROUND(velocidad_kmh, 2) as velocidad_kmh
    FROM banderas_corte
    -- >>> FILTRO DE PRECISIÓN <<<
    -- Filtramos saltos imposibles provocados por rebotes de señal (ej: > 120 km/h)
    WHERE velocidad_kmh <= 120.0
    ORDER BY time

) TO '../../OneDrive/Documentos/GPS/tracklog_processed.parquet' (FORMAT PARQUET);