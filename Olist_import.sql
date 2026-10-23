-- =====================================================================
-- Olist 数据导入
-- 作用：把 Olist 的 CSV 文件装进 Olist.sql 建好的表里。
--
-- 使用步骤：
--   1) 先运行 Olist.sql（建库、建表）
--   2) 再运行本文件（导入数据）
--
-- 注意：LOAD DATA LOCAL INFILE 需要 MySQL 允许本地文件导入。
--   - 命令行登录时加参数：mysql --local-infile=1 -u root -p
--   - 或在 MySQL 里执行一次：SET GLOBAL local_infile = 1;
-- =====================================================================

USE olist;
SET NAMES utf8mb4;

SEt GLOBAL local_infile = 1;

-- 如需重复导入，先清空旧数据（临时关掉外键检查，避免顺序报错）
SET FOREIGN_KEY_CHECKS = 0;
SET FOREIGN_KEY_CHECKS = 1;

-- 1. 客户  ← olist_customers_dataset.csv
LOAD DATA LOCAL INFILE 'C:/Users/iiLI/Desktop/Olist/olist_customers_dataset.csv'
INTO TABLE customers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state);

-- 2. 卖家  ← olist_sellers_dataset.csv
LOAD DATA LOCAL INFILE 'C:/Users/iiLI/Desktop/Olist/olist_sellers_dataset.csv'
INTO TABLE sellers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(seller_id, seller_zip_code_prefix, seller_city, seller_state);

-- 3. 商品  ← olist_products_dataset.csv
--    CSV 里空值会读成空字符串，用 NULLIF 把它变成真正的 NULL。
LOAD DATA LOCAL INFILE 'C:/Users/iiLI/Desktop/Olist/olist_products_dataset.csv'
INTO TABLE products
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@product_id, @product_category_name, @product_name_length, @product_description_length,
 @product_photos_qty, @product_weight_g, @product_length_cm, @product_height_cm, @product_width_cm)
SET product_id                 = @product_id,
    product_category_name      = NULLIF(@product_category_name, ''),
    product_name_length        = NULLIF(@product_name_length, ''),
    product_description_length = NULLIF(@product_description_length, ''),
    product_photos_qty         = NULLIF(@product_photos_qty, ''),
    product_weight_g           = NULLIF(@product_weight_g, ''),
    product_length_cm          = NULLIF(@product_length_cm, ''),
    product_height_cm          = NULLIF(@product_height_cm, ''),
    product_width_cm           = NULLIF(@product_width_cm, '');

-- 4. 商品类目翻译  ← product_category_name_translation.csv
LOAD DATA LOCAL INFILE 'C:/Users/iiLI/Desktop/Olist/product_category_name_translation.csv'
INTO TABLE product_category_name_translation
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_category_name, product_category_name_english);

-- 5. 订单  ← olist_orders_dataset.csv
--    时间列有空值，同样用 NULLIF 转成 NULL。
LOAD DATA LOCAL INFILE 'C:/Users/iiLI/Desktop/Olist/olist_orders_dataset.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@order_id, @customer_id, @order_status, @order_purchase_timestamp, @order_approved_at,
 @order_delivered_carrier_date, @order_delivered_customer_date, @order_estimated_delivery_date)
SET order_id                      = @order_id,
    customer_id                   = @customer_id,
    order_status                  = @order_status,
    order_purchase_timestamp      = NULLIF(@order_purchase_timestamp, ''),
    order_approved_at             = NULLIF(@order_approved_at, ''),
    order_delivered_carrier_date  = NULLIF(@order_delivered_carrier_date, ''),
    order_delivered_customer_date = NULLIF(@order_delivered_customer_date, ''),
    order_estimated_delivery_date = NULLIF(@order_estimated_delivery_date, '');

-- 6. 订单明细  ← olist_order_items_dataset.csv
LOAD DATA LOCAL INFILE 'C:/Users/iiLI/Desktop/Olist/olist_order_items_dataset.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@order_id, @order_item_id, @product_id, @seller_id, @shipping_limit_date, @price, @freight_value)
SET order_id            = @order_id,
    order_item_id       = @order_item_id,
    product_id          = @product_id,
    seller_id           = @seller_id,
    shipping_limit_date = NULLIF(@shipping_limit_date, ''),
    price               = @price,
    freight_value       = @freight_value;

-- 7. 订单支付  ← olist_order_payments_dataset.csv
LOAD DATA LOCAL INFILE 'C:/Users/iiLI/Desktop/Olist/olist_order_payments_dataset.csv'
INTO TABLE order_payments
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, payment_sequential, payment_type, payment_installments, payment_value);

-- 8. 订单评价  ← olist_order_reviews_dataset.csv
--    评论标题、内容、时间都可能为空，用 NULLIF 转成 NULL。
LOAD DATA LOCAL INFILE 'C:/Users/iiLI/Desktop/Olist/olist_order_reviews_dataset.csv'
INTO TABLE order_reviews
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@review_id, @order_id, @review_score, @review_comment_title, @review_comment_message,
 @review_creation_date, @review_answer_timestamp)
SET review_id               = @review_id,
    order_id                = @order_id,
    review_score            = @review_score,
    review_comment_title    = NULLIF(@review_comment_title, ''),
    review_comment_message  = NULLIF(@review_comment_message, ''),
    review_creation_date    = NULLIF(@review_creation_date, ''),
    review_answer_timestamp = NULLIF(@review_answer_timestamp, '');

-- 9. 地理位置  ← olist_geolocation_dataset.csv
LOAD DATA LOCAL INFILE 'C:/Users/iiLI/Desktop/Olist/olist_geolocation_dataset.csv'
INTO TABLE geolocation
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state);

