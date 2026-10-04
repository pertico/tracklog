{{ config (
    post_hook=["
        DELETE FROM {{ ref('clean')}}
        WHERE track_uid in ( 
            SELECT track_uid FROM {{ this }} WHERE is_subtrack
        )
    "]
)

}}
-- Detectar qué tracks están totalmente contenidos dentro de un track de mayor duración
with flag as (
    select 1 from {{ ref('clean')}} limit 1
),
summary_2 AS (
	select *, end_time - start_time as duration
	from summary
),
subtrack_matches as (
    select distinct
        child.track_uid as subtrack_uid,
        parent.track_uid as parent_track_uid
    from summary_2 as child
    inner join summary_2 as parent
        on child.start_time >= parent.start_time
       and child.end_time <= parent.end_time
       and child.track_uid != parent.track_uid
       and parent.duration > child.duration
)
select
    s.*,
    case 
        when m.subtrack_uid is not null then true 
        else false 
    end as is_subtrack,
    m.parent_track_uid
from summary as s
left join subtrack_matches as m
    on s.track_uid = m.subtrack_uid