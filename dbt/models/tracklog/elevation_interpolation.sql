WITH ventana_vecinos AS (
    SELECT 
        *,
        -- Vecino anterior válido dentro de la misma ruta
        LAST_VALUE(ele IGNORE NULLS) OVER (
            PARTITION BY track_uid
            ORDER BY time 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_ele,
        
        -- Vecino posterior válido dentro de la misma ruta
        FIRST_VALUE(ele IGNORE NULLS) OVER (
            PARTITION BY track_uid
            ORDER BY time 
            ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
        ) AS next_ele
    FROM {{ ref('elevation_grid') }}
)
SELECT 
    track_uid,
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
        -- Caso 1: Punto positivo original (se mantiene)
        WHEN ele >= 0 THEN ele
        -- Caso 2: Intermedio con vecinos a ambos lados (Interpolación)
        WHEN prev_ele IS NOT NULL AND next_ele IS NOT NULL THEN 
            ROUND((prev_ele + next_ele) / 2.0, 3)
        -- Caso 3: Extremo INICIAL (Sin vecino previo -> Toma el primer valor válido posterior)
        WHEN prev_ele IS NULL AND next_ele IS NOT NULL THEN next_ele
        -- Caso 4: Extremo FINAL (Sin vecino posterior -> Toma el último valor válido previo)
        WHEN prev_ele IS NOT NULL AND next_ele IS NULL THEN prev_ele
        -- Caso 5: Si TODO el track tuviera alturas negativas (Mantiene NULL para paso DEM)
        ELSE NULL 
    END AS ele,
    source_file,
    geometry
FROM ventana_vecinos