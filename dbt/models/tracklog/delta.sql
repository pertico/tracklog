{{ config(
    pre_hook=["
        INSTALL spatial;
        LOAD spatial;
    "],
    post_hook=["
        CREATE OR REPLACE VIEW summary AS (
        SELECT 
            track_uid,
            content_digest,
            summary_digest,
            min(time) AS start_time, 
            max(time) AS end_time, 
            count(1) AS points,
            mean(time_delta) AS mean_time,
            mean(distance_delta) AS mean_distance,
            mean(distance_delta/epoch(time_delta)) AS mean_speed,
            median(time_delta) AS median_time,
            median(distance_delta) AS median_distance,
            median(distance_delta/epoch(time_delta)) AS median_speed
            -- stddev(epoch(time_delta)) FILTER(WHERE time_delta IS NOT NULL) AS sd_time ,
            -- stddev(distance_delta) FILTER(WHERE distance_delta IS NOT NULL) AS sd_distance,
            -- stddev(distance_delta/epoch(time_delta)) AS sd_speed
        FROM delta
        GROUP BY track_uid, content_digest, summary_digest            
        )
    "]
)

}}

WITH calculated_data AS (
    SELECT 
        *,    
        time - LAG(time) OVER (PARTITION BY track_uid ORDER BY time) AS time_delta,
        LAG(lat) OVER (PARTITION BY track_uid ORDER BY time) AS last_lat,
        LAG(lon) OVER (PARTITION BY track_uid ORDER BY time) AS last_lon,
        ST_SetCRS(ST_Point(lat, lon), 'EPSG:4326') AS p1,
        ST_SetCRS(ST_Point(last_lat, last_lon), 'EPSG:4326') AS p2,
        ST_Distance(p1, p2) AS distance_delta
FROM {{ ref('clean') }}
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
FROM calculated_data
