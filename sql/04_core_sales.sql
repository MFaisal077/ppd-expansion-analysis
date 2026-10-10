-- 04_core_sales.sql
-- Core: one row per London sale, with its borough.
-- Borough comes from the sale's postcode in the ONS Postcode Directory (decision D01).
-- Category B sales are kept, flagged by ppd_category; headline metrics filter to A in the marts.

-- London sales. The join to stg.borough is the London filter: a sale whose
-- postcode is outside the 33 London areas, or has no postcode, does not match.
drop table if exists core.sales;

create table core.sales as
select
    s.transaction_id,
    s.price,
    s.date_of_transfer,
    extract(year from s.date_of_transfer)::int   as sale_year,
    s.property_type,
    s.ppd_category,
    s.postcode,
    b.borough_code,
    b.borough_name,
    b.is_ranked
from stg.ppd s
join raw.onspd   o on o.pcds = s.postcode
join stg.borough b on b.borough_code = o.lad26cd;

-- A primary key makes duplicates impossible: the build stops here if one appears.
alter table core.sales add primary key (transaction_id);
create index on core.sales (borough_code, sale_year);

-- Sales that Price Paid Data places in Greater London (its county field) but
-- that did not get a London borough from their postcode. This is the list the
-- brief asks for, and the "missed" side of the postcode match rate.
drop table if exists core.sales_unmatched;

create table core.sales_unmatched as
select
    s.transaction_id,
    s.postcode,
    r.district                  as ppd_district,
    s.date_of_transfer,
    s.ppd_category,
    case
        when s.postcode is null then 'no_postcode'
        when o.pcds is null     then 'postcode_not_in_directory'
        else                         'postcode_outside_london'
    end                         as reason
from raw.ppd r
join stg.ppd s        on s.transaction_id = r.transaction_id
left join raw.onspd o on o.pcds = s.postcode
where r.county = 'GREATER LONDON'
  and (o.lad26cd is null or o.lad26cd not like 'E09%');


-- Checks. One run_id for the whole file.
drop table if exists core_run;
create temp table core_run as
select 'core_' || to_char(clock_timestamp(), 'YYYYMMDD"T"HH24MISS') as run_id;

insert into qa.check_log (run_id, layer, check_name, subject, status, expected, observed, detail)

-- No transaction appears twice.
select run_id, 'core', 'unique_transaction_id', 'core.sales',
       case when count(*) = count(distinct transaction_id) then 'pass' else 'fail' end,
       count(*)::text, count(distinct transaction_id)::text,
       'rows vs distinct transaction_id'
from core.sales, core_run group by run_id

union all

-- At least 99% of sales that Price Paid Data places in Greater London get a borough.
select run_id, 'core', 'postcode_match_rate', 'core.sales',
       case when m.matched::numeric / (m.matched + u.n) >= 0.99 then 'pass' else 'fail' end,
       '>= 99%',
       round(100.0 * m.matched / (m.matched + u.n), 2) || '%',
       m.matched || ' matched, ' || u.n || ' unmatched (see core.sales_unmatched)'
from core_run,
     (select count(*) as n from core.sales_unmatched) u,
     (select count(*) as matched
      from raw.ppd r join core.sales c on c.transaction_id = r.transaction_id
      where r.county = 'GREATER LONDON') m

union all

-- All 33 London areas have sales.
select run_id, 'core', 'all_boroughs_present', 'core.sales',
       case when count(distinct borough_code) = 33 then 'pass' else 'fail' end,
       '33', count(distinct borough_code)::text, null
from core.sales, core_run group by run_id

union all

-- Every sale is inside the project window.
select run_id, 'core', 'sale_year_in_window', 'core.sales',
       case when min(sale_year) >= 2015 and max(sale_year) <= 2025 then 'pass' else 'fail' end,
       '2015 to 2025', min(sale_year) || ' to ' || max(sale_year), null
from core.sales, core_run group by run_id

union all

-- Borough-years with fewer than 30 category A sales get no median in the marts.
select run_id, 'core', 'borough_years_below_30_sales', 'core.sales',
       'info', '0',
       (select count(*) from (select 1 from core.sales where ppd_category = 'A'
                              group by borough_code, sale_year having count(*) < 30) small)::text,
       'category A, by borough and year'
from core_run

union all

-- Unmatched sales by reason.
select run_id, 'core', 'unmatched_' || reason, 'core.sales_unmatched',
       'info', null, count(*)::text, null
from core.sales_unmatched, core_run group by run_id, reason;

-- A failed check stops the build.
do $$
declare failed text;
begin
    select string_agg(check_name, ', ') into failed
    from qa.check_log
    where status = 'fail' and run_id = (select run_id from core_run);
    if failed is not null then
        raise exception 'Core checks failed: %', failed;
    end if;
end $$;
