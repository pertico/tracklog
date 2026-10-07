{{ config (
    post_hook=["
        CREATE OR REPLACE VIEW summary AS
            SELECT 
                track_uid,
                content_digest,
                summary_digest,
                min(time) AS start_time, 
                max(time) AS end_time, 
                count(*) AS points
            FROM {{ this }}
            GROUP BY track_uid, content_digest, summary_digest
        "]
)}}
WITH parquet_file AS (
    -- Lectura directa del Parquet original generado por el script de Python
    SELECT * 
    FROM '../data/tracklog.parquet'
),
source_data AS (
    SELECT 
    -- Generar UUID determinista v5/MD5 combinando source, source_file, track_name y track_fid
    CAST(
        MD5(COALESCE(source, '') || '::' ||
            COALESCE(source_file, '') || '::' || 
            COALESCE(track_name, '') || '::' || 
            COALESCE(CAST(track_fid AS VARCHAR), '0')
        ) AS UUID
    ) AS track_uid,
    * EXCLUDE (geometry)
FROM parquet_file 
WHERE time IS NOT NULL
),
summary AS (
    SELECT 
        track_uid,
        min(time) AS start_time, 
        max(time) AS end_time, 
        count(*) AS points,
        -- Concatena lat y lon formateados, asegurando el orden por el timestamp del GPS
        -- md5(string_agg(round(lat,5)::VARCHAR || '::' || round(lon,5)::VARCHAR, ';' ORDER BY time ASC)) AS content_digest,
        -- Utilizando únicamente el timestamp
        md5(string_agg(time::VARCHAR, ';' ORDER BY time ASC)) AS content_digest,
        -- Utilizado el campo geometry
        -- md5(string_agg(geometry::VARCHAR, ';' ORDER BY time ASC)) AS track_hash,
        -- Creamos también un hash por hora de inicio y comienzo más el nº de puntos
        -- El hash por geometría falla por cambios de precisión.
        md5(start_time || '::' || end_time || '::' || points) AS summary_digest
    FROM source_data
    GROUP BY track_uid
),
unique_tracks AS (
    SELECT 
        content_digest,
        min(track_uid) AS track_uid
    FROM summary
    GROUP BY content_digest
)
SELECT 
    t.track_uid,
    s.content_digest,
    s.summary_digest,
    t.source,
    t.track_name,
    t.track_type,
    t.track_fid,
    t.track_seg_id,
    t.track_seg_point_id,
    t.time,
    t.lat,
    t.lon,
    t.ele,
    t.source_file
FROM 
    source_data t
    INNER JOIN summary s USING (track_uid)
    INNER JOIN unique_tracks u USING (track_uid)