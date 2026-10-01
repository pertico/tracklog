WITH ordered_data AS (
    SELECT 
        track_uid,
        time,
        geometry
    FROM {{ ref('clean_phase_2') }}
    ORDER BY time
)
SELECT 
    track_uid,
    min(time) AS start_time, 
    max(time) AS end_time, 
    count(*) AS points,
    -- Concatena lat y lon formateados, asegurando el orden por el timestamp del GPS
    -- md5(string_agg(lat::VARCHAR || ',' || lon::VARCHAR, ';' ORDER BY timestamp ASC)) AS track_hash,
    -- Utilizado el campo geometry
    md5(string_agg(geometry::VARCHAR)) AS track_hash,
    md5(start_time || '::' || end_time || '::' || points) AS track_hash_simple
FROM ordered_data
GROUP BY track_uid
