-- ========================================================
-- 05_logistics_experience.sql 配送体验
-- 量化物流效率，评估延迟对客户的评价的影响
-- ========================================================

use olist;

-- 物流大盘(整体延迟率/平均天数/平均评分)
-- 确立平台整体物流水平

select
    count(*) as total_delivered_orders,                                      # 总送达订单数
    round(avg(delivery_days), 1) as avg_delivery_day,                        # 平均送达天数
    round(100* sum(delivery_status = 'late')/ count(*), 2) as late_rate_pct, # 整体迟到率
    round(avg(review_score), 2) as  avg_review_score                         # 整体平均评分
from olist.v_order_base
where order_status = 'delivered' and order_delivered_customer_date is not null
      and order_purchase_timestamp >= '2017-01-01'
      and order_purchase_timestamp <  '2018-09-01';

-- 延迟天数与评分关系
-- 将延迟分为'准时','迟1-3天','迟3-7天','迟7天以上'
-- 证明迟达是否为摧毁用户体验的主要因素

select
    -- 分桶逻辑: 按延迟严重程度划分4个等级
    case
        when delivery_status = 'on_time' then '1,准时/提前'
        when delivery_status = 'late' and
             datediff(order_delivered_customer_date,order_estimated_delivery_date) <= 3 then '2,晚1-3天'
        when delivery_status = 'late' and
             datediff(order_delivered_customer_date,order_estimated_delivery_date) <= 7 then '3,晚4-7天'
        else '4,晚7天以上'
    end as delay_bucket,
    count(*) as total_orders,                                               # 该类的总订单
    -- 用sum(count(*)) over() 计算全体总订单量作为分母
    round(100*count(*)/sum(count(*)) over(), 2) as pct_of_total,            # 各类订单占比
    round(avg(review_score), 2) as avg_review_score,                        # 各类用户平均评分
    round(100*sum(review_score <= 2)/count(*), 2) as bad_review_rate_pct    # 该类的差评率占比
from v_order_base
where order_status = 'delivered'
  and order_delivered_customer_date is not null
  and order_estimated_delivery_date is not null
  and order_purchase_timestamp >= '2017-01-01'
  and order_purchase_timestamp <  '2018-09-01'
group by delay_bucket
order by delay_bucket;

-- 拆分物流: 看物流慢是因为'卖家发货慢'还是'承运商送得慢'

select
    case
        when delivery_status = 'late' then '晚到订单'
        else '准时订单'
        end as status_group,
    count(*) as order_count,
    -- 卖家段(履约时长): 从平台审批 --> 卖家交给承运商
    round(avg(datediff(order_delivered_carrier_date, order_approved_at)), 1) as seller_leg_days,
    -- 承运端(配送时长): 从承运商接手 --> 实际送达客户
    round(avg(datediff(order_delivered_customer_date, order_delivered_carrier_date)), 1) as carrier_leg_days
from v_order_base
where order_status = 'delivered'
    and order_purchase_timestamp >= '2017-01-01'
    and order_purchase_timestamp <  '2018-09-01'
group by status_group;


-- 找空间因素,按客户所在州拆解延迟率,
-- 找出哪个州迟到率最高,哪个州送的最慢,定位重灾区

select
    customer_state,
    count(*)                                             as total_orders,      # 该州总订单
    round(avg(delivery_days), 1)                         as avg_delivery_days, # 该州平均送达天数
    round(100*sum(delivery_status = 'late')/count(*), 2) as late_rate_pct,     # 该州迟到率
    round(avg(review_score), 2)                          as avg_review_score   # 该州平均评分
from v_order_base
where order_status = 'delivered'
  and order_delivered_customer_date is not null
  and order_purchase_timestamp >= '2017-01-01'
  and order_purchase_timestamp <  '2018-09-01'
group by customer_state
having count(*) > 100   -- 排除样本量太少的州,避免受极端值影响
order by late_rate_pct desc
limit 10;


-- 找出高运费占比, 计算运费/商品价格的比例
-- 为调整运费策略提供依据
-- 只看有一定单量的品类

with cat_freight as (
    select
        ifnull(t.product_category_name_english,'unknown') as category,
        round(sum(oi.price), 2)                           as total_item_price,  # 总商品价格
        round(sum(oi.freight_value), 2)                   as total_freight,     # 总运费
        -- 运费占比 = 总运费 / 总商品价格 ,占比越高物流成本越高
        round(100*sum(oi.freight_value)/sum(oi.price), 2) as freight_ratio_pct, # 运费占比
        count(distinct oi.order_id)                       as count_orders       # 订单量
    from order_items oi
    join products pr on oi.product_id = pr.product_id
    join olist.orders o
         on oi.order_id = o.order_id
             and o.order_status not in ('canceled', 'unavailable')
    left join product_category_name_translation t
        on t.product_category_name = pr.product_category_name
    where o.order_purchase_timestamp >= '2017-01-01'
      and o.order_purchase_timestamp <  '2018-09-01'
    group by ifnull(t.product_category_name_english,'unknown')
)
select
    category,
    count_orders,       # 订单量
    total_item_price,   # 总销售额
    total_freight,      # 总运费
    freight_ratio_pct   # 运费占销售额的占比 (%)
from cat_freight
where count_orders > 50
order by  freight_ratio_pct desc
limit 15;

-- 查看各个商家送货的速度
select
    oi.seller_id,
    count(distinct oi.order_id) as total_orders,
    -- 计算该卖家所用订单的平均总物流天数(含 卖家发货 + 承运商配送)
    round(avg(datediff(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1) as avg_delivery_days
from order_items oi
         join orders o on oi.order_id = o.order_id
where o.order_status = 'delivered'
  and o.order_delivered_customer_date is not null
  and o.order_purchase_timestamp >= '2017-01-01'
  and o.order_purchase_timestamp <  '2018-09-01'
group by oi.seller_id
having total_orders > 30  # 是评估订单量大于30的卖家
order by avg_delivery_days desc;