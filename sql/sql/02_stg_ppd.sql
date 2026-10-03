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