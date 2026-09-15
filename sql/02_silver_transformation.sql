-- =============================================================================
-- DATACO SUPPLY CHAIN — SILVER LAYER
-- Source: bronze.dataco_supply_chain_raw
-- Target: silver.dataco_supply_chain_clean
--
-- Purpose:
--   1. Remove analytically useless / sensitive columns
--   2. Convert TEXT fields to appropriate data types
--   3. Trim text values
--   4. Standardize casing where appropriate
--   5. Round financial values
--   6. Preserve timestamps
--   7. Keep the validated grain: one row per Order Item ID
--
-- Grain:
--   One row per order_item_id
-- =============================================================================

-- =============================================================================
-- 1. CREATE SILVER SCHEMA
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS silver;

-- =============================================================================
-- 2. DROP OLD SILVER TABLE
-- Allows the transformation to be rerun during development.
-- =============================================================================

DROP TABLE IF EXISTS silver.dataco_supply_chain_clean;

-- =============================================================================
-- 3. CREATE CLEAN SILVER TABLE
-- =============================================================================

CREATE TABLE silver.dataco_supply_chain_clean (

    -- -------------------------------------------------------------------------
    -- ORDER / PAYMENT PROFILE
    -- -------------------------------------------------------------------------

    type VARCHAR(50),

    days_for_shipping_real INTEGER,
    days_for_shipment_scheduled INTEGER,

    benefit_per_order NUMERIC(12,2),
    sales_per_customer NUMERIC(12,2),

    delivery_status VARCHAR(50),
    late_delivery_risk SMALLINT,

    -- -------------------------------------------------------------------------
    -- CATEGORY
    -- -------------------------------------------------------------------------

    category_id INTEGER,
    category_name VARCHAR(150),

    -- -------------------------------------------------------------------------
    -- CUSTOMER
    -- -------------------------------------------------------------------------

    customer_city VARCHAR(150),
    customer_country VARCHAR(100),

    customer_fname VARCHAR(100),
    customer_id INTEGER,
    customer_lname VARCHAR(100),

    customer_segment VARCHAR(100),
    customer_state VARCHAR(100),
    customer_street VARCHAR(255),
    customer_zipcode VARCHAR(30),

    -- -------------------------------------------------------------------------
    -- DEPARTMENT
    -- -------------------------------------------------------------------------

    department_id INTEGER,
    department_name VARCHAR(150),

    -- -------------------------------------------------------------------------
    -- CUSTOMER LOCATION
    -- -------------------------------------------------------------------------

    latitude NUMERIC(10,6),
    longitude NUMERIC(10,6),

    -- -------------------------------------------------------------------------
    -- MARKET
    -- -------------------------------------------------------------------------

    market VARCHAR(100),

    -- -------------------------------------------------------------------------
    -- ORDER
    -- -------------------------------------------------------------------------

    order_city VARCHAR(150),
    order_country VARCHAR(100),

    order_customer_id INTEGER,

    order_timestamp TIMESTAMP,

    order_id INTEGER,

    order_item_cardprod_id INTEGER,

    order_item_discount NUMERIC(12,2),
    order_item_discount_rate NUMERIC(8,4),

    order_item_id INTEGER,

    order_item_product_price NUMERIC(12,2),
    order_item_profit_ratio NUMERIC(8,4),

    order_item_quantity INTEGER,

    sales NUMERIC(12,2),
    order_item_total NUMERIC(12,2),
    order_profit_per_order NUMERIC(12,2),

    order_region VARCHAR(150),
    order_state VARCHAR(150),
    order_status VARCHAR(100),

    -- -------------------------------------------------------------------------
    -- PRODUCT
    -- -------------------------------------------------------------------------

    product_card_id INTEGER,
    product_category_id INTEGER,

    product_name VARCHAR(255),
    product_price NUMERIC(12,2),

    -- -------------------------------------------------------------------------
    -- SHIPPING
    -- -------------------------------------------------------------------------

    shipping_timestamp TIMESTAMP,
    shipping_mode VARCHAR(100),

    -- -------------------------------------------------------------------------
    -- CONSTRAINT
    -- -------------------------------------------------------------------------

    CONSTRAINT pk_silver_order_item
        PRIMARY KEY (order_item_id)
);

-- =============================================================================
-- 4. LOAD CLEAN DATA FROM BRONZE
-- =============================================================================

INSERT INTO silver.dataco_supply_chain_clean (

    type,

    days_for_shipping_real,
    days_for_shipment_scheduled,

    benefit_per_order,
    sales_per_customer,

    delivery_status,
    late_delivery_risk,

    category_id,
    category_name,

    customer_city,
    customer_country,
    customer_fname,
    customer_id,
    customer_lname,
    customer_segment,
    customer_state,
    customer_street,
    customer_zipcode,

    department_id,
    department_name,

    latitude,
    longitude,

    market,

    order_city,
    order_country,
    order_customer_id,
    order_timestamp,
    order_id,

    order_item_cardprod_id,
    order_item_discount,
    order_item_discount_rate,
    order_item_id,
    order_item_product_price,
    order_item_profit_ratio,
    order_item_quantity,

    sales,
    order_item_total,
    order_profit_per_order,

    order_region,
    order_state,
    order_status,

    product_card_id,
    product_category_id,
    product_name,
    product_price,

    shipping_timestamp,
    shipping_mode

)

SELECT

    -- =========================================================================
    -- PAYMENT TYPE
    -- Example:
    -- DEBIT -> Debit
    -- CASH  -> Cash
    -- =========================================================================

    INITCAP(TRIM(type)) AS type,

    -- =========================================================================
    -- SHIPPING DAYS
    -- Convert raw TEXT to INTEGER.
    -- =========================================================================

    NULLIF(TRIM(days_for_shipping_real), '')::INTEGER
        AS days_for_shipping_real,

    NULLIF(TRIM(days_for_shipment_scheduled), '')::INTEGER
        AS days_for_shipment_scheduled,

    -- =========================================================================
    -- FINANCIAL VALUES
    -- Convert to NUMERIC and round to 2 decimal places.
    -- =========================================================================

    ROUND(
        NULLIF(TRIM(benefit_per_order), '')::NUMERIC,
        2
    ) AS benefit_per_order,

    ROUND(
        NULLIF(TRIM(sales_per_customer), '')::NUMERIC,
        2
    ) AS sales_per_customer,

    -- =========================================================================
    -- DELIVERY
    -- Standardize descriptive casing.
    -- =========================================================================

    INITCAP(TRIM(delivery_status))
        AS delivery_status,

    NULLIF(TRIM(late_delivery_risk), '')::SMALLINT
        AS late_delivery_risk,

    -- =========================================================================
    -- CATEGORY
    -- =========================================================================

    NULLIF(TRIM(category_id), '')::INTEGER
        AS category_id,

    INITCAP(TRIM(category_name))
        AS category_name,

    -- =========================================================================
    -- CUSTOMER
    -- INITCAP used where proper-name formatting makes sense.
    -- =========================================================================

    INITCAP(TRIM(customer_city))
        AS customer_city,

    INITCAP(TRIM(customer_country))
        AS customer_country,

    INITCAP(TRIM(customer_fname))
        AS customer_fname,

    NULLIF(TRIM(customer_id), '')::INTEGER
        AS customer_id,

    INITCAP(TRIM(customer_lname))
        AS customer_lname,

    INITCAP(TRIM(customer_segment))
        AS customer_segment,

    -- Customer State may contain abbreviations such as CA / NY / PR.
    -- Do NOT INITCAP because:
    -- CA -> Ca
    -- PR -> Pr

    UPPER(TRIM(customer_state))
        AS customer_state,

    -- Street kept in original capitalization to avoid damaging addresses.

    TRIM(customer_street)
        AS customer_street,

    -- Zipcode kept as text because postal codes are identifiers,
    -- not numerical measures.

    NULLIF(TRIM(customer_zipcode), '')
        AS customer_zipcode,

    -- =========================================================================
    -- DEPARTMENT
    -- =========================================================================

    NULLIF(TRIM(department_id), '')::INTEGER
        AS department_id,

    INITCAP(TRIM(department_name))
        AS department_name,

    -- =========================================================================
    -- COORDINATES
    -- =========================================================================

    NULLIF(TRIM(latitude), '')::NUMERIC(10,6)
        AS latitude,

    NULLIF(TRIM(longitude), '')::NUMERIC(10,6)
        AS longitude,

    -- =========================================================================
    -- MARKET
    --
    -- Do not INITCAP because values may include abbreviations such as:
    -- LATAM
    -- USCA
    -- =========================================================================

    TRIM(market)
        AS market,

    -- =========================================================================
    -- ORDER DESTINATION
    -- =========================================================================

    INITCAP(TRIM(order_city))
        AS order_city,

    INITCAP(TRIM(order_country))
        AS order_country,

    NULLIF(TRIM(order_customer_id), '')::INTEGER
        AS order_customer_id,

    -- =========================================================================
    -- ORDER DATE
    --
    -- Keep complete timestamp in Silver.
    -- DateKey will be created later in Gold.
    --
    -- DataCo format:
    -- MM/DD/YYYY HH24:MI
    -- =========================================================================

    TO_TIMESTAMP(
        TRIM(order_date),
        'MM/DD/YYYY HH24:MI'
    ) AS order_timestamp,

    -- =========================================================================
    -- ORDER IDS
    -- =========================================================================

    NULLIF(TRIM(order_id), '')::INTEGER
        AS order_id,

    NULLIF(TRIM(order_item_cardprod_id), '')::INTEGER
        AS order_item_cardprod_id,

    -- =========================================================================
    -- ORDER ITEM FINANCIALS
    -- =========================================================================

    ROUND(
        NULLIF(TRIM(order_item_discount), '')::NUMERIC,
        2
    ) AS order_item_discount,

    -- Keep additional decimal precision for rates.
    -- Example: 0.1500 represents 15%.

    ROUND(
        NULLIF(TRIM(order_item_discount_rate), '')::NUMERIC,
        4
    ) AS order_item_discount_rate,

    -- =========================================================================
    -- ORDER ITEM PRIMARY KEY
    -- Bronze profiling confirmed uniqueness.
    -- =========================================================================

    NULLIF(TRIM(order_item_id), '')::INTEGER
        AS order_item_id,

    ROUND(
        NULLIF(TRIM(order_item_product_price), '')::NUMERIC,
        2
    ) AS order_item_product_price,

    ROUND(
        NULLIF(TRIM(order_item_profit_ratio), '')::NUMERIC,
        4
    ) AS order_item_profit_ratio,

    NULLIF(TRIM(order_item_quantity), '')::INTEGER
        AS order_item_quantity,

    ROUND(
        NULLIF(TRIM(sales), '')::NUMERIC,
        2
    ) AS sales,

    ROUND(
        NULLIF(TRIM(order_item_total), '')::NUMERIC,
        2
    ) AS order_item_total,

    ROUND(
        NULLIF(TRIM(order_profit_per_order), '')::NUMERIC,
        2
    ) AS order_profit_per_order,

    -- =========================================================================
    -- ORDER GEOGRAPHY
    --
    -- Keep region largely as provided because it can contain abbreviations
    -- or business-specific labels.
    -- =========================================================================

    TRIM(order_region)
        AS order_region,

    INITCAP(TRIM(order_state))
        AS order_state,

    -- =========================================================================
    -- ORDER STATUS
    --
    -- Standardize casing and replace underscores with spaces.
    -- Examples:
    -- COMPLETE         -> Complete
    -- PENDING_PAYMENT  -> Pending Payment
    -- ON_HOLD          -> On Hold
    -- SUSPECTED_FRAUD  -> Suspected Fraud
    -- =========================================================================

    INITCAP(
        REPLACE(
            TRIM(order_status),
            '_',
            ' '
        )
    ) AS order_status,

    -- =========================================================================
    -- PRODUCT
    -- =========================================================================

    NULLIF(TRIM(product_card_id), '')::INTEGER
        AS product_card_id,

    NULLIF(TRIM(product_category_id), '')::INTEGER
        AS product_category_id,

    -- Do not INITCAP product names.
    -- Brand/product capitalization should be preserved.

    TRIM(product_name)
        AS product_name,

    ROUND(
        NULLIF(TRIM(product_price), '')::NUMERIC,
        2
    ) AS product_price,

    -- =========================================================================
    -- SHIPPING DATE
    -- Preserve timestamp.
    -- =========================================================================

    TO_TIMESTAMP(
        TRIM(shipping_date),
        'MM/DD/YYYY HH24:MI'
    ) AS shipping_timestamp,

    INITCAP(TRIM(shipping_mode))
        AS shipping_mode

FROM bronze.dataco_supply_chain_raw;
