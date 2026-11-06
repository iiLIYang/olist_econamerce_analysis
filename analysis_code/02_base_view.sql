-- =======================================================================
-- 02_base_view.sql 基础视图 v_order_base
-- 1.统一业务口径:防止数据杂乱
-- 2.减少代码重复性:把多表join和复杂逻辑封装成view
-- 3.隔离脏数据:把取消的,未送达的,时间逻辑错误的订单隔离在视图外
-- =======================================================================

use olist;

create or replace view v_order_base as
select o.order_id,
       c.customer_id,                                               # 订单级用户ID(一人下两单,这个ID不一样)
       c.customer_unique_id,                                        # 客户唯一ID(同一人下两单,这ID一样,用来计算RFM)
       c.customer_state,                                            # 客户所在州(用于跨州物流分析)
       o.order_status,                                              # 原始订单状态
       -- 有效订单,is_valid_order = 1, 则为有效订单
       case when o.order_status not in ('canceled', 'unavailable')
           then 1 else 0 end as is_valid_order,
       o.order_purchase_timestamp,                                  # 下单时间
       o.order_approved_at,                                         # 付款批准时间
       o.order_delivered_customer_date,                             # 实际送达时间
       o.order_delivered_carrier_date,                              # 承运商发货时间
       o.order_estimated_delivery_date,                             # 平台承诺的预计送达时间
       -- delivered_days,实际的物流天数
       datediff(o.order_delivered_customer_date,o.order_purchase_timestamp) as delivery_days,
       -- 物流履约状态
       case
           -- 未送达
           when o.order_status != 'delivered'
                or o.order_delivered_customer_date is null then 'undelivered'
           -- 未知
           when o.order_estimated_delivery_date is null then 'unknown'
           -- 迟到
           when date(o.order_delivered_customer_date) > date(o.order_estimated_delivery_date)
            then 'late'
           -- 准时
           else 'on_time' end as delivery_status,
       r.review_score,                                              # 评价得分
       p.payment_total,                                             # 订单总支付金额
       oi.order_total,                                              # 商品总金额
       oi.item_count                                                # 订单商品件数
from orders o
-- 1.订单必要有对应的客户
inner join customers c on o.customer_id = c.customer_id
-- 2.评价表去重
-- 逻辑:按order_id分组,用row_number()按评价时间倒序打上序号(1,2,3...),外层嵌套只保留rn = 1 (最旧一条)
left join (
    select order_id,review_score
    from (
        select order_id, review_score,
               row_number() over (partition by order_id
                                order by review_creation_date, review_id) as rn
        from order_reviews
         ) x
        where x.rn = 1
) r on o.order_id = r.order_id
-- 3.关联支付表
-- 为了防止一对多导致数据发散,先在子查询中用sum汇总出每一单的总金额,再和主表一对一
left join (
    select order_id, sum(order_payments.payment_value) as payment_total
    from order_payments
    group by order_id
) p on o.order_id = p.order_id
-- 4.关联商品明细表
-- 先在子查询中按order_id聚合出商品总价和件数,在和主表一对一
left join (
    select order_id, sum(price) as order_total, count(*) as item_count
    from order_items group by order_id
) oi on o.order_id = oi.order_id;

-- ------取保每个订单只出现一次(防止数据发散) -------------------------------
select count(*) as total_rows, count(distinct order_id) as distinct_orders
from v_order_base;