-- dbt automáticamente materializará esto como una Vista o Tabla
{{ config(materialized='view') }}

SELECT
    source,
    track_name,
    track_type,
    track_fid,
    track_seg_id,
    track_seg_point_id,
    time::TIMESTAMP WITH TIME ZONE AS time,
    lat::DOUBLE AS lat,
    lon::DOUBLE AS lon,
    ele::DOUBLE AS ele,
    source_file,
    geometry
FROM 'data/tracklog.parquet'
WHERE time IS NOT NULL