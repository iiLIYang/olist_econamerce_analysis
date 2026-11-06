-- ===================================================
-- 03_economic_trends.sql - 了解总体经济趋势
-- 目的:分析月度GMV,订单量,客单价,并计算环比增速和累计值.
-- ===================================================

use olist;

# 第一部分:大盘核心指标趋势(GMV，订单量，客单价)
with monthly_base as (      -- 利用CTE临时表,先把每个月的基础数据算出来
    select
        date_format(order_purchase_timestamp, '%Y-%m') as month,                 # 截取'年-月'作为时间维度
        count(distinct order_id) as order_count,                                 # 每月有效订单量
        round(sum(ifnull(payment_total,0)),2) as gmv,                            # 每月真实GMV(ifnull 把null值转成0,防止计算错误)
        round(sum(ifnull(payment_total,0))/count(distinct order_id),2) as aov    # 客单价 = 总钱数 / 总单数
    from v_order_base
    -- 剔除无效订单,避开2016年平台刚起步和18年年底原始数据截断的影响
    where is_valid_order = 1
      and order_purchase_timestamp >= '2017-01-01'
      and order_purchase_timestamp <  '2018-09-01'
    group by month
)
select
    month,
    order_count,
    round(gmv,2) as gmv,
    round(aov,2) as aov,
    # 窗口函数LAG:gmv的环比增长率（本月 vs 上月）（%）
    round(100*(gmv-LAG(gmv) over (order by month))
              /LAG(gmv) over (order by month),2) as gmv_mom_pct,
    # 窗口函数SUM...ROWS BETWEEN:累计gmv（从第一月到当前月）
    round(sum(gmv) over (order by month
                          rows between unbounded preceding and current row),2) as running_gmv,
    # 窗口函数LAG:订单量的环比增长率（%）
    round(100*(order_count - lag(order_count) over (order by month))
       /lag(order_count) over (order by month),2) as order_count_mom_pct,
    # 窗口函数LAG:客单价的环比增长率（%）
    round(100*(aov - lag(aov) over (order by month))
              / lag(aov) over (order by month),2) as aov_mom_pct
from monthly_base
order by month;

# 订单增长质量
-- 如果取消率和履约率表现不好,那GMV的上涨也不是不健康的
select
    date_format(order_purchase_timestamp,'%Y-%m') as month,
    count(distinct order_id) as total,                       # 总订单数
    sum(order_status = 'delivered') as delivered_cnt,        # 成功送达的订单数
    sum(order_status = 'canceled') as canceled_cnt,          # 主动取消的订单数
    sum(order_status = 'unavailable') as unavailable_cnt,    # 因缺货或不可用而失败的订单数
    round(100*sum(order_status = 'canceled')/count(distinct order_id),2) as cancel_rate_pct,   # 取消率（%）
    round(100*sum(order_status = 'delivered')/count(distinct order_id),2) as fulfillment_rate_pct   #履约率（%）
from orders
where order_purchase_timestamp >= '2017-01-01'
  and order_purchase_timestamp <  '2018-09-01'
group by month
order by month