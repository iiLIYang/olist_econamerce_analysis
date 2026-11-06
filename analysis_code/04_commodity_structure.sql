-- ========================================================================
-- 04_commodity_structure.sql - 查看商品结构
-- ========================================================================

use olist;


# 建立品类基本盘,观察哪几类品类占主要
-- 算出每个品类的销售额,订单量,和客单价
with cat_sales as (
    select
        ifnull(t.product_category_name_english,'unknown') as category,          # 产品英文名,空值为'unknown'
        round(sum(oi.price), 2) as total_sales,                                 # 品类总销售额
        count(distinct oi.order_id) as orders_count,                            # 品类订单量
        count(*) as total_items,                                                # 品类总销量
        round(sum(oi.price)/count(distinct oi.order_id), 2) as category_aov     # 品类客单价 = 该品类总金额 / 该品类订单数
    from olist.order_items oi
    -- 只算有效订单,且锁定业务最完整的时窗口
    join olist.orders o on oi.order_id = o.order_id
        and o.order_status not in ('canceled', 'unavailable')
    join olist.products pr on oi.product_id = pr.product_id
    left join olist.product_category_name_translation t
        on t.product_category_name = pr.product_category_name
    where o.order_purchase_timestamp >= '2017-01-01'
      and o.order_purchase_timestamp <  '2018-09-01'
    group by ifnull(t.product_category_name_english,'unknown')
)
# 各品类销售额 / 订单量 / 销量, 并按销售额排名
select category,
       total_sales,
       orders_count,
       total_items,
       category_aov,
       -- 窗口函数rank:给销售额排名
       rank() over (order by total_sales desc) as rnk
from cat_sales
order by rnk;

# 品类帕累托与累计占比(累计占比集中度)
-- 用80/20 法则验证,是否是少数品类撑起了整个平台的大部分GMV
-- 判断收入集中度风险,如TOP5商品占据60%以上,那说明风险高只靠个别商品支撑总GMV,反之生态健康,风险低

with cat_sales as (
    select
        ifnull(t.product_category_name_english,'unknown') as category,
        round(sum(oi.price), 2)                           as total_sales
    from olist.order_items oi
        join olist.orders o
            on oi.order_id = o.order_id
                and o.order_status not in ('canceled', 'unavailable')
        join olist.products pr on oi.product_id = pr.product_id
        left join olist.product_category_name_translation t
            on t.product_category_name = pr.product_category_name
    where o.order_purchase_timestamp >= '2017-01-01'
      and o.order_purchase_timestamp <  '2018-09-01'
    group by ifnull(t.product_category_name_english,'unknown')
),
pareto as (
    select
        category,
        total_sales,
        -- 计算 销售额占比 = 该品类销售额 / 全平台总销售额
        round(100*total_sales/sum(total_sales) over(),2)                                       as gmv_pct,
        -- 累计销售额占比: 按销售额降序
        round(100*sum(total_sales) over(order by total_sales desc)/sum(total_sales) over (),2) as cumulative_pct,
        -- 按照销售额进行排名
        row_number() over (order by total_sales desc) as rn
        from cat_sales
)
select *
from pareto
where rn <= 20;


-- 各品类下的top5爆款单品
-- 找出这类单品作为核心单品(保障库存,优先发货)

with product_sales as (
    select
        ifnull(t.product_category_name_english,'unknown') as category,
        oi.product_id,
        round(sum(oi.price), 2) as item_revenue,                        # 单品总营收
        count(*) as sold_qty                                            # 单品总销量
    from order_items oi
             join olist.orders o
                  on oi.order_id = o.order_id
                      and o.order_status not in ('canceled', 'unavailable')
             join olist.products pr on oi.product_id = pr.product_id
             left join olist.product_category_name_translation t
                       on t.product_category_name = pr.product_category_name
    where o.order_purchase_timestamp >= '2017-01-01'
      and o.order_purchase_timestamp <  '2018-09-01'
    group by
        ifnull(t.product_category_name_english,'unknown'),
        oi.product_id
),
ranked_products as (
    select
        category,
        product_id,
        item_revenue,
        sold_qty,
        -- 按照category分组,在每个品类内部按照营收降序排名
        row_number() over (partition by category order by item_revenue desc) as product_rank
    from product_sales
)
select
    category,
    product_id,
    item_revenue,
    sold_qty
from ranked_products
where product_rank <= 5
order by category,product_rank;

-- 总Top 5 品类月度销量趋势
-- 观察这些事逐步上升还是悄悄推退落
-- 帮助业务发现高价值/高品质的商品和需要及时调整的商品

with category_totals as (
    -- 1.先算出所有品类的总销售额（用来找前 5 名）
    select
        ifnull(t.product_category_name_english, 'unknown') as category,
        sum(oi.price) as total_sales
    from order_items oi
             join orders o on oi.order_id = o.order_id
                        and o.order_status not in ('canceled', 'unavailable')
             join products pr on oi.product_id = pr.product_id
             left join product_category_name_translation t
                       on t.product_category_name = pr.product_category_name
    where o.order_purchase_timestamp >= '2017-01-01'
      and o.order_purchase_timestamp <  '2018-09-01'
    group by ifnull(t.product_category_name_english, 'unknown')
),
top_5_categories as (
    -- 2.排个序，真正取出前 5 名
    select category
    from category_totals
    order by total_sales desc
    limit 5
),
monthly_cat_sales as (
    -- 3.算这几个品类每个月的销售明细
    select
        date_format(o.order_purchase_timestamp,'%Y-%m')    as month,
        ifnull(t.product_category_name_english, 'unknown') as category,
        sum(oi.price)                                      as monthly_gmv
    from orders o
    join order_items oi on o.order_id = oi.order_id
    join products pr on oi.product_id = pr.product_id
    left join product_category_name_translation t
        on t.product_category_name = pr.product_category_name
    join top_5_categories tc on ifnull(t.product_category_name_english,'unknown') = tc.category
    where o.order_status not in ('canceled', 'unavailable')
      and o.order_purchase_timestamp >= '2017-01-01'
      and o.order_purchase_timestamp <  '2018-09-01'
    group by
        date_format(o.order_purchase_timestamp,'%Y-%m'),
        ifnull(t.product_category_name_english,'unknown')
)
select
    -- 4. 将明细表与Top5 名单关联, 计算环比
    m.month,
    m.category,
    round(m.monthly_gmv, 2) as monthly_gmv,
    -- 计算环比(%):按品类分区, 按月份排序,计算该品类自身的环比增长
round(100*(m.monthly_gmv - lag(monthly_gmv) over (partition by m.category order by month))
          / lag(monthly_gmv) over (partition by m.category order by month), 2) as mom_pct
from monthly_cat_sales m
order by m.category,
         month;
