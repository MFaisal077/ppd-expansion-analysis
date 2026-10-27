drop table if exists mart.metric_growth;



create table mart.metric_growth as 
with medians as (
select borough_name,borough_code,is_ranked,max(median_price) filter (where sale_year = 2020) as median_2020,
max(median_price) filter (where sale_year = 2025) as median_2025 from mart.borough_year group by borough_name,borough_code,is_ranked
)
Select 
borough_code,borough_name,is_ranked,median_2020,median_2025,round((power((median_2025/median_2020),0.2)-1)*100,2) as growth_pct
from medians 


