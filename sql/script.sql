
create database scorpion_ecomerse_db;
use scorpion_ecomerse_db;

create schema manager_toolset;

create stage manager_toolset.stage_order;

list @manager_toolset.stage_order;

create or replace file format manager_toolset.comma_delimited_csv_file_format 
    type = 'csv' field_delimiter = ',' field_optionally_enclosed_by = '"' skip_header = 1;

select $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12
from @manager_toolset.stage_order/ecommerce_orders.csv
(file_format => 'manager_toolset.comma_delimited_csv_file_format');

select $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12
from @manager_toolset.stage_order/ecommerce_orders.csv
limit 1;


create schema init_data;

create or replace table init_data."order" (
    order_id string primary key,
    customer_id string,
    customer_name string,
    order_date string,
    product string,
    quantity number(4,0),
    price number(10, 2),
    discount number(3, 2),
    total_amount number(10, 2),
    payment_method string,
    shipping_address string,
    status string
);

copy into init_data."order"
from @manager_toolset.stage_order/ecommerce_orders.csv
file_format = manager_toolset.comma_delimited_csv_file_format;

select * from init_data."order";

---------------------------------------------------------------------------------------------------------------

create schema data_review;


create or replace table data_review.td_for_review as
select * from init_data."order"
where shipping_address is null and upper(status) = 'DELIVERED';

select * from data_review.td_for_review;


create or replace table data_review.td_suspisios_records as 
select * from init_data."order" 
where customer_id is null;

select * from data_review.td_suspisios_records;


create or replace table data_review.td_invalid_date_format as 
select * from init_data."order" 
where try_to_date(order_date) is null;

select * from data_review.td_invalid_date_format;


create or replace table data_review.td_invalid_qty_price as
select * from init_data."order" 
where (quantity is null or quantity <= 0) or (price is null or price <= 0);

select * from data_review.td_invalid_qty_price;

---------------------------------------------------------------------------------------------------------------

create schema curated;

create or replace table curated.td_clean_records as 
with exclude_order as (
    select order_id from data_review.td_suspisios_records
    union 
    select order_id from data_review.td_invalid_date_format
    union 
    select order_id from data_review.td_invalid_qty_price
),
clean_order as (
    select distinct 
           o.order_id,
           customer_id, 
           customer_name,
           date(order_date) as order_date,
           product,
           quantity,
           price,
           case when discount < 0 then 0 when discount > 0.5 then 0.5 else discount end as discount,
           total_amount,
           coalesce(payment_method, 'Unknown') as payment_method,
           shipping_address,
           case when shipping_address is null and upper(status) = 'DELIVERED' then 'Pending' else status end as status
    from init_data."order" o
    left join exclude_order eo on o.order_id = eo.order_id
    where eo.order_id is null
)
select order_id,
       customer_id, 
       customer_name,
       order_date,
       product,
       quantity,
       price,
       discount,
       cast((price * quantity) * (1 - discount) as number(10, 2)) as total_amount,
       payment_method,
       shipping_address,
       status
from clean_order;

select * from curated.td_clean_records;

