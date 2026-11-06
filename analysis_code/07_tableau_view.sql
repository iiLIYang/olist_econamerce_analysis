-- =================================================================================
-- 目的：创建两个视图，供 BI 工具（Tableau）直接读取并作图
-- v_category_item：订单商品级，用来做 Top5 月度趋势
-- v_category_pareto：品类级，用来做 Top15 和帕累托，排名和累计占比
-- v_freight_category：运费占比需要品类级聚合
-- ==================================================================================
USE olist;

-- 视图 1：v_category_item（商品级明细宽表）
-- 业务作用：把杂乱的订单、商品、翻译表拼在一起，保留到“订单商品行”的粒度
-- 为什么建这个视图：Tableau 画月度趋势图时，可以直接拖拽这个视图

CREATE OR REPLACE VIEW v_category_item AS
SELECT
    oi.order_id,                                                    # 订单ID
    oi.order_item_id,                                               # 订单项ID（一个订单可能有多个商品）
    oi.product_id,                                                  # 商品ID
    oi.seller_id,                                                   # 卖家ID
    oi.price,                                                       # 商品单价（算GMV的核心）
    oi.freight_value,                                               # 运费
    o.order_purchase_timestamp,                                     # 下单时间
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,      # 提取'年-月',方便按月分组
    IFNULL(t.product_category_name_english, 'unknown') AS category, # 翻译成英文品类名;如果翻译表里没有,统一归为'unknown'
    p.product_category_name                                         # 原始葡萄牙语品类名（留作备用）
FROM order_items oi
         JOIN orders o
              ON oi.order_id = o.order_id
         JOIN products p
              ON oi.product_id = p.product_id
         LEFT JOIN product_category_name_translation t
                   ON p.product_category_name = t.product_category_name
-- 只取有效订单，且限定时间窗口（避开2016年样本少和2018年数据缺失）
WHERE o.order_status NOT IN ('canceled', 'unavailable')
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01';

-- 视图 2：v_category_pareto（品类级帕累托视图）
-- 业务作用：直接算出各品类的销售额排名、占比、以及累计占比

CREATE OR REPLACE VIEW v_category_pareto AS
SELECT
    category,                         # 品类名
    sales,                            # 该品类总销售额
    orders,                           # 该品类总订单数
    rn,                               # 排名（第1名、第2名...）
    total_sales,                      # 全平台总销售额（所有品类加起来的）
    sales / total_sales AS share,     # 该品类销售额占全平台的比例（比如第一名占 10%）
-- (窗口函数)计算帕累托的“累计占比”
-- 逻辑：按销售额降序排列，把当前行和前面所有行的销售额加起来，除以总销售额
    SUM(sales) OVER (
        ORDER BY sales DESC, category
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / total_sales AS cumulative_share
FROM (
         -- (中间层)：给每个品类打排名，并算出总盘子
         SELECT
             category,
             sales,
             orders,
             -- 按销售额降序排名（如果销售额一样，按品类名字母排序，防止排名冲突）
             ROW_NUMBER() OVER (ORDER BY sales DESC, category) AS rn,
             -- 窗口函数不带 ORDER BY，代表算全表（所有品类）的总和
             SUM(sales) OVER () AS total_sales
         FROM (
                  -- (最内层)：基础聚合，算出每个品类的总销售额和总订单数
                  SELECT
                      IFNULL(t.product_category_name_english, 'unknown') AS category,
                      SUM(oi.price) AS sales,
                      COUNT(DISTINCT oi.order_id) AS orders
                  FROM order_items oi
                           JOIN orders o
                                ON oi.order_id = o.order_id
                           JOIN products p
                                ON oi.product_id = p.product_id
                           LEFT JOIN product_category_name_translation t
                                     ON p.product_category_name = t.product_category_name
                  -- 同样的时间窗口和有效状态过滤，保证口径一致
                  WHERE o.order_status NOT IN ('canceled', 'unavailable')
                    AND o.order_purchase_timestamp >= '2017-01-01'
                    AND o.order_purchase_timestamp <  '2018-09-01'
                  GROUP BY IFNULL(t.product_category_name_english, 'unknown')
              ) c
     ) r
ORDER BY rn;

-- 视图 3：v_freight_category（运费占比需要品类级聚合）
-- 找出哪类品类的物流成本吃掉了利润
CREATE OR REPLACE VIEW v_freight_category AS
SELECT
    category,
    orders,
    sales,
    freight,
    freight_ratio,
    -- 按运费占比从高到低排名
    ROW_NUMBER() OVER (ORDER BY freight_ratio DESC) AS freight_rank
FROM (
         SELECT
             IFNULL(t.product_category_name_english, 'unknown') AS category,
             COUNT(DISTINCT oi.order_id) AS orders,
             SUM(oi.price) AS sales,
             SUM(oi.freight_value) AS freight,
             SUM(oi.freight_value) / SUM(oi.price) AS freight_ratio
         FROM order_items oi
                  JOIN orders o
                       ON oi.order_id = o.order_id
                  JOIN products p
                       ON oi.product_id = p.product_id
                  LEFT JOIN product_category_name_translation t
                            ON p.product_category_name = t.product_category_name
         WHERE o.order_status NOT IN ('canceled', 'unavailable')
           AND o.order_purchase_timestamp >= '2017-01-01'
           AND o.order_purchase_timestamp <  '2018-09-01'
         GROUP BY IFNULL(t.product_category_name_english, 'unknown')
         HAVING COUNT(DISTINCT oi.order_id) > 50  # 过滤掉单量过少的品类
     ) x;

