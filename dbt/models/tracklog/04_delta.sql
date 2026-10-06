{{ config(
    pre_hook=["
        INSTALL spatial;
        LOAD spatial;
    "],
    post_hook=["
        CREATE OR REPLACE VIEW summary AS
            SELECT 
                track_uid,
                min(time) AS start_time, 
                max(time) AS end_time, 
                count(*) AS points,
                max(time)-min(time) AS duration,
                SUM(distance_delta)/1000 AS distance_km,
                3.6 * SUM(distance_delta)/(epoch(max(time))-epoch(min(time))) AS avg_speed_kmh
            FROM {{ this }}
            GROUP BY track_uid
        "]
)}}

WITH new_deltas AS (
    SELECT 
        * EXCLUDE (time_delta, distance_delta),    
        time - LAG(time) OVER (PARTITION BY track_uid ORDER BY time) AS time_delta,
        LAG(lat) OVER (PARTITION BY track_uid ORDER BY time) AS last_lat,
        LAG(lon) OVER (PARTITION BY track_uid ORDER BY time) AS last_lon,
        ST_Point(lat, lon) AS p1,
        ST_Point(last_lat, last_lon) AS p2,
        -- ST_SetCRS(ST_Point(lat, lon), 'EPSG:4326') AS p1,
        -- ST_SetCRS(ST_Point(last_lat, last_lon), 'EPSG:4326') AS p2,
        ST_Distance_Spheroid(p1, p2) AS distance_delta
FROM {{ ref('03_split') }}
)
SELECT 
  track_uid, 
  content_digest, 
  summary_digest, 
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
  time_delta,
  distance_delta
FROM new_deltas
WHERE epoch(time_delta) > 0 OR time_delta IS NULL

