WITH source_data AS (
    -- Lectura directa del Parquet original generado por el script de Python
    SELECT * 
    FROM '../data/tracklog.parquet'
)
SELECT 
    -- Generar UUID determinista v5/MD5 combinando source, source_file, track_name y track_fid
    CAST(
        MD5(COALESCE(source, '') || '::' ||
            COALESCE(source_file, '') || '::' || 
            COALESCE(track_name, '') || '::' || 
            COALESCE(CAST(track_fid AS VARCHAR), '0')
        ) AS UUID
    ) AS track_uid,
    source,
    track_name,
    track_type,
    track_fid,
    track_seg_id,
    track_seg_point_id,
    time,
    lat,
    lon,
    ele,
    source_file,
    geometry
FROM source_data 
WHERE time IS NOT NULL