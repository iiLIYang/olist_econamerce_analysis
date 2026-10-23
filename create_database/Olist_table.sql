-- =====================================================================
-- Olist 巴西电商数据集 —— MySQL 建表
-- 数据来源：https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
--
-- 每个 CSV 文件对应一张表，表名与文件名一一对应（见下方注释）。
--
-- 表与表的关系：
--
--   customers (客户)
--       └─< orders (订单)              orders.customer_id 引用 customers.customer_id
--              ├─< order_items (订单明细) ──> products (商品)
--              │                          └──> sellers  (卖家)
--              ├─< order_payments (支付)
--              └─< order_reviews  (评价)
--
--   products.product_category_name  ──> product_category_name_translation (类目翻译)
--
--   geolocation (地理位置)：独立表，用邮编与 customers / sellers 关联，不设外键。
-- =====================================================================

CREATE DATABASE IF NOT EXISTS olist;
USE olist;

-- 1. 客户表  ← olist_customers_dataset.csv
CREATE TABLE customers (
    customer_id              CHAR(32),      -- 主键：订单级客户编号
    customer_unique_id       CHAR(32),      -- 客户真实唯一编号（同一人多次下单不变）
    customer_zip_code_prefix VARCHAR(5),    -- 邮编前 5 位
    customer_city            VARCHAR(50),   -- 城市
    customer_state           CHAR(2),       -- 州
    PRIMARY KEY (customer_id)
);

-- 2. 卖家表  ← olist_sellers_dataset.csv
CREATE TABLE sellers (
    seller_id              CHAR(32),        -- 主键：卖家编号
    seller_zip_code_prefix VARCHAR(5),      -- 邮编前 5 位
    seller_city            VARCHAR(50),     -- 城市
    seller_state           CHAR(2),         -- 州
    PRIMARY KEY (seller_id)
);

-- 3. 商品表  ← olist_products_dataset.csv
CREATE TABLE products (
    product_id                 CHAR(32),     -- 主键：商品编号
    product_category_name      VARCHAR(50),  -- 商品类目（葡语），可关联翻译表
    product_name_length        INT,          -- 名称字符数
    product_description_length INT,          -- 描述字符数
    product_photos_qty         INT,          -- 图片数量
    product_weight_g           INT,          -- 重量（克）
    product_length_cm          INT,          -- 长（厘米）
    product_height_cm          INT,          -- 高（厘米）
    product_width_cm           INT,          -- 宽（厘米）
    PRIMARY KEY (product_id)
);

-- 4. 商品类目翻译表  ← product_category_name_translation.csv
--    把葡语类目翻译成英语。
CREATE TABLE product_category_name_translation (
    product_category_name         VARCHAR(50),  -- 主键，对应 products.product_category_name
    product_category_name_english VARCHAR(50),  -- 对应英文类目名
    PRIMARY KEY (product_category_name)
);

-- 5. 订单表  ← olist_orders_dataset.csv
--    一条记录 = 一个订单。
CREATE TABLE orders (
    order_id                      CHAR(32),    -- 主键：订单编号
    customer_id                   CHAR(32),    -- 外键：下单的客户
    order_status                  VARCHAR(20), -- 订单状态（delivered/shipped/canceled 等）
    order_purchase_timestamp      DATETIME,    -- 下单时间
    order_approved_at             DATETIME,    -- 审核时间
    order_delivered_carrier_date  DATETIME,    -- 交给物流时间
    order_delivered_customer_date DATETIME,    -- 送达客户时间
    order_estimated_delivery_date DATETIME,    -- 预计送达时间
    PRIMARY KEY (order_id),
    FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
);

-- 6. 订单明细表  ← olist_order_items_dataset.csv
CREATE TABLE order_items (
    order_id            CHAR(32),        -- 外键：属于哪个订单
    order_item_id       INT,             -- 订单内第几件商品
    product_id          CHAR(32),        -- 外键：商品
    seller_id           CHAR(32),        -- 外键：卖家
    shipping_limit_date DATETIME,        -- 发货截止时间
    price               DECIMAL(10, 2),  -- 商品单价
    freight_value       DECIMAL(10, 2),  -- 运费
    PRIMARY KEY (order_id, order_item_id),
    FOREIGN KEY (order_id)   REFERENCES orders (order_id),
    FOREIGN KEY (product_id) REFERENCES products (product_id),
    FOREIGN KEY (seller_id)  REFERENCES sellers (seller_id)
);

-- 7. 订单支付表  ← olist_order_payments_dataset.csv
CREATE TABLE order_payments (
    order_id             CHAR(32),        -- 外键：属于哪个订单
    payment_sequential   INT,             -- 第几笔支付
    payment_type         VARCHAR(20),     -- 支付方式
    payment_installments INT,             -- 分期数
    payment_value        DECIMAL(10, 2),  -- 支付金额
    PRIMARY KEY (order_id, payment_sequential),
    FOREIGN KEY (order_id) REFERENCES orders (order_id)
);

-- 8. 订单评价表  ← olist_order_reviews_dataset.csv
CREATE TABLE order_reviews (
    review_id               CHAR(32),     -- 评价编号
    order_id                CHAR(32),     -- 外键：属于哪个订单
    review_score            TINYINT,      -- 评分 1~5
    review_comment_title    VARCHAR(100), -- 评论标题
    review_comment_message  TEXT,         -- 评论内容
    review_creation_date    DATETIME,     -- 评论创建时间
    review_answer_timestamp DATETIME,     -- 评论回复时间
    PRIMARY KEY (review_id, order_id),
    FOREIGN KEY (order_id) REFERENCES orders (order_id)
);

-- 9. 地理位置表  ← olist_geolocation_dataset.csv
CREATE TABLE geolocation (
    geolocation_zip_code_prefix VARCHAR(5),      -- 邮编前 5 位
    geolocation_lat             DECIMAL(11, 8),  -- 纬度
    geolocation_lng             DECIMAL(11, 8),  -- 经度
    geolocation_city            VARCHAR(50),     -- 城市
    geolocation_state           CHAR(2)          -- 州
);

-- =====================================================================
-- 数据导入顺序见 Olist_import.sql。
-- =====================================================================
