-- ===========================================================================
-- 01_data_quality.sql  olist数据质量检查
-- ===========================================================================

use olist;

-- 1.九张表的行数

select 'order' as tbl, count(*) as row_cnt from orders
union all select 'customers', count(*) from customers
union all select 'order_items', count(*) from order_items
union all select 'order_payments', count(*) from order_payments
union all select 'order_reviews', count(*) from order_reviews
union all select 'products', count(*) from products
union all select 'sellers', count(*) from sellers
union all select 'product_category_name_translation', count(*) from product_category_name_translation
union all select 'geolocation', count(*) from geolocation;

-- 2.关键列空值率（%）

select 'orders.order_approved_at' as tbl, ROUND(100*sum(order_approved_at is null)/count(*),2) as pct_null from orders
union all select 'orders.order_delivered_customer_date', round(100*sum(order_delivered_customer_date is null)/count(*),2) from orders
union all select 'reviews_review_comment_message', round(100*sum(order_reviews.review_comment_message is null)/count(*),2) from order_reviews;

-- 3.重复评价条数
select count(*) as order_with_mutiple_reviews
from (select order_id from order_reviews group by order_id having count(*) > 1) t;

-- 4.品类未知，无法翻译
select
    count(case when p.product_category_name is null then 1 end) as null_category_products,
    count(case when p.product_category_name is not null and t.product_category_name is not null then 1 end) as untranslation_products
from products p
left join product_category_name_translation t on p.product_category_name = t.product_category_name;

-- 5.时间逻辑错误的订单数, 批准晚于承运, 承运晚于签收, 购买晚于批准
select
    count(case when order_approved_at > order_delivered_carrier_date then 1 end) as approved_after_carried,
    count(case when order_delivered_carrier_date > order_delivered_customer_date then 1 end) as carried_after_deliverd,
    count(case when order_purchase_timestamp > order_approved_at then 1 end ) as purchase_after_approved
from orders;

-- 6.配送天数异常的订单数（负值或超过60天）
select
    count(case when datediff(orders.order_delivered_customer_date,orders.order_purchase_timestamp) < 0 then 1 end) as negative_delivery_days,
    count(case when datediff(orders.order_delivered_customer_date,orders.order_purchase_timestamp) > 60 then 1 end ) as over_60_delivery_days
from orders
where order_status = 'delivered' and order_delivered_customer_date is not null;

-- 7. 已取消订单中带有评价的数量
SELECT COUNT(*) AS canceled_with_review
FROM orders o
         JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'canceled';

-- 8. geolocation 原始行数 vs 去重后邮编数
SELECT COUNT(*) AS raw_rows, COUNT(DISTINCT geolocation_zip_code_prefix) AS unique_zips
FROM geolocation;