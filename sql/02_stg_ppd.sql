-- 02_stg_ppd.sql
-- Staging for Price Paid Data: typed columns, scope rules applied.
-- Every raw row ends up in exactly one of stg.ppd (kept) or stg.ppd_dropped (with a reason).
-- Price range kept: £10,000 up to, but not including, £10,000,000 (decisions D05 and D12).

-- Kept sales
drop table if exists stg.ppd;

create table stg.ppd as
select
    transaction_id,
    price::int                   as price,
    date_of_transfer::date       as date_of_transfer,
    nullif(postcode, '')         as postcode,
    property_type,
    ppd_category,
    record_status,
    source_file
from raw.ppd
where property_type <> 'O'
  and price::int >= 10000
  and price::int < 10000000
  and record_status <> 'D';

create index on stg.ppd (postcode);
create index on stg.ppd (transaction_id);

-- Dropped sales, one reason each (first rule failed, in this order)
drop table if exists stg.ppd_dropped;

create table stg.ppd_dropped as
select
    transaction_id,
    price,
    date_of_transfer,
    postcode,
    property_type,
    ppd_category,
    record_status,
    source_file,
    case
        when record_status = 'D'      then 'record_status_D'
        when property_type = 'O'      then 'property_type_O'
        when price::int < 10000       then 'price_below_10000'
        when price::int >= 10000000   then 'price_10m_or_more'
    end as reason
from raw.ppd
where record_status = 'D'
   or property_type = 'O'
   or price::int < 10000
   or price::int >= 10000000;


-- Checks. One run_id for the whole file.
drop table if exists stg_run;
create temp table stg_run as
select 'stg_' || to_char(clock_timestamp(), 'YYYYMMDD"T"HH24MISS') as run_id;

insert into qa.check_log (run_id, layer, check_name, subject, status, expected, observed, detail)

-- Row reconciliation: every raw row is either kept or dropped.
select run_id, 'stg', 'raw_rows_equal_kept_plus_dropped', 'stg.ppd',
       case when r.n = k.n + d.n then 'pass' else 'fail' end,
       r.n::text, (k.n + d.n)::text,
       k.n || ' kept + ' || d.n || ' dropped'
from stg_run,
     (select count(*) n from raw.ppd)         r,
     (select count(*) n from stg.ppd)         k,
     (select count(*) n from stg.ppd_dropped) d

union all

-- No transaction appears twice.
select run_id, 'stg', 'unique_transaction_id', 'stg.ppd',
       case when count(*) = count(distinct transaction_id) then 'pass' else 'fail' end,
       count(*)::text, count(distinct transaction_id)::text,
       'rows vs distinct transaction_id'
from stg.ppd, stg_run group by run_id

union all

-- Every dropped row has a reason.
select run_id, 'stg', 'every_drop_has_a_reason', 'stg.ppd_dropped',
       case when count(*) filter (where reason is null) = 0 then 'pass' else 'fail' end,
       '0', (count(*) filter (where reason is null))::text, 'dropped rows with no reason'
from stg.ppd_dropped, stg_run group by run_id

union all

-- Deleted records removed: a count to report. The yearly files hold none (decision D07).
select run_id, 'stg', 'deleted_records_removed', 'stg.ppd_dropped',
       'info', null,
       (select count(*) from stg.ppd_dropped where reason = 'record_status_D')::text,
       'rows with record_status D'
from stg_run

union all

-- Dropped rows by reason.
select run_id, 'stg', 'dropped_' || reason, 'stg.ppd_dropped',
       'info', null, count(*)::text, null
from stg.ppd_dropped, stg_run group by run_id, reason;

-- A failed check stops the build.
do $$
declare failed text;
begin
    select string_agg(check_name, ', ') into failed
    from qa.check_log
    where status = 'fail' and run_id = (select run_id from stg_run);
    if failed is not null then
        raise exception 'Staging checks failed: %', failed;
    end if;
end $$;
