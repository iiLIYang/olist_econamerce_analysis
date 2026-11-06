-- ===========================================================================
-- 06_customer_value.sql 客户价值与留存
-- 测算复购率,完成客户分层(RFM), 并验证体验对留存的影响
-- 这里将本数据分析窗口设定为 2017-01-01 至 2018-08-31
-- 减少2016年启动期的极端波动，也能避免2018年末数据不完整带来的统计误差
-- 首单准时 vs 延迟 → 复购率,是相关性观察性结论
-- ============================================================================

use olist;

-- 复购率与购买频次分布(看平台粘性)
-- 不看金额就看购买次数,看每个人买了几次

with customer_orders as (
    select
        customer_unique_id,                     # 客户唯一ID
        count(distinct order_id) as order_cnt   # 统计每一个客户下单次数
    from v_order_base
    where order_status = 'delivered'
      and order_purchase_timestamp >= '2017-01-01'
      and order_purchase_timestamp < '2018-09-01'
    group by customer_unique_id
)
select
    order_cnt as buy_times,                      # 购买次数
    count(*) as customer_count,                  # 该购买次数含多少人
    -- 计算该频次的用户占总用户的百分比
    round(100*count(*)/sum(count(*)) over(), 2) as repeat_rate_pct  # 购买人数占总人数的比例(%)
from customer_orders
group by order_cnt
order by order_cnt;

-- RFM客户分层(找出高净值人群)
-- 用R(最近一次购买),F(购买频次),M(消费金额)三个维度打分(1-5)
-- 用有限的营销创造更高的价值

with rfm_base as (
    select
        customer_unique_id,
        -- R：计算距离截止日2018-09-01有多少天没有够买
        datediff('2018-09-01',max(order_purchase_timestamp)) as recency_days,
        -- F：购买的总单数
        count(distinct order_id)                             as frequency,
        -- M：总消费金额
        sum(payment_total)                                   as monetary
    from v_order_base
    where order_status = 'delivered'
      and order_purchase_timestamp >= '2017-01-01'
      and order_purchase_timestamp < '2018-09-01'
    group by customer_unique_id
),
rfm_score as (
    select
        customer_unique_id,
        recency_days,
        frequency,
        round(monetary, 2) as monetary,
        -- R打分逻辑：用ntile(5)将用户按R值均分5组,天数越小打分越高
        ntile (5) over (order by recency_days desc) as r_score,
        -- F打分逻辑：分按业务实际频次定档（Olist 复购极少，强行五等分会全部挤在 1 分）
        -- 1次为1分,2-3次为3分,4-5次为5分
        case
        when frequency = 1 then 1
        when frequency between 2 and 3 then 3
        else 5
        end as f_score,
        -- M打分逻辑：按消费金额ntile(5)均分5组,金额越大打分越高
        ntile (5) over (order by monetary) as m_score
    from rfm_base
)
-- 根据R,F,M的分数,组合出不同的业务标签
select
    case
        when r_score >= 4 and f_score >= 3 and m_score >= 4 then '1.核心高价值用户'
        when r_score <= 2 and m_score >= 4 then '2.高价值流失预警'
        when r_score >= 4 and f_score = 1 then '3.新客/潜力客户'
        when r_score <= 2 and f_score = 1 then '4. 一般流失客户'
        else '5. 普通客户'
    end as customer_segment,
    count(*) as customer_cnt,                                       # 各类人群数量
    round(100*count(*)/sum(count(*)) over(), 2) as pct_of_total,    # 各类人群占比
    round(avg(monetary), 2) as avg_monetary                         # 该人群的平均消费力
    from rfm_score
group by customer_segment
order by customer_segment;

-- 客户地域分布(找核心地区),按州看用户数与贡献的GMV
-- 为地域营销提供依据,此为已送达口径，区别于 03 的有效订单 GMV

select
    customer_state,
    count(distinct customer_unique_id) as total_customers,  # 该州总客户数
    round(sum(payment_total), 2) as delivered_gmv,          # 该州总GMV
    -- 人均贡献GMV
    round(sum(payment_total)/count(distinct customer_unique_id), 2) as gmv_per_customer
from v_order_base
where order_status = 'delivered'
  and order_purchase_timestamp >= '2017-01-01'
  and order_purchase_timestamp < '2018-09-01'
group by customer_state
order by total_customers desc;

-- 迟达对购的影响
-- 找到每位客户的首单,观察准时组的复购率与延迟组的复购率
-- 证明物流体验会影响客户体验导致客户流失

with first_order as (
    -- 1. 找出每个客户的首单, 用row_number()按购买时间正序排列,取rn = 1
    select
        customer_unique_id,
        order_id,
        delivery_status,
        row_number() over (partition by customer_unique_id order by order_purchase_timestamp asc) as rn
    from v_order_base
    where order_status = 'delivered'
      and order_purchase_timestamp >= '2017-01-01'
      and order_purchase_timestamp < '2018-09-01'
),
customer_total_orders as (
    -- 2. 算出每个客户在窗口期内的总单数(判断是否复购)
    select
        customer_unique_id,
        count(distinct order_id) as total_orders
    from v_order_base
    where order_status = 'delivered'
      and order_purchase_timestamp >= '2017-01-01'
      and order_purchase_timestamp < '2018-09-01'
    group by customer_unique_id
)
select
    f.delivery_status as first_order_status,                                 # 首单物流状态(late / on_time)
    count(distinct f.customer_unique_id) as total_customers,                 # 该组总人数
    sum(case when c.total_orders > 1 then 1 else 0 end) as repeat_customers, # 该组复购人数
    -- 计算该组复购率
    round(100*sum(case when c.total_orders > 1 then 1 else 0 end)/ count(distinct f.customer_unique_id), 2) as repeat_rate_pct
from first_order f
join customer_total_orders c on f.customer_unique_id = c.customer_unique_id
where f.rn = 1
group by f.delivery_status;

