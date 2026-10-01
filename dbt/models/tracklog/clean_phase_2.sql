WITH unique_tracks AS (
    SELECT 
        -- Usamos track_hash_simple porque el 'completo" cambia por precision
        -- de la geometría 
        track_hash_simple AS track_hash,
        min(track_uid) AS track_uid
    FROM {{ ref('summary_phase_1') }}
    GROUP BY track_hash_simple
)
SELECT 
    t.track_uid,
    s.track_hash,
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
    t.source_file,
    t.geometry
FROM 
    {{ ref('clean_phase_1') }} t
    INNER JOIN {{ ref('summary_phase_1') }} s USING (track_uid)
    INNER JOIN unique_tracks u USING (track_uid)