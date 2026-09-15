-- =============================================================================
-- DATACO SUPPLY CHAIN — GOLD LAYER
-- Source: silver.dataco_supply_chain_clean
-- Model: Star Schema
--
-- Fact Grain:
--   One row per order_item_id
--
-- Dimensions:
--   dim_customer
--   dim_product
--   dim_destination
--   dim_order_profile
--   dim_date
--
-- Fact:
--   fact_order_item
-- =============================================================================

-- =============================================================================
-- 1. CREATE GOLD SCHEMA
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS gold;

-- =============================================================================
-- 2. DROP EXISTING GOLD TABLES
-- Fact must be dropped first because it references the dimensions.
-- =============================================================================

DROP TABLE IF EXISTS gold.fact_order_item;

DROP TABLE IF EXISTS gold.dim_order_profile;
DROP TABLE IF EXISTS gold.dim_destination;
DROP TABLE IF EXISTS gold.dim_product;
DROP TABLE IF EXISTS gold.dim_customer;
DROP TABLE IF EXISTS gold.dim_date;

-- =============================================================================
-- 3. DIM CUSTOMER
-- One row per customer_id
-- =============================================================================

CREATE TABLE gold.dim_customer (

    customer_key SERIAL PRIMARY KEY,

    -- Source business key
    customer_id INTEGER NOT NULL UNIQUE,

    customer_fname VARCHAR(100),
    customer_lname VARCHAR(100),
    customer_segment VARCHAR(100),

    customer_city VARCHAR(150),
    customer_state VARCHAR(100),
    customer_country VARCHAR(100),
    customer_zipcode VARCHAR(30),

    latitude NUMERIC(10,6),
    longitude NUMERIC(10,6)
);

INSERT INTO gold.dim_customer (
    customer_id,
    customer_fname,
    customer_lname,
    customer_segment,
    customer_city,
    customer_state,
    customer_country,
    customer_zipcode,
    latitude,
    longitude
)

SELECT DISTINCT
    customer_id,
    customer_fname,
    customer_lname,
    customer_segment,
    customer_city,
    customer_state,
    customer_country,
    customer_zipcode,
    latitude,
    longitude

FROM silver.dataco_supply_chain_clean;

-- =============================================================================
-- 4. DIM PRODUCT
-- One row per product_card_id
--
-- Category and department are flattened into DimProduct.
-- This keeps the reporting model as a simple star schema rather than snowflake.
-- =============================================================================

CREATE TABLE gold.dim_product (

    product_key SERIAL PRIMARY KEY,

    -- Source business key
    product_card_id INTEGER NOT NULL UNIQUE,

    product_name VARCHAR(255),

    product_category_id INTEGER,
    category_id INTEGER,
    category_name VARCHAR(150),

    department_id INTEGER,
    department_name VARCHAR(150),

    product_price NUMERIC(12,2)
);

INSERT INTO gold.dim_product (
    product_card_id,
    product_name,
    product_category_id,
    category_id,
    category_name,
    department_id,
    department_name,
    product_price
)

SELECT DISTINCT
    product_card_id,
    product_name,
    product_category_id,
    category_id,
    category_name,
    department_id,
    department_name,
    product_price

FROM silver.dataco_supply_chain_clean;

-- =============================================================================
-- 5. DIM DESTINATION
--
-- Represents the destination of the order.
-- This is separate from the customer's own location.
-- =============================================================================

CREATE TABLE gold.dim_destination (

    destination_key SERIAL PRIMARY KEY,

    order_city VARCHAR(150),
    order_state VARCHAR(150),
    order_country VARCHAR(100),
    order_region VARCHAR(150),
    market VARCHAR(100),

    CONSTRAINT uq_destination UNIQUE (
        order_city,
        order_state,
        order_country,
        order_region,
        market
    )
);

INSERT INTO gold.dim_destination (
    order_city,
    order_state,
    order_country,
    order_region,
    market
)

SELECT DISTINCT
    order_city,
    order_state,
    order_country,
    order_region,
    market

FROM silver.dataco_supply_chain_clean;

-- =============================================================================
-- 6. DIM ORDER PROFILE
--
-- Stores low-cardinality descriptive order/shipping attributes.
-- =============================================================================

CREATE TABLE gold.dim_order_profile (

    order_profile_key SERIAL PRIMARY KEY,

    type VARCHAR(50),
    order_status VARCHAR(100),
    delivery_status VARCHAR(50),
    shipping_mode VARCHAR(100),
    late_delivery_risk SMALLINT,

    CONSTRAINT uq_order_profile UNIQUE (
        type,
        order_status,
        delivery_status,
        shipping_mode,
        late_delivery_risk
    )
);

INSERT INTO gold.dim_order_profile (
    type,
    order_status,
    delivery_status,
    shipping_mode,
    late_delivery_risk
)

SELECT DISTINCT
    type,
    order_status,
    delivery_status,
    shipping_mode,
    late_delivery_risk

FROM silver.dataco_supply_chain_clean;

-- =============================================================================
-- 7. DIM DATE
--
-- One shared date dimension used by:
--
--   fact_order_item.order_date_key
--   fact_order_item.shipping_date_key
--
-- IMPORTANT:
-- Date range is generated from BOTH order_timestamp and shipping_timestamp.
-- =============================================================================

-- =============================================================================
-- DIM DATE
-- =============================================================================

-- DimDate was already dropped in section 2; no cascading drop is needed.

CREATE TABLE gold.dim_date (
    date_key INTEGER PRIMARY KEY,

    full_date DATE NOT NULL UNIQUE,

    year INTEGER,
    quarter INTEGER,

    month INTEGER,
    month_name VARCHAR(20),

    week_of_year INTEGER,

    day INTEGER,
    day_name VARCHAR(20),

    is_weekend BOOLEAN
);

-- =============================================================================
-- LOAD DIM DATE
--
-- Date range is calculated from BOTH:
--   order_timestamp
--   shipping_timestamp
--
-- This ensures the maximum shipping date, including 2018-02-06,
-- is included in DimDate.
-- =============================================================================

WITH all_dates AS (

    SELECT
        order_timestamp::DATE AS dt
    FROM silver.dataco_supply_chain_clean

    UNION ALL

    SELECT
        shipping_timestamp::DATE AS dt
    FROM silver.dataco_supply_chain_clean
),

date_bounds AS (

    SELECT
        MIN(dt) AS min_date,
        MAX(dt) AS max_date
    FROM all_dates

)

INSERT INTO gold.dim_date (
    date_key,
    full_date,
    year,
    quarter,
    month,
    month_name,
    week_of_year,
    day,
    day_name,
    is_weekend
)

SELECT
    TO_CHAR(d::DATE, 'YYYYMMDD')::INTEGER
        AS date_key,

    d::DATE
        AS full_date,

    EXTRACT(YEAR FROM d)::INTEGER
        AS year,

    EXTRACT(QUARTER FROM d)::INTEGER
        AS quarter,

    EXTRACT(MONTH FROM d)::INTEGER
        AS month,

    TO_CHAR(d, 'FMMonth')
        AS month_name,

    EXTRACT(WEEK FROM d)::INTEGER
        AS week_of_year,

    EXTRACT(DAY FROM d)::INTEGER
        AS day,

    TO_CHAR(d, 'FMDay')
        AS day_name,

    CASE
        WHEN EXTRACT(ISODOW FROM d) IN (6, 7)
            THEN TRUE
        ELSE FALSE
    END
        AS is_weekend

FROM date_bounds b

CROSS JOIN LATERAL GENERATE_SERIES(
    b.min_date::TIMESTAMP,
    b.max_date::TIMESTAMP,
    INTERVAL '1 day'
) AS d;

-- =============================================================================
-- 8. VALIDATE DIM DATE BEFORE FACT LOAD
-- =============================================================================

SELECT
    MIN(full_date) AS min_dim_date,
    MAX(full_date) AS max_dim_date,
    COUNT(*) AS total_dates
FROM gold.dim_date;

-- Check for missing order dates

SELECT DISTINCT
    s.order_timestamp::DATE AS missing_order_date

FROM silver.dataco_supply_chain_clean s

LEFT JOIN gold.dim_date d
    ON s.order_timestamp::DATE = d.full_date

WHERE d.date_key IS NULL;

-- Check for missing shipping dates

SELECT DISTINCT
    s.shipping_timestamp::DATE AS missing_shipping_date

FROM silver.dataco_supply_chain_clean s

LEFT JOIN gold.dim_date d
    ON s.shipping_timestamp::DATE = d.full_date

WHERE d.date_key IS NULL;

-- Both queries above should return:
-- 0 rows

-- =============================================================================
-- 9. FACT ORDER ITEM
--
-- Grain:
-- One row per order_item_id
--
-- order_id is retained as a degenerate dimension.
-- =============================================================================

CREATE TABLE gold.fact_order_item (

    -- -------------------------------------------------------------------------
    -- PRIMARY KEY
    -- -------------------------------------------------------------------------

    order_item_id INTEGER PRIMARY KEY,

    -- -------------------------------------------------------------------------
    -- DEGENERATE DIMENSION
    -- -------------------------------------------------------------------------

    order_id INTEGER NOT NULL,

    -- -------------------------------------------------------------------------
    -- DIMENSION FOREIGN KEYS
    -- -------------------------------------------------------------------------

    customer_key INTEGER NOT NULL,
    product_key INTEGER NOT NULL,
    destination_key INTEGER NOT NULL,
    order_profile_key INTEGER NOT NULL,

    order_date_key INTEGER NOT NULL,
    shipping_date_key INTEGER NOT NULL,

    -- -------------------------------------------------------------------------
    -- QUANTITY
    -- -------------------------------------------------------------------------

    order_item_quantity INTEGER,

    -- -------------------------------------------------------------------------
    -- SALES
    -- -------------------------------------------------------------------------

    sales NUMERIC(12,2),

    sales_per_customer NUMERIC(12,2),

    order_item_total NUMERIC(12,2),

    -- -------------------------------------------------------------------------
    -- PRICING / DISCOUNT
    -- -------------------------------------------------------------------------

    order_item_product_price NUMERIC(12,2),

    order_item_discount NUMERIC(12,2),

    order_item_discount_rate NUMERIC(8,4),

    -- -------------------------------------------------------------------------
    -- PROFITABILITY
    -- -------------------------------------------------------------------------

    benefit_per_order NUMERIC(12,2),

    order_profit_per_order NUMERIC(12,2),

    order_item_profit_ratio NUMERIC(8,4),

    -- -------------------------------------------------------------------------
    -- SHIPPING PERFORMANCE
    -- -------------------------------------------------------------------------

    days_for_shipping_real INTEGER,

    days_for_shipment_scheduled INTEGER,

    -- -------------------------------------------------------------------------
    -- FOREIGN KEY CONSTRAINTS
    -- -------------------------------------------------------------------------

    CONSTRAINT fk_fact_customer
        FOREIGN KEY (customer_key)
        REFERENCES gold.dim_customer(customer_key),

    CONSTRAINT fk_fact_product
        FOREIGN KEY (product_key)
        REFERENCES gold.dim_product(product_key),

    CONSTRAINT fk_fact_destination
        FOREIGN KEY (destination_key)
        REFERENCES gold.dim_destination(destination_key),

    CONSTRAINT fk_fact_order_profile
        FOREIGN KEY (order_profile_key)
        REFERENCES gold.dim_order_profile(order_profile_key),

    CONSTRAINT fk_fact_order_date
        FOREIGN KEY (order_date_key)
        REFERENCES gold.dim_date(date_key),

    CONSTRAINT fk_fact_shipping_date
        FOREIGN KEY (shipping_date_key)
        REFERENCES gold.dim_date(date_key)
);

-- =============================================================================
-- 10. LOAD FACT ORDER ITEM
-- =============================================================================

INSERT INTO gold.fact_order_item (

    order_item_id,
    order_id,

    customer_key,
    product_key,
    destination_key,
    order_profile_key,

    order_date_key,
    shipping_date_key,

    order_item_quantity,

    sales,
    sales_per_customer,
    order_item_total,

    order_item_product_price,
    order_item_discount,
    order_item_discount_rate,

    benefit_per_order,
    order_profit_per_order,
    order_item_profit_ratio,

    days_for_shipping_real,
    days_for_shipment_scheduled
)

SELECT

    -- -------------------------------------------------------------------------
    -- TRANSACTION IDS
    -- -------------------------------------------------------------------------

    s.order_item_id,
    s.order_id,

    -- -------------------------------------------------------------------------
    -- SURROGATE KEYS
    -- -------------------------------------------------------------------------

    c.customer_key,

    p.product_key,

    d.destination_key,

    op.order_profile_key,

    -- -------------------------------------------------------------------------
    -- ROLE-PLAYING DATE KEYS
    -- -------------------------------------------------------------------------

    TO_CHAR(
        s.order_timestamp::DATE,
        'YYYYMMDD'
    )::INTEGER
        AS order_date_key,

    TO_CHAR(
        s.shipping_timestamp::DATE,
        'YYYYMMDD'
    )::INTEGER
        AS shipping_date_key,

    -- -------------------------------------------------------------------------
    -- MEASURES
    -- -------------------------------------------------------------------------

    s.order_item_quantity,

    s.sales,
    s.sales_per_customer,
    s.order_item_total,

    s.order_item_product_price,
    s.order_item_discount,
    s.order_item_discount_rate,

    s.benefit_per_order,
    s.order_profit_per_order,
    s.order_item_profit_ratio,

    s.days_for_shipping_real,
    s.days_for_shipment_scheduled

FROM silver.dataco_supply_chain_clean s

-- =============================================================================
-- CUSTOMER LOOKUP
-- =============================================================================

JOIN gold.dim_customer c
    ON s.customer_id = c.customer_id

-- =============================================================================
-- PRODUCT LOOKUP
-- =============================================================================

JOIN gold.dim_product p
    ON s.product_card_id = p.product_card_id

-- =============================================================================
-- DESTINATION LOOKUP
-- =============================================================================

JOIN gold.dim_destination d

    ON s.order_city = d.order_city

   AND s.order_state = d.order_state

   AND s.order_country = d.order_country

   AND s.order_region = d.order_region

   AND s.market = d.market

-- =============================================================================
-- ORDER PROFILE LOOKUP
-- =============================================================================

JOIN gold.dim_order_profile op

    ON s.type = op.type

   AND s.order_status = op.order_status

   AND s.delivery_status = op.delivery_status

   AND s.shipping_mode = op.shipping_mode

   AND s.late_delivery_risk = op.late_delivery_risk;

-- =============================================================================
-- 11. INDEXES
-- Improve filtering and fact-to-dimension joins.
-- =============================================================================

CREATE INDEX idx_fact_customer_key
ON gold.fact_order_item(customer_key);

CREATE INDEX idx_fact_product_key
ON gold.fact_order_item(product_key);

CREATE INDEX idx_fact_destination_key
ON gold.fact_order_item(destination_key);

CREATE INDEX idx_fact_order_profile_key
ON gold.fact_order_item(order_profile_key);

CREATE INDEX idx_fact_order_date_key
ON gold.fact_order_item(order_date_key);

CREATE INDEX idx_fact_shipping_date_key
ON gold.fact_order_item(shipping_date_key);

CREATE INDEX idx_fact_order_id
ON gold.fact_order_item(order_id);

-- =============================================================================
-- 12. VALIDATE GOLD LAYER
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Silver vs Fact count
-- -----------------------------------------------------------------------------

SELECT

    (
        SELECT COUNT(*)
        FROM silver.dataco_supply_chain_clean
    ) AS silver_rows,

    (
        SELECT COUNT(*)
        FROM gold.fact_order_item
    ) AS fact_rows;

-- Expected:
--
-- silver_rows = 180519
-- fact_rows   = 180519

-- -----------------------------------------------------------------------------
-- Confirm Fact Grain
-- -----------------------------------------------------------------------------

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_item_id) AS distinct_order_items

FROM gold.fact_order_item;

-- Expected:
--
-- total_rows           = 180519
-- distinct_order_items = 180519

-- =============================================================================
-- 13. DIMENSION COUNTS
-- =============================================================================

SELECT
    COUNT(*) AS customers
FROM gold.dim_customer;

SELECT
    COUNT(*) AS products
FROM gold.dim_product;

SELECT
    COUNT(*) AS destinations
FROM gold.dim_destination;

SELECT
    COUNT(*) AS order_profiles
FROM gold.dim_order_profile;

SELECT
    COUNT(*) AS dates
FROM gold.dim_date;

-- =============================================================================
-- 14. FINAL FOREIGN KEY VALIDATION
-- =============================================================================

-- Missing customers

SELECT COUNT(*) AS missing_customers
FROM gold.fact_order_item f

LEFT JOIN gold.dim_customer d
    ON f.customer_key = d.customer_key

WHERE d.customer_key IS NULL;

-- Missing products

SELECT COUNT(*) AS missing_products
FROM gold.fact_order_item f

LEFT JOIN gold.dim_product d
    ON f.product_key = d.product_key

WHERE d.product_key IS NULL;

-- Missing destinations

SELECT COUNT(*) AS missing_destinations
FROM gold.fact_order_item f

LEFT JOIN gold.dim_destination d
    ON f.destination_key = d.destination_key

WHERE d.destination_key IS NULL;

-- Missing order profiles

SELECT COUNT(*) AS missing_order_profiles
FROM gold.fact_order_item f

LEFT JOIN gold.dim_order_profile d
    ON f.order_profile_key = d.order_profile_key

WHERE d.order_profile_key IS NULL;

-- Missing order dates

SELECT COUNT(*) AS missing_order_dates
FROM gold.fact_order_item f

LEFT JOIN gold.dim_date d
    ON f.order_date_key = d.date_key

WHERE d.date_key IS NULL;

-- Missing shipping dates

SELECT COUNT(*) AS missing_shipping_dates
FROM gold.fact_order_item f

LEFT JOIN gold.dim_date d
    ON f.shipping_date_key = d.date_key

WHERE d.date_key IS NULL;

-- Expected for every query above:
--
-- 0

-- =============================================================================
-- 15. TEST COMPLETE STAR SCHEMA
-- =============================================================================

SELECT

    f.order_id,
    f.order_item_id,

    -- CUSTOMER
    c.customer_fname,
    c.customer_lname,
    c.customer_segment,

    -- PRODUCT
    p.product_name,
    p.category_name,
    p.department_name,

    -- DESTINATION
    dest.order_city,
    dest.order_country,
    dest.order_region,
    dest.market,

    -- ORDER PROFILE
    op.type AS payment_type,
    op.order_status,
    op.delivery_status,
    op.shipping_mode,
    op.late_delivery_risk,

    -- DATES
    od.full_date AS order_date,

    sd.full_date AS shipping_date,

    -- MEASURES
    f.order_item_quantity,

    f.sales,
    f.order_item_total,

    f.order_item_discount,

    f.order_profit_per_order,

    f.days_for_shipping_real,
    f.days_for_shipment_scheduled

FROM gold.fact_order_item f

JOIN gold.dim_customer c
    ON f.customer_key = c.customer_key

JOIN gold.dim_product p
    ON f.product_key = p.product_key

JOIN gold.dim_destination dest
    ON f.destination_key = dest.destination_key

JOIN gold.dim_order_profile op
    ON f.order_profile_key = op.order_profile_key

JOIN gold.dim_date od
    ON f.order_date_key = od.date_key

JOIN gold.dim_date sd
    ON f.shipping_date_key = sd.date_key

LIMIT 50;

-- =============================================================================
-- GOLD LAYER COMPLETE
-- =============================================================================
