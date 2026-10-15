drop table if exists mart.borough_year;

Create table mart.borough_year as 
Select borough_code, borough_name, is_ranked,
sale_year, count(*) as sales,count(*) filter (where property_type = 'F')   as flat_sales
, Case when count(*)>= 30 then (percentile_cont(0.5) within group (order by price))::numeric end as median_price,
case
    when count(*) filter (where property_type = 'F') >= 30
    then percentile_cont(0.5) within group (order by price) filter (where property_type = 'F')::numeric
end   as median_flat_price
from core.sales where ppd_category = 'A' group by borough_name,borough_code,is_ranked,sale_year