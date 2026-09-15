-- =============================================================================
-- DATACO SUPPLY CHAIN — FINAL BUSINESS ANALYSIS
-- PostgreSQL
-- =============================================================================
--
-- Purpose:
--   Present the final decision-supporting SQL analysis after exploratory
--   validation of the DataCo Supply Chain warehouse.
--
-- Final analytical focus:
--   1. Executive performance
--   2. Data interpretation / trend limitation
--   3. Profit quality and profit leakage
--   4. Fulfillment reliability
--   5. Customer value concentration
--
-- Fact grain:
--   One row per order_item_id
--
-- Reporting principle:
--   Keep only analyses that materially support a business conclusion or
--   management decision. Exploratory dead ends and redundant descriptive
--   rankings are intentionally excluded from this final script.
-- =============================================================================

-- =============================================================================
-- SECTION 1 — EXECUTIVE PERFORMANCE
-- =============================================================================

-- =============================================================================
-- 1. What are the core executive KPIs for the business?
-- =============================================================================

WITH order_level AS (

    SELECT
        f.order_id,
        MAX(
            CASE
                WHEN op.delivery_status = 'Late Delivery' THEN 1
                ELSE 0
            END
        ) AS is_late

    FROM gold.fact_order_item f

    JOIN gold.dim_order_profile op
        ON f.order_profile_key = op.order_profile_key

    GROUP BY
        f.order_id
),

product_losses AS (

    SELECT
        p.product_name,

        SUM(
            CASE
                WHEN f.order_profit_per_order < 0
                    THEN f.order_profit_per_order
                ELSE 0
            END
        ) AS negative_profit

    FROM gold.fact_order_item f

    JOIN gold.dim_product p
        ON f.product_key = p.product_key

    GROUP BY
        p.product_name
),

ranked_losses AS (

    SELECT
        product_name,
        negative_profit,

        ROW_NUMBER() OVER (
            ORDER BY negative_profit ASC
        ) AS loss_rank

    FROM product_losses

    WHERE
        negative_profit < 0
)

SELECT
    ROUND(SUM(f.sales), 2) AS total_sales,

    ROUND(
        SUM(f.order_profit_per_order),
        2
    ) AS net_profit,

    ROUND(
        SUM(f.order_profit_per_order)
        / NULLIF(SUM(f.sales), 0) * 100,
        2
    ) AS profit_margin_pct,

    COUNT(DISTINCT f.order_id) AS total_orders,
    COUNT(*) AS total_order_items,

    ROUND(
        COUNT(*) FILTER (
            WHERE f.order_profit_per_order < 0
        ) * 100.0
        / NULLIF(COUNT(*), 0),
        2
    ) AS loss_making_item_rate_pct,

    ROUND(
        ABS(
            SUM(
                CASE
                    WHEN f.order_profit_per_order < 0
                        THEN f.order_profit_per_order
                    ELSE 0
                END
            )
        ),
        2
    ) AS total_negative_profit,

    ROUND(
        (
            SELECT SUM(ABS(negative_profit))
            FROM ranked_losses
            WHERE loss_rank <= 8
        )
        /
        NULLIF(
            (
                SELECT SUM(ABS(negative_profit))
                FROM ranked_losses
            ),
            0
        ) * 100,
        2
    ) AS top_8_negative_profit_share_pct,

    ROUND(
        (
            SELECT
                COUNT(*) FILTER (WHERE is_late = 1) * 100.0
                / NULLIF(COUNT(*), 0)
            FROM order_level
        ),
        2
    ) AS late_delivery_rate_pct

FROM gold.fact_order_item f;

/*
INSIGHT:

The final executive KPI summary is:

- Total Sales:                         36.78M
- Net Profit:                           3.97M
- Profit Margin:                       10.78%
- Total Orders:                        65,752
- Total Order Items:                  180,519
- Loss-Making Item Rate:               18.71%
- Total Negative Profit:                3.88M
- Top 8 Products' Share of Losses:     84.64%
- Late Delivery Rate:                  54.82%

BUSINESS INSIGHT:

Headline sales and net profit hide two major business risks:

1. PROFIT QUALITY
   Nearly one in five order items loses money, and the majority of negative
   profit is concentrated in only a small group of products.

2. FULFILLMENT RELIABILITY
   More than half of all orders are delivered late.

These two issues form the core of the Power BI decision-support dashboard.
*/

-- =============================================================================
-- SECTION 2 — DATA INTERPRETATION
-- =============================================================================

-- =============================================================================
-- 2. What coverage changes accompany the apparent late-period sales collapse?
-- =============================================================================

SELECT
    d.year,
    d.month,
    d.month_name,

    COUNT(DISTINCT p.product_key) AS distinct_products,
    COUNT(DISTINCT p.category_name) AS distinct_categories,

    ROUND(
        SUM(f.sales)
        / NULLIF(SUM(f.order_item_quantity), 0),
        2
    ) AS sales_per_unit,

    ROUND(
        SUM(f.order_item_quantity)::NUMERIC
        / NULLIF(COUNT(DISTINCT f.order_id), 0),
        2
    ) AS units_per_order

FROM gold.fact_order_item f

JOIN gold.dim_date d
    ON f.order_date_key = d.date_key

JOIN gold.dim_product p
    ON f.product_key = p.product_key

WHERE
       (d.year = 2017 AND d.month >= 8)
    OR d.year = 2018

GROUP BY
    d.year,
    d.month,
    d.month_name

ORDER BY
    d.year,
    d.month;

/*
INSIGHT:

The apparent late-2017 sales decline coincides with a major collapse in
product and category coverage.

Examples:

September 2017:
- 53 products
- 26 categories
- 6.10 units/order

October 2017:
- 20 products
- 20 categories
- 1.19 units/order

November 2017:
- 8 products
- 8 categories
- 1.00 unit/order

January 2018:
- 10 products
- 10 categories
- 1.00 unit/order

BUSINESS / DATA INTERPRETATION:

The final months should not be presented as evidence of genuine demand or
business deterioration without context.

The change is strongly associated with reduced product/data coverage.

This reporting limitation should accompany every presentation of the trend.
*/

-- =============================================================================
-- SECTION 3 — PROFIT QUALITY & PROFIT LEAKAGE
-- =============================================================================

-- =============================================================================
-- 3. How much of the business comes from loss-making order items?
-- =============================================================================

SELECT
    COUNT(*) AS total_order_items,

    COUNT(*) FILTER (
        WHERE order_profit_per_order < 0
    ) AS loss_making_items,

    ROUND(
        COUNT(*) FILTER (
            WHERE order_profit_per_order < 0
        ) * 100.0
        / NULLIF(COUNT(*), 0),
        2
    ) AS loss_making_item_rate_pct,

    ROUND(
        SUM(sales) FILTER (
            WHERE order_profit_per_order < 0
        ),
        2
    ) AS sales_from_loss_making_items,

    ROUND(
        SUM(sales) FILTER (
            WHERE order_profit_per_order < 0
        ) * 100.0
        / NULLIF(SUM(sales), 0),
        2
    ) AS loss_making_sales_share_pct,

    ROUND(
        SUM(order_profit_per_order) FILTER (
            WHERE order_profit_per_order < 0
        ),
        2
    ) AS total_negative_profit,

    ROUND(
        SUM(order_profit_per_order) FILTER (
            WHERE order_profit_per_order >= 0
        ),
        2
    ) AS positive_profit,

    ROUND(
        SUM(order_profit_per_order),
        2
    ) AS net_profit

FROM gold.fact_order_item;

/*
INSIGHT:

Profit leakage is material:

- Total Order Items:                 180,519
- Loss-Making Items:                  33,784
- Loss-Making Item Rate:              18.71%
- Sales from Loss-Making Items:        6.87M
- Share of Total Sales:               18.68%
- Negative Profit:                    -3.88M
- Positive Profit Generated:           7.85M
- Final Net Profit:                    3.97M

Approximately 49.5% of the positive profit generated by profitable
transactions is erased by loss-making order items.

BUSINESS INSIGHT:

Improving existing loss-making transactions represents a significant profit
opportunity even without increasing sales.
*/

-- =============================================================================
-- 4. Which product categories contribute the most negative profit?
-- =============================================================================

SELECT
    p.category_name,

    COUNT(*) AS total_order_items,

    COUNT(*) FILTER (
        WHERE f.order_profit_per_order < 0
    ) AS loss_making_items,

    ROUND(
        COUNT(*) FILTER (
            WHERE f.order_profit_per_order < 0
        ) * 100.0
        / NULLIF(COUNT(*), 0),
        2
    ) AS loss_making_item_rate_pct,

    ROUND(
        SUM(f.sales),
        2
    ) AS total_sales,

    ROUND(
        SUM(f.sales) FILTER (
            WHERE f.order_profit_per_order < 0
        ),
        2
    ) AS loss_making_sales,

    ROUND(
        SUM(f.order_profit_per_order) FILTER (
            WHERE f.order_profit_per_order < 0
        ),
        2
    ) AS negative_profit,

    ROUND(
        SUM(f.order_profit_per_order) FILTER (
            WHERE f.order_profit_per_order >= 0
        ),
        2
    ) AS positive_profit,

    ROUND(
        SUM(f.order_profit_per_order),
        2
    ) AS net_profit

FROM gold.fact_order_item f

JOIN gold.dim_product p
    ON f.product_key = p.product_key

GROUP BY
    p.category_name

HAVING
    COUNT(*) >= 200

ORDER BY
    negative_profit ASC;

/*
INSIGHT:

Largest absolute negative-profit contributors include:

- Fishing:                -728.57K
- Cleats:                 -452.59K
- Camping & Hiking:       -443.08K
- Cardio Equipment:       -402.65K
- Water Sports:           -334.57K
- Women's Apparel:        -323.77K
- Men's Footwear:         -309.27K
- Indoor/Outdoor Games:   -298.64K

The major categories have broadly similar loss-making rates of approximately
18%-19%.

BUSINESS INSIGHT:

The largest losses are primarily driven by scale rather than uniquely poor
loss rates.

High-volume categories deserve priority because small improvements in their
loss-making transaction rates can create meaningful financial gains.
*/

-- =============================================================================
-- 5. Which individual products contribute the most negative profit?
-- =============================================================================

SELECT
    p.product_name,
    p.category_name,

    COUNT(*) AS total_order_items,

    COUNT(*) FILTER (
        WHERE f.order_profit_per_order < 0
    ) AS loss_making_items,

    ROUND(
        COUNT(*) FILTER (
            WHERE f.order_profit_per_order < 0
        ) * 100.0
        / NULLIF(COUNT(*), 0),
        2
    ) AS loss_making_item_rate_pct,

    ROUND(
        SUM(f.sales),
        2
    ) AS total_sales,

    ROUND(
        SUM(f.sales) FILTER (
            WHERE f.order_profit_per_order < 0
        ),
        2
    ) AS loss_making_sales,

    ROUND(
        SUM(f.order_profit_per_order) FILTER (
            WHERE f.order_profit_per_order < 0
        ),
        2
    ) AS negative_profit,

    ROUND(
        SUM(f.order_profit_per_order),
        2
    ) AS net_profit

FROM gold.fact_order_item f

JOIN gold.dim_product p
    ON f.product_key = p.product_key

GROUP BY
    p.product_name,
    p.category_name

HAVING
    COUNT(*) >= 200

ORDER BY
    negative_profit ASC

LIMIT 20;

/*
INSIGHT:

Profit leakage is concentrated in a small group of high-volume products.

Largest negative-profit contributors include:

- Field & Stream Sportsman 16 Gun Fire Safe:       -728.57K
- Perfect Fitness Perfect Rip Deck:                -450.98K
- Diamondback Women's Serene Classic Comfort Bike: -443.08K
- Nike Men's Free 5.0+ Running Shoe:               -400.02K
- Pelican Sunstream 100 Kayak:                     -332.80K
- Nike Men's Dri-FIT Victory Golf Polo:            -323.77K
- Nike Men's CJ Elite 2 TD Football Cleat:         -309.27K
- O'Brien Men's Neoprene Life Vest:                -298.64K

These products remain profitable overall, which means the issue is not that
the products are inherently unprofitable.

The issue is that a material subset of their transactions destroys profit.
*/

-- =============================================================================
-- 6. How concentrated is negative profit among the worst-performing products?
-- =============================================================================

WITH product_losses AS (

    SELECT
        p.product_name,

        SUM(
            CASE
                WHEN f.order_profit_per_order < 0
                    THEN f.order_profit_per_order
                ELSE 0
            END
        ) AS negative_profit

    FROM gold.fact_order_item f

    JOIN gold.dim_product p
        ON f.product_key = p.product_key

    GROUP BY
        p.product_name
),

ranked_products AS (

    SELECT
        product_name,
        negative_profit,

        ROW_NUMBER() OVER (
            ORDER BY negative_profit ASC
        ) AS loss_rank,

        SUM(ABS(negative_profit)) OVER ()
            AS total_negative_profit,

        SUM(ABS(negative_profit)) OVER (
            ORDER BY negative_profit ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_negative_profit

    FROM product_losses

    WHERE
        negative_profit < 0
)

SELECT
    loss_rank,
    product_name,

    ROUND(
        negative_profit,
        2
    ) AS negative_profit,

    ROUND(
        ABS(negative_profit)
        / NULLIF(total_negative_profit, 0) * 100,
        2
    ) AS negative_profit_share_pct,

    ROUND(
        cumulative_negative_profit
        / NULLIF(total_negative_profit, 0) * 100,
        2
    ) AS cumulative_negative_profit_pct

FROM ranked_products

ORDER BY
    loss_rank;

/*
INSIGHT:

Negative profit is extremely concentrated:

- Top 1 product:   18.76%
- Top 4 products:  52.08%
- Top 8 products:  84.64%
- Top 10 products: 90.17%

BUSINESS INSIGHT:

Management does not need to treat all products equally.

A focused review of the small number of products responsible for most profit
leakage can address the majority of the financial exposure.

Priority actions may include:

- Product cost review
- Pricing review
- Supplier / sourcing review
- Fulfillment-cost investigation
- Product-level profitability monitoring

DATA LIMITATION:

The source does not contain detailed COGS, shipping cost, returns, supplier
cost, or other transaction-level operating costs.

The analysis can reliably identify WHERE profit leakage is concentrated, but
it should not claim a causal explanation that the available data cannot
support.
*/

-- =============================================================================
-- 7. How does profit margin change as discount depth increases?
-- =============================================================================

SELECT

    CASE
        WHEN order_item_discount_rate = 0
            THEN '0%'

        WHEN order_item_discount_rate <= 0.05
            THEN '0-5%'

        WHEN order_item_discount_rate <= 0.10
            THEN '5-10%'

        WHEN order_item_discount_rate <= 0.15
            THEN '10-15%'

        WHEN order_item_discount_rate <= 0.20
            THEN '15-20%'

        WHEN order_item_discount_rate <= 0.25
            THEN '20-25%'

        ELSE '25%+'
    END AS discount_band,

    COUNT(*) AS order_items,
    SUM(order_item_quantity) AS units_sold,

    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(order_profit_per_order), 2) AS total_profit,

    ROUND(
        SUM(order_profit_per_order)
        / NULLIF(SUM(sales), 0) * 100,
        2
    ) AS profit_margin_pct

FROM gold.fact_order_item

GROUP BY

    CASE
        WHEN order_item_discount_rate = 0
            THEN '0%'

        WHEN order_item_discount_rate <= 0.05
            THEN '0-5%'

        WHEN order_item_discount_rate <= 0.10
            THEN '5-10%'

        WHEN order_item_discount_rate <= 0.15
            THEN '10-15%'

        WHEN order_item_discount_rate <= 0.20
            THEN '15-20%'

        WHEN order_item_discount_rate <= 0.25
            THEN '20-25%'

        ELSE '25%+'
    END

ORDER BY
    MIN(order_item_discount_rate);

/*
INSIGHT:

Profit margin declines as discount depth increases:

- 0%:      13.09%
- 0-5%:    11.47%
- 5-10%:   11.34%
- 10-15%:  10.20%
- 15-20%:   9.59%
- 20-25%:   9.39%

BUSINESS INSIGHT:

Deeper discount bands are associated with lower observed margins.

However, lower margin does not automatically mean that discounts cause
negative-profit transactions.

That hypothesis is tested separately in the next analysis.
*/

-- =============================================================================
-- 8. Does deeper discounting increase the probability of a loss-making item?
-- =============================================================================

SELECT

    CASE
        WHEN f.order_item_discount_rate = 0
            THEN '0%'

        WHEN f.order_item_discount_rate <= 0.05
            THEN '0-5%'

        WHEN f.order_item_discount_rate <= 0.10
            THEN '5-10%'

        WHEN f.order_item_discount_rate <= 0.15
            THEN '10-15%'

        WHEN f.order_item_discount_rate <= 0.20
            THEN '15-20%'

        WHEN f.order_item_discount_rate <= 0.25
            THEN '20-25%'

        ELSE '25%+'
    END AS discount_band,

    COUNT(*) AS total_order_items,

    COUNT(*) FILTER (
        WHERE f.order_profit_per_order < 0
    ) AS loss_making_items,

    ROUND(
        COUNT(*) FILTER (
            WHERE f.order_profit_per_order < 0
        ) * 100.0
        / NULLIF(COUNT(*), 0),
        2
    ) AS loss_making_item_rate_pct,

    ROUND(
        SUM(f.sales),
        2
    ) AS total_sales,

    ROUND(
        SUM(f.order_profit_per_order) FILTER (
            WHERE f.order_profit_per_order < 0
        ),
        2
    ) AS negative_profit,

    ROUND(
        SUM(f.order_profit_per_order),
        2
    ) AS net_profit

FROM gold.fact_order_item f

GROUP BY

    CASE
        WHEN f.order_item_discount_rate = 0
            THEN '0%'

        WHEN f.order_item_discount_rate <= 0.05
            THEN '0-5%'

        WHEN f.order_item_discount_rate <= 0.10
            THEN '5-10%'

        WHEN f.order_item_discount_rate <= 0.15
            THEN '10-15%'

        WHEN f.order_item_discount_rate <= 0.20
            THEN '15-20%'

        WHEN f.order_item_discount_rate <= 0.25
            THEN '20-25%'

        ELSE '25%+'
    END

ORDER BY
    MIN(f.order_item_discount_rate);

/*
INSIGHT:

Loss-making rates remain almost flat across discount bands:

- 0%:      18.38%
- 0-5%:    18.68%
- 5-10%:   18.37%
- 10-15%:  18.95%
- 15-20%:  19.07%
- 20-25%:  18.48%

BUSINESS INSIGHT:

Loss frequency is similar across discount bands; this association does not establish causation.

The data supports two separate profitability issues:

1. MARGIN EROSION
   Deeper discounts reduce the amount of profit earned.

2. PROFIT LEAKAGE
   Approximately 18%-19% of order items lose money regardless of discount
   depth.

The available commercial variables do not provide enough information to
reliably explain the root cause of negative-profit transactions.
*/

-- =============================================================================
-- SECTION 4 — FULFILLMENT RELIABILITY
-- =============================================================================

-- =============================================================================
-- 9. How are orders distributed across delivery outcomes?
-- =============================================================================

WITH order_delivery AS (

    SELECT
        f.order_id,
        op.delivery_status,
        op.shipping_mode,

        SUM(f.sales) AS order_sales,

        MAX(f.days_for_shipping_real)
            AS actual_shipping_days,

        MAX(f.days_for_shipment_scheduled)
            AS scheduled_shipping_days

    FROM gold.fact_order_item f

    JOIN gold.dim_order_profile op
        ON f.order_profile_key = op.order_profile_key

    GROUP BY
        f.order_id,
        op.delivery_status,
        op.shipping_mode
)

SELECT
    delivery_status,

    COUNT(*) AS total_orders,

    ROUND(
        COUNT(*) * 100.0
        / SUM(COUNT(*)) OVER (),
        2
    ) AS order_share_pct,

    ROUND(
        SUM(order_sales),
        2
    ) AS total_sales,

    ROUND(
        SUM(order_sales) * 100.0
        / SUM(SUM(order_sales)) OVER (),
        2
    ) AS sales_share_pct,

    ROUND(
        AVG(actual_shipping_days),
        2
    ) AS avg_actual_shipping_days,

    ROUND(
        AVG(scheduled_shipping_days),
        2
    ) AS avg_scheduled_shipping_days,

    ROUND(
        AVG(
            actual_shipping_days
            - scheduled_shipping_days
        ),
        2
    ) AS avg_schedule_variance_days

FROM order_delivery

GROUP BY
    delivery_status

ORDER BY
    total_orders DESC;

/*
INSIGHT:

Delivery outcomes are:

Late Delivery:
- 36,048 orders
- 54.82% of orders
- Approximately 20.13M in sales
- Average schedule variance: +1.62 days

Advance Shipping:
- 23.01% of orders
- Average schedule variance: -1.50 days

Shipping On Time:
- 17.83% of orders
- Average schedule variance: 0 days

Shipping Canceled:
- 4.34% of orders

BUSINESS INSIGHT:

More than half of all orders are delivered late.

At the same time, a substantial share is delivered in advance, showing that
fulfillment performance is highly inconsistent rather than uniformly slow.
*/

-- =============================================================================
-- 10. How does delivery performance vary by shipping mode?
-- =============================================================================

WITH order_shipping AS (

    SELECT
        f.order_id,
        op.shipping_mode,
        op.delivery_status,

        SUM(f.sales) AS order_sales,

        MAX(f.days_for_shipping_real)
            AS actual_shipping_days,

        MAX(f.days_for_shipment_scheduled)
            AS scheduled_shipping_days

    FROM gold.fact_order_item f

    JOIN gold.dim_order_profile op
        ON f.order_profile_key = op.order_profile_key

    GROUP BY
        f.order_id,
        op.shipping_mode,
        op.delivery_status
)

SELECT
    shipping_mode,

    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE delivery_status = 'Late Delivery'
    ) AS late_orders,

    ROUND(
        COUNT(*) FILTER (
            WHERE delivery_status = 'Late Delivery'
        ) * 100.0
        / NULLIF(COUNT(*), 0),
        2
    ) AS late_rate_pct,

    COUNT(*) FILTER (
        WHERE delivery_status = 'Shipping On Time'
    ) AS on_time_orders,

    COUNT(*) FILTER (
        WHERE delivery_status = 'Advance Shipping'
    ) AS advance_orders,

    COUNT(*) FILTER (
        WHERE delivery_status = 'Shipping Canceled'
    ) AS canceled_orders,

    ROUND(
        AVG(
            actual_shipping_days
            - scheduled_shipping_days
        ) FILTER (
            WHERE delivery_status <> 'Shipping Canceled'
        ),
        2
    ) AS avg_schedule_variance_days,

    ROUND(
        SUM(order_sales) FILTER (
            WHERE delivery_status = 'Late Delivery'
        ),
        2
    ) AS late_order_sales

FROM order_shipping

GROUP BY
    shipping_mode

ORDER BY
    late_rate_pct DESC;

/*
INSIGHT:

Delivery reliability varies dramatically by shipping mode:

- First Class:     95.27% late
- Second Class:    76.72% late
- Same Day:        46.15% late
- Standard Class:  38.13% late

First Class:
- 9,602 late orders
- 0 on-time orders
- 0 advance shipments
- Average schedule variance: +1 day

Second Class:
- 9,803 late orders
- Average schedule variance: +2 days

Standard Class:
- Much lower late rate
- 15,127 advance shipments
- Average schedule variance: approximately 0 days

BUSINESS INSIGHT:

Shipping mode is strongly associated with delivery performance.

The premium / expedited services perform materially worse against their
promised service levels than Standard Class.
*/

-- =============================================================================
-- 11. How severe are late deliveries by shipping mode?
-- =============================================================================

WITH order_shipping AS (

    SELECT
        f.order_id,
        op.shipping_mode,
        op.delivery_status,

        MAX(f.days_for_shipping_real)
            AS actual_shipping_days,

        MAX(f.days_for_shipment_scheduled)
            AS scheduled_shipping_days

    FROM gold.fact_order_item f

    JOIN gold.dim_order_profile op
        ON f.order_profile_key = op.order_profile_key

    GROUP BY
        f.order_id,
        op.shipping_mode,
        op.delivery_status
),

late_orders AS (

    SELECT
        order_id,
        shipping_mode,

        actual_shipping_days
            - scheduled_shipping_days
            AS delay_days

    FROM order_shipping

    WHERE
        delivery_status = 'Late Delivery'
)

SELECT
    shipping_mode,

    COUNT(*) AS late_orders,

    COUNT(*) FILTER (
        WHERE delay_days = 1
    ) AS one_day_late,

    COUNT(*) FILTER (
        WHERE delay_days = 2
    ) AS two_days_late,

    COUNT(*) FILTER (
        WHERE delay_days >= 3
    ) AS three_plus_days_late,

    ROUND(
        COUNT(*) FILTER (
            WHERE delay_days >= 2
        ) * 100.0
        / NULLIF(COUNT(*), 0),
        2
    ) AS severe_delay_rate_pct,

    ROUND(
        AVG(delay_days),
        2
    ) AS avg_delay_days,

    MAX(delay_days) AS max_delay_days

FROM late_orders

GROUP BY
    shipping_mode

ORDER BY
    avg_delay_days DESC;

/*
INSIGHT:

Delay severity differs materially by shipping mode.

First Class:
- 9,602 late orders
- All are exactly 1 day late
- Severe Delay Rate: 0%
- Maximum Delay: 1 day

Same Day:
- All late orders are exactly 1 day late
- Severe Delay Rate: 0%

Standard Class:
- 50.26% of late orders are at least 2 days late
- Average Delay: 1.5 days
- Maximum Delay: 2 days

Second Class:
- 75.29% of late orders are at least 2 days late
- 4,908 orders are 3+ days late
- Average Delay: 2.5 days
- Maximum Delay: 4 days

BUSINESS INSIGHT:

Late-delivery frequency and delay severity are different management problems.

- First Class is primarily a service-promise / commitment problem.
- Second Class is the strongest operational priority because it combines a
  high late rate with severe multi-day delays.
*/

-- =============================================================================
-- SECTION 5 — CUSTOMER VALUE
-- =============================================================================

-- =============================================================================
-- 12. How concentrated is profit across individual customers?
-- =============================================================================

WITH customer_profit AS (

    SELECT
        c.customer_id,
        c.customer_fname,
        c.customer_lname,

        COUNT(DISTINCT f.order_id) AS total_orders,
        SUM(f.sales) AS total_sales,
        SUM(f.order_profit_per_order) AS total_profit

    FROM gold.fact_order_item f

    JOIN gold.dim_customer c
        ON f.customer_key = c.customer_key

    GROUP BY
        c.customer_id,
        c.customer_fname,
        c.customer_lname
),

ranked_customers AS (

    SELECT
        customer_id,
        customer_fname,
        customer_lname,
        total_orders,
        total_sales,
        total_profit,

        ROW_NUMBER() OVER (
            ORDER BY total_profit DESC
        ) AS profit_rank,

        COUNT(*) OVER () AS total_customers,

        SUM(total_profit) OVER () AS company_profit,

        SUM(total_profit) OVER (
            ORDER BY total_profit DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_profit

    FROM customer_profit
)

SELECT
    profit_rank,
    customer_id,

    customer_fname || ' ' || customer_lname
        AS customer_name,

    total_orders,

    ROUND(total_sales, 2) AS total_sales,
    ROUND(total_profit, 2) AS total_profit,

    ROUND(
        profit_rank * 100.0
        / NULLIF(total_customers, 0),
        2
    ) AS cumulative_customer_pct,

    ROUND(
        cumulative_profit * 100.0
        / NULLIF(company_profit, 0),
        2
    ) AS cumulative_profit_pct

FROM ranked_customers

ORDER BY
    profit_rank;

/*
INSIGHT:

Customer profitability is meaningfully concentrated:

- Top 5% of customers generate approximately 28.75% of net profit.
- Top 10% generate approximately 49.08%.
- Top 20% generate approximately 79.17%.
- Top 30% generate approximately 100% of final net profit.

A meaningful tail of customers generates negative total profit, causing the
cumulative-profit curve to rise above 100% before returning to final company
net profit.

BUSINESS INSIGHT:

Individual customer profitability is much more useful than broad customer
segment labels for prioritization.

High-value customers may deserve stronger retention, service monitoring, and
account-management attention.
*/

-- =============================================================================
-- 13. Are high-value customers receiving more reliable delivery service?
-- =============================================================================

WITH customer_value AS (

    SELECT
        c.customer_id,
        SUM(f.order_profit_per_order) AS total_profit

    FROM gold.fact_order_item f

    JOIN gold.dim_customer c
        ON f.customer_key = c.customer_key

    GROUP BY
        c.customer_id
),

customer_rank AS (

    SELECT
        customer_id,
        total_profit,

        NTILE(5) OVER (
            ORDER BY total_profit DESC
        ) AS value_quintile

    FROM customer_value
),

order_delivery AS (

    SELECT
        f.order_id,
        c.customer_id,
        op.delivery_status,

        MAX(f.days_for_shipping_real)
            AS actual_shipping_days,

        MAX(f.days_for_shipment_scheduled)
            AS scheduled_shipping_days

    FROM gold.fact_order_item f

    JOIN gold.dim_customer c
        ON f.customer_key = c.customer_key

    JOIN gold.dim_order_profile op
        ON f.order_profile_key = op.order_profile_key

    GROUP BY
        f.order_id,
        c.customer_id,
        op.delivery_status
)

SELECT

    CASE cr.value_quintile
        WHEN 1 THEN 'Top 20%'
        WHEN 2 THEN '20-40%'
        WHEN 3 THEN '40-60%'
        WHEN 4 THEN '60-80%'
        WHEN 5 THEN 'Bottom 20%'
    END AS customer_value_group,

    COUNT(DISTINCT cr.customer_id) AS customers,
    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE od.delivery_status = 'Late Delivery'
    ) AS late_orders,

    ROUND(
        COUNT(*) FILTER (
            WHERE od.delivery_status = 'Late Delivery'
        ) * 100.0
        / NULLIF(COUNT(*), 0),
        2
    ) AS late_rate_pct,

    ROUND(
        AVG(
            od.actual_shipping_days
            - od.scheduled_shipping_days
        ) FILTER (
            WHERE od.delivery_status = 'Late Delivery'
        ),
        2
    ) AS avg_late_delay_days

FROM customer_rank cr

JOIN order_delivery od
    ON cr.customer_id = od.customer_id

GROUP BY
    cr.value_quintile

ORDER BY
    cr.value_quintile;

/*
INSIGHT:

Delivery performance is almost identical across customer-value groups:

- Top 20%:     54.78% late
- 20-40%:      54.58% late
- 40-60%:      55.59% late
- 60-80%:      54.57% late
- Bottom 20%:  54.83% late

Average late-delay severity is also almost identical at approximately
1.61-1.63 days across all groups.

BUSINESS INSIGHT:

High-value customers do not receive materially better fulfillment service
than lower-value customers.

This matters because the Top 20% of customers generate approximately 79% of
company net profit, yet they are exposed to the same fulfillment reliability
problem as the rest of the customer base.
*/

-- =============================================================================
-- FINAL BUSINESS FINDINGS
-- =============================================================================

/*
1. OVERALL PERFORMANCE
----------------------
The business generated approximately:

- 36.78M in Sales
- 3.97M in Net Profit
- 65,752 Orders
- 10.78% Profit Margin

The company is profitable overall, but headline performance hides important
commercial and operational risks.

2. PROFIT QUALITY & PROFIT LEAKAGE
----------------------------------
- 18.71% of order items are loss-making.
- Loss-making items account for approximately 18.68% of sales.
- Negative-profit transactions generate approximately -3.88M in losses.
- The Top 8 products account for 84.64% of all negative profit.
- The Top 10 products account for 90.17%.

Decision:
Prioritize product-level profitability review rather than treating the entire
portfolio equally.

3. DISCOUNT ECONOMICS
---------------------
Discount depth clearly reduces average profit margin:

- 0% discount: 13.09% margin
- 20-25% discount: 9.39% margin

However, the loss-making transaction rate remains roughly 18%-19% across all
discount bands.

Decision:
Treat discounting as a margin-management issue, not as the demonstrated root
cause of negative-profit transactions.

4. FULFILLMENT RELIABILITY
--------------------------
- 54.82% of orders are delivered late.
- First Class has the highest late-delivery frequency at 95.27%.
- First Class late orders are consistently only 1 day late.
- Second Class has a 76.72% late rate and the most severe delays.
- 75.29% of late Second Class orders are at least 2 days late.
- Maximum Second Class delay reaches 4 days.

Decision:

First Class:
- Review whether the promised service level is realistically achievable.

Second Class:
- Investigate deeper fulfillment / transportation constraints.

5. CUSTOMER VALUE
-----------------
- Broad customer segments do not materially differ in economic value.
- Individual customer profitability is much more concentrated.
- Top 20% of customers generate approximately 79% of net profit.
- High-value customers receive essentially the same delivery performance as
  lower-value customers.

Decision:
Use customer profitability rather than broad customer segment as the main
customer-prioritization lens.

6. DATA INTERPRETATION LIMITATION
---------------------------------
The apparent revenue decline near the end of 2017 coincides with a major
reduction in product and category coverage.

Decision:
Do not present the final months as evidence of genuine business decline
without documenting the data-coverage limitation.

*/
