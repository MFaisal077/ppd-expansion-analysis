-- 02_stg_ppd.sql
-- Staging for Price Paid Data: typed columns, scope rules applied.
-- Every raw row ends up in exactly one of stg.ppd (kept) or stg.ppd_dropped (with a reason).

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
        when record_status = 'D'  then 'record_status_D'
        when property_type = 'O'  then 'property_type_O'
        when price::int < 10000   then 'price_below_10000'
    end as reason
from raw.ppd
where record_status = 'D'
   or property_type = 'O'
   or price::int < 10000;


--staging checks
insert into qa.check_log (run_id, layer, check_name, subject, status, expected, observed)
select
    'stg_' || to_char(now(), 'YYYYMMDD"T"HH24MISS'),
    'stg',
    'raw_rows_equal_kept_plus_dropped',
    'stg.ppd',
    case when r.n = k.n + d.n then 'pass' else 'fail' end,
    r.n::text,
    (k.n + d.n)::text
from (select count(*) n from raw.ppd)         r,
     (select count(*) n from stg.ppd)         k,
     (select count(*) n from stg.ppd_dropped) d;
