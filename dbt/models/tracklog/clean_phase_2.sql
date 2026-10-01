WITH unique_tracks AS (
    SELECT 
        track_hash,
        min(track_uid) AS track_uid
    FROM {{ ref('summary') }}
    GROUP BY track_hash
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
    INNER JOIN {{ ref('summary') }} s USING (track_uid)
    INNER JOIN unique_tracks u USING (track_uid)