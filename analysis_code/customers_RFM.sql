USE olist;

DROP TABLE IF EXISTS tableau_customer_rfm;

CREATE TABLE tableau_customer_rfm AS
-- 1. 基础过滤: 只取有效送达订单,且限定时间窗口
WITH delivered AS (
    SELECT customer_unique_id, order_id, order_purchase_timestamp,
           payment_total, customer_state
    FROM v_order_base
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp <  '2018-09-01'
),
last_state AS (
    -- 2. 找每个客户最后一次下单所在的州,按时间倒序取第一
    SELECT customer_unique_id, customer_state
    FROM (
            SELECT customer_unique_id, customer_state,
                    ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                        ORDER BY order_purchase_timestamp DESC, order_id DESC
                        ) AS rn
            FROM delivered
        ) x
    WHERE rn = 1
),
rfm_base AS (
    -- 3. 计算R,F,M基础值
    SELECT
        customer_unique_id,
        DATEDIFF('2018-09-01', MAX(order_purchase_timestamp)) AS recency_days,
        COUNT(DISTINCT order_id) AS frequency,
        SUM(payment_total) AS monetary,
        MIN(order_purchase_timestamp) AS first_order_at,
        MAX(order_purchase_timestamp) AS last_order_at
    FROM delivered
    GROUP BY customer_unique_id
),
rfm_score AS (
    -- 4. 给R,F,M打分
    SELECT
        *,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        CASE
            WHEN frequency = 1 THEN 1
            WHEN frequency BETWEEN 2 AND 3 THEN 3
            ELSE 5
            END AS f_score,
        NTILE(5) OVER (ORDER BY monetary) AS m_score
    FROM rfm_base
)
SELECT
    r.customer_unique_id,
    s.customer_state,
    r.first_order_at,
    r.last_order_at,
    r.recency_days,
    r.frequency,
    r.monetary,
    r.r_score,
    r.f_score,
    r.m_score,
    CONCAT(r.r_score, r.f_score, r.m_score) AS rfm_code,
    CASE WHEN r.frequency >= 2 THEN '复购客户' ELSE '一次性客户' END AS customer_type,
    CASE
        WHEN r.r_score >= 4 AND r.f_score >= 3 AND r.m_score >= 4 THEN '1.核心高价值用户'
        WHEN r.r_score <= 2 AND r.m_score >= 4 THEN '2.高价值流失预警'
        WHEN r.r_score >= 4 AND r.f_score = 1 THEN '3.新客/潜力客户'
        WHEN r.r_score <= 2 AND r.f_score = 1 THEN '4.一般流失客户'
        ELSE '5.普通客户'
        END AS customer_segment
FROM rfm_score r
         JOIN last_state s
              ON r.customer_unique_id = s.customer_unique_id;
-- 加上索引,减少查找等待时间
ALTER TABLE tableau_customer_rfm
    ADD PRIMARY KEY (customer_unique_id),
    ADD INDEX idx_state (customer_state),
    ADD INDEX idx_segment (customer_segment),
    ADD INDEX idx_type (customer_type);
-- 数据验证
SELECT COUNT(*) AS core_high_value
FROM tableau_customer_rfm
WHERE customer_segment = '1.核心高价值用户';