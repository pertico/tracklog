{{ config(
    pre_hook=["
        INSTALL spatial;
        LOAD spatial;
    "]
)}}

WITH delta AS (
    SELECT 
        *,    
        time - LAG(time) OVER (PARTITION BY track_uid ORDER BY time) AS time_delta,
        LAG(lat) OVER (PARTITION BY track_uid ORDER BY time) AS last_lat,
        LAG(lon) OVER (PARTITION BY track_uid ORDER BY time) AS last_lon,
        ST_Point(lat, lon) AS p1,
        ST_Point(last_lat, last_lon) AS p2,
        -- ST_SetCRS(ST_Point(lat, lon), 'EPSG:4326') AS p1,
        -- ST_SetCRS(ST_Point(last_lat, last_lon), 'EPSG:4326') AS p2,
        ST_Distance_Spheroid(p1, p2) AS distance_delta
FROM {{ ref('01_clean') }}
)
SELECT *
FROM delta
WHERE epoch(time_delta) > 0 OR time_delta IS NULL

