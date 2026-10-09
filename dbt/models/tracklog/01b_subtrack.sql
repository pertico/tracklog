-- 02_subtrack.sql

-- Detectar qué tracks están totalmente contenidos dentro de un track de mayor duración
with summary as (
    SELECT 
        track_uid,
        min(time) AS start_time, 
        max(time) AS end_time, 
        count(1) AS points
    FROM {{ ref('01_clean') }}
    GROUP BY track_uid
),
subtrack_matches as (
    select distinct
        child.track_uid as subtrack_uid,
        parent.track_uid as parent_track_uid
    from summary as child
    inner join summary as parent
        on child.track_uid != parent.track_uid
       and child.start_time >= parent.start_time
       and child.end_time <= parent.end_time
       and (
           -- Mayor duración
           (parent.end_time - parent.start_time) > (child.end_time - child.start_time)
           or (
               -- Igual duración pero más puntos
               (parent.end_time - parent.start_time) = (child.end_time - child.start_time)
               and parent.points > child.points
           )
           -- or (
             -- Empate total: desempate por hash
           -- (parent.end_time - parent.start_time) = (child.end_time - child.start_time)
           --   and parent.points = child.points
           --   and parent.track_uid > child.track_uid
           -- )
        )        
), subtracks as (
    select
        distinct m.subtrack_uid as track_uid
    from summary as s
    left join subtrack_matches as m
        on s.track_uid = m.subtrack_uid
    where m.subtrack_uid is not null
)
select * from {{ ref('01_clean')}}
where track_uid not in (select distinct track_uid from subtracks)