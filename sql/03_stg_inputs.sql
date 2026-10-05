-- 03_stg_inputs.sql
-- Staging for the borough list, earnings and rents. One row per London area (33).

-- 2a. Borough master list -> stg.borough

drop table if exists stg.borough;

create table stg.borough as
select
    lad25cd                     as borough_code,
    lad25nm                     as borough_name,
    lad25cd <> 'E09000001'      as is_ranked      -- City of London: shown, not ranked
from raw.lad_names
where lad25cd like 'E09%';



-- 2b. Earnings -> stg.earnings
-- ASHE 2025 provisional, residence-based, full-time median gross annual pay (Table 8.7a),
-- with its coefficient of variation (Table 8.7b). 'x' = suppressed by ONS, becomes NULL.
-- Quality bands follow ONS: CV <= 5% precise, <= 10% reasonably precise,
-- <= 20% acceptable, above that unreliable.
drop table if exists stg.earnings;

create table stg.earnings as
select
    est.code                            as borough_code,
    trim(est.description)               as borough_name,
    nullif(est.median, 'x')::int        as median_annual_pay,
    nullif(cv.median, 'x')::numeric     as cv_median,
    case
        when nullif(est.median, 'x') is null       then 'suppressed'
        when nullif(cv.median, 'x')::numeric <= 5  then 'precise'
        when nullif(cv.median, 'x')::numeric <= 10 then 'reasonably precise'
        when nullif(cv.median, 'x')::numeric <= 20 then 'acceptable'
        else 'unreliable'
    end                                 as quality,
    est.source_file
from raw.ashe_table8 est
left join raw.ashe_table8 cv
       on cv.code = est.code
      and cv.sheet = est.sheet
      and cv.source_file like '%Table 8.7b%'
where est.source_file like '%Table 8.7a%'
  and est.sheet = 'Full-Time'
  and est.code like 'E09%';


-- 2c. Rents -> stg.rents
-- 2-bed median monthly rent per borough (decision D11), April 2025 to March 2026.
-- The rents file has names, not codes, so the code comes from stg.borough.
-- '..' and '-' = suppressed by ONS, become NULL.
drop table if exists stg.rents;

create table stg.rents as
select
    b.borough_code,
    r.borough                                           as borough_name,
    nullif(nullif(r.median, '..'), '-')::int            as median_monthly_rent,
    nullif(nullif(r.count_of_rents, '..'), '-')::int    as rent_count,
    r.source_file
from raw.rents_borough r
join stg.borough b on b.borough_name = r.borough
where r.bedroom_category = 'Two Bedrooms';
