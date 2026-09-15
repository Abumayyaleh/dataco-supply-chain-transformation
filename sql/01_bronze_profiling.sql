-- =============================================================================
-- DATACO SUPPLY CHAIN — BRONZE DATA PROFILING
-- Source: DataCoSupplyChainDataset.csv
-- Table: bronze.dataco_supply_chain_raw
--
-- Purpose:
--   1. Validate row count and grain
--   2. Check duplicates
--   3. Inspect NULLs and constant columns
--   4. Validate key relationships
--   5. Inspect categorical values
--   6. Profile numeric fields
--   7. Review date fields
--   8. Document cleaning decisions before building Silver
-- =============================================================================

-- =============================================================================
-- 0. RAW STAGING SETUP
-- Run this section first, then import the CSV before running section 1 onward.
-- Import instructions: data/README.md. All source columns are staged as TEXT.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS bronze;

CREATE TABLE IF NOT EXISTS bronze.dataco_supply_chain_raw (
    type TEXT,
    days_for_shipping_real TEXT,
    days_for_shipment_scheduled TEXT,
    benefit_per_order TEXT,
    sales_per_customer TEXT,
    delivery_status TEXT,
    late_delivery_risk TEXT,
    category_id TEXT,
    category_name TEXT,
    customer_city TEXT,
    customer_country TEXT,
    customer_email TEXT,
    customer_fname TEXT,
    customer_id TEXT,
    customer_lname TEXT,
    customer_password TEXT,
    customer_segment TEXT,
    customer_state TEXT,
    customer_street TEXT,
    customer_zipcode TEXT,
    department_id TEXT,
    department_name TEXT,
    latitude TEXT,
    longitude TEXT,
    market TEXT,
    order_city TEXT,
    order_country TEXT,
    order_customer_id TEXT,
    order_date TEXT,
    order_id TEXT,
    order_item_cardprod_id TEXT,
    order_item_discount TEXT,
    order_item_discount_rate TEXT,
    order_item_id TEXT,
    order_item_product_price TEXT,
    order_item_profit_ratio TEXT,
    order_item_quantity TEXT,
    sales TEXT,
    order_item_total TEXT,
    order_profit_per_order TEXT,
    order_region TEXT,
    order_state TEXT,
    order_status TEXT,
    order_zipcode TEXT,
    product_card_id TEXT,
    product_category_id TEXT,
    product_description TEXT,
    product_image TEXT,
    product_name TEXT,
    product_price TEXT,
    product_status TEXT,
    shipping_date TEXT,
    shipping_mode TEXT
);

-- =============================================================================
-- 1. BASIC ROW COUNT
-- =============================================================================

SELECT
    COUNT(*) AS total_rows
FROM bronze.dataco_supply_chain_raw;

-- Expected:
-- 180,519 rows

-- =============================================================================
-- 2. VALIDATE FACT GRAIN
-- Proposed grain: one row per Order Item ID
-- =============================================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_item_id) AS distinct_order_items
FROM bronze.dataco_supply_chain_raw;

-- Result:
-- total_rows           = 180,519
-- distinct_order_items = 180,519
--
-- Conclusion:
-- Order Item ID is unique.
-- Grain is confirmed as one row per order item.

-- Check for duplicate Order Item IDs

SELECT
    order_item_id,
    COUNT(*) AS duplicate_count
FROM bronze.dataco_supply_chain_raw
GROUP BY order_item_id
HAVING COUNT(*) > 1;

-- Expected:
-- 0 rows

-- =============================================================================
-- 3. CHECK ORDER-LEVEL COUNTS
-- =============================================================================

SELECT
    COUNT(DISTINCT order_id) AS distinct_orders
FROM bronze.dataco_supply_chain_raw;

-- Used later to compare:
-- order count vs order-item count

-- =============================================================================
-- 4. VALIDATE DUPLICATE SOURCE IDs
-- =============================================================================

-- Customer ID should match Order Customer ID

SELECT
    COUNT(*) AS mismatched_customer_ids
FROM bronze.dataco_supply_chain_raw
WHERE customer_id <> order_customer_id;

-- Expected:
-- 0

-- Product Card ID should match Order Item Card Product ID

SELECT
    COUNT(*) AS mismatched_product_ids
FROM bronze.dataco_supply_chain_raw
WHERE product_card_id <> order_item_cardprod_id;

-- Expected:
-- 0

-- =============================================================================
-- 5. NULL PROFILING
-- =============================================================================

-- Order Zipcode has a large number of NULL values

SELECT
    COUNT(*) AS total_rows,
    COUNT(order_zipcode) AS non_null_rows,
    COUNT(*) - COUNT(order_zipcode) AS null_rows,
    ROUND(
        100.0 * (COUNT(*) - COUNT(order_zipcode)) / COUNT(*),
        2
    ) AS null_percentage
FROM bronze.dataco_supply_chain_raw;

-- Result:
-- non_null_rows ≈ 24,840
-- null_rows     ≈ 155,679
-- null %        ≈ 86.2%
--
-- Decision:
-- Drop order_zipcode from Silver because most values are missing
-- and other geographic fields are available.

-- Product Description NULL check

SELECT
    COUNT(*) AS total_rows,
    COUNT(product_description) AS non_null_rows
FROM bronze.dataco_supply_chain_raw;

-- Decision:
-- Drop if all values are NULL.

-- =============================================================================
-- 6. CONSTANT COLUMN CHECKS
-- =============================================================================

SELECT
    product_status,
    COUNT(*) AS row_count
FROM bronze.dataco_supply_chain_raw
GROUP BY product_status;

-- Result:
-- All rows contain 0
--
-- Decision:
-- Drop product_status from Silver because it carries no analytical value.

-- =============================================================================
-- 7. USELESS / NON-ANALYTICAL COLUMNS
-- =============================================================================

-- Customer Email inspection

SELECT DISTINCT customer_email
FROM bronze.dataco_supply_chain_raw
LIMIT 20;

-- Observation:
-- Email is masked / unusable.
--
-- Decision:
-- Drop customer_email.

-- Customer Password presence check (never display values)

SELECT COUNT(customer_password) AS populated_password_rows
FROM bronze.dataco_supply_chain_raw;

-- Decision:
-- Drop customer_password.
-- It is sensitive and provides no analytical value.

-- Product Image inspection

SELECT DISTINCT product_image
FROM bronze.dataco_supply_chain_raw
LIMIT 20;

-- Decision:
-- Drop product_image from analytical model.

-- =============================================================================
-- 8. CATEGORICAL DATA PROFILING
-- =============================================================================

-- Delivery Status

SELECT
    delivery_status,
    COUNT(*) AS row_count
FROM bronze.dataco_supply_chain_raw
GROUP BY delivery_status
ORDER BY row_count DESC;

-- Late Delivery Risk

SELECT
    late_delivery_risk,
    COUNT(*) AS row_count
FROM bronze.dataco_supply_chain_raw
GROUP BY late_delivery_risk
ORDER BY late_delivery_risk;

-- Customer Segment

SELECT
    customer_segment,
    COUNT(*) AS row_count
FROM bronze.dataco_supply_chain_raw
GROUP BY customer_segment
ORDER BY row_count DESC;

-- Market

SELECT
    market,
    COUNT(*) AS row_count
FROM bronze.dataco_supply_chain_raw
GROUP BY market
ORDER BY row_count DESC;

-- Order Status

SELECT
    order_status,
    COUNT(*) AS row_count
FROM bronze.dataco_supply_chain_raw
GROUP BY order_status
ORDER BY row_count DESC;

-- Shipping Mode

SELECT
    shipping_mode,
    COUNT(*) AS row_count
FROM bronze.dataco_supply_chain_raw
GROUP BY shipping_mode
ORDER BY row_count DESC;

-- Payment Type

SELECT
    type,
    COUNT(*) AS row_count
FROM bronze.dataco_supply_chain_raw
GROUP BY type
ORDER BY row_count DESC;

-- =============================================================================
-- 9. CUSTOMER DATA PROFILING
-- =============================================================================

-- Customer count

SELECT
    COUNT(DISTINCT customer_id) AS distinct_customers
FROM bronze.dataco_supply_chain_raw;

-- Check whether a Customer ID maps to multiple names

SELECT
    customer_id,
    COUNT(DISTINCT CONCAT(customer_fname, '|', customer_lname)) AS name_versions
FROM bronze.dataco_supply_chain_raw
GROUP BY customer_id
HAVING COUNT(DISTINCT CONCAT(customer_fname, '|', customer_lname)) > 1;

-- If rows appear here, customer attributes require further investigation.

-- Check whether customer location changes for the same customer

SELECT
    customer_id,
    COUNT(
        DISTINCT CONCAT(
            customer_city, '|',
            customer_state, '|',
            customer_country
        )
    ) AS location_versions
FROM bronze.dataco_supply_chain_raw
GROUP BY customer_id
HAVING COUNT(
    DISTINCT CONCAT(
        customer_city, '|',
        customer_state, '|',
        customer_country
    )
) > 1;

-- Useful before building DimCustomer.

-- =============================================================================
-- 10. PRODUCT DATA PROFILING
-- =============================================================================

-- Distinct products

SELECT
    COUNT(DISTINCT product_card_id) AS distinct_products
FROM bronze.dataco_supply_chain_raw;

-- Validate Product ID -> Product Name

SELECT
    product_card_id,
    COUNT(DISTINCT product_name) AS product_name_versions
FROM bronze.dataco_supply_chain_raw
GROUP BY product_card_id
HAVING COUNT(DISTINCT product_name) > 1;

-- Validate Product -> Category relationship

SELECT
    product_card_id,
    COUNT(DISTINCT product_category_id) AS category_versions
FROM bronze.dataco_supply_chain_raw
GROUP BY product_card_id
HAVING COUNT(DISTINCT product_category_id) > 1;

-- Validate Category ID -> Category Name

SELECT
    category_id,
    COUNT(DISTINCT category_name) AS category_name_versions
FROM bronze.dataco_supply_chain_raw
GROUP BY category_id
HAVING COUNT(DISTINCT category_name) > 1;

-- Validate Department ID -> Department Name

SELECT
    department_id,
    COUNT(DISTINCT department_name) AS department_name_versions
FROM bronze.dataco_supply_chain_raw
GROUP BY department_id
HAVING COUNT(DISTINCT department_name) > 1;

-- =============================================================================
-- 11. NUMERIC RANGE PROFILING
-- Bronze stores values as TEXT, so cast them for inspection.
-- =============================================================================

SELECT
    MIN(days_for_shipping_real::NUMERIC) AS min_shipping_days,
    MAX(days_for_shipping_real::NUMERIC) AS max_shipping_days,
    AVG(days_for_shipping_real::NUMERIC) AS avg_shipping_days
FROM bronze.dataco_supply_chain_raw;

SELECT
    MIN(days_for_shipment_scheduled::NUMERIC) AS min_scheduled_days,
    MAX(days_for_shipment_scheduled::NUMERIC) AS max_scheduled_days,
    AVG(days_for_shipment_scheduled::NUMERIC) AS avg_scheduled_days
FROM bronze.dataco_supply_chain_raw;

SELECT
    MIN(benefit_per_order::NUMERIC) AS min_benefit,
    MAX(benefit_per_order::NUMERIC) AS max_benefit,
    AVG(benefit_per_order::NUMERIC) AS avg_benefit
FROM bronze.dataco_supply_chain_raw;

SELECT
    MIN(sales::NUMERIC) AS min_sales,
    MAX(sales::NUMERIC) AS max_sales,
    AVG(sales::NUMERIC) AS avg_sales
FROM bronze.dataco_supply_chain_raw;

SELECT
    MIN(order_item_total::NUMERIC) AS min_order_item_total,
    MAX(order_item_total::NUMERIC) AS max_order_item_total,
    AVG(order_item_total::NUMERIC) AS avg_order_item_total
FROM bronze.dataco_supply_chain_raw;

SELECT
    MIN(order_profit_per_order::NUMERIC) AS min_order_profit,
    MAX(order_profit_per_order::NUMERIC) AS max_order_profit,
    AVG(order_profit_per_order::NUMERIC) AS avg_order_profit
FROM bronze.dataco_supply_chain_raw;

SELECT
    MIN(order_item_quantity::NUMERIC) AS min_quantity,
    MAX(order_item_quantity::NUMERIC) AS max_quantity,
    AVG(order_item_quantity::NUMERIC) AS avg_quantity
FROM bronze.dataco_supply_chain_raw;

SELECT
    MIN(order_item_discount_rate::NUMERIC) AS min_discount_rate,
    MAX(order_item_discount_rate::NUMERIC) AS max_discount_rate
FROM bronze.dataco_supply_chain_raw;

SELECT
    MIN(order_item_profit_ratio::NUMERIC) AS min_profit_ratio,
    MAX(order_item_profit_ratio::NUMERIC) AS max_profit_ratio
FROM bronze.dataco_supply_chain_raw;

-- =============================================================================
-- 12. CHECK FOR NEGATIVE / ZERO VALUES
-- =============================================================================

SELECT
    COUNT(*) AS negative_profit_rows
FROM bronze.dataco_supply_chain_raw
WHERE order_profit_per_order::NUMERIC < 0;

SELECT
    COUNT(*) AS zero_quantity_rows
FROM bronze.dataco_supply_chain_raw
WHERE order_item_quantity::NUMERIC = 0;

SELECT
    COUNT(*) AS negative_quantity_rows
FROM bronze.dataco_supply_chain_raw
WHERE order_item_quantity::NUMERIC < 0;

SELECT
    COUNT(*) AS negative_sales_rows
FROM bronze.dataco_supply_chain_raw
WHERE sales::NUMERIC < 0;

-- =============================================================================
-- 13. CHECK COMMERCIAL FIELD RELATIONSHIPS
-- Important because DataCo contains several similar financial columns.
-- =============================================================================

SELECT
    sales,
    sales_per_customer,
    order_item_total,
    benefit_per_order,
    order_profit_per_order
FROM bronze.dataco_supply_chain_raw
LIMIT 50;

-- Purpose:
-- Compare similar fields before deciding which measures belong in FactOrderItem.

-- Compare Sales vs Order Item Total

SELECT
    COUNT(*) AS different_rows
FROM bronze.dataco_supply_chain_raw
WHERE ROUND(sales::NUMERIC, 2)
   <> ROUND(order_item_total::NUMERIC, 2);

-- Do not assume these measures mean the same thing.

-- Compare Benefit Per Order vs Order Profit Per Order

SELECT
    COUNT(*) AS different_rows
FROM bronze.dataco_supply_chain_raw
WHERE ROUND(benefit_per_order::NUMERIC, 2)
   <> ROUND(order_profit_per_order::NUMERIC, 2);

-- =============================================================================
-- 14. DATE PROFILING
-- =============================================================================

SELECT
    order_date,
    shipping_date
FROM bronze.dataco_supply_chain_raw
LIMIT 20;

-- Observation:
-- Both contain date and time information.
--
-- Decision:
-- Keep timestamps in Silver.
-- Derive DateKey later in Gold.

-- Earliest and latest order dates
-- Parse source timestamps before comparing chronological ranges.

SELECT
    MIN(TO_TIMESTAMP(NULLIF(TRIM(order_date), ''), 'MM/DD/YYYY HH24:MI')) AS earliest_order_date_raw,
    MAX(TO_TIMESTAMP(NULLIF(TRIM(order_date), ''), 'MM/DD/YYYY HH24:MI')) AS latest_order_date_raw
FROM bronze.dataco_supply_chain_raw;

SELECT
    MIN(TO_TIMESTAMP(NULLIF(TRIM(shipping_date), ''), 'MM/DD/YYYY HH24:MI')) AS earliest_shipping_date_raw,
    MAX(TO_TIMESTAMP(NULLIF(TRIM(shipping_date), ''), 'MM/DD/YYYY HH24:MI')) AS latest_shipping_date_raw
FROM bronze.dataco_supply_chain_raw;

-- =============================================================================
-- 15. TEXT CLEANING REVIEW
-- =============================================================================

-- Check possible leading/trailing spaces

SELECT
    COUNT(*) AS product_names_with_spaces
FROM bronze.dataco_supply_chain_raw
WHERE product_name <> TRIM(product_name);

SELECT
    COUNT(*) AS customer_first_names_with_spaces
FROM bronze.dataco_supply_chain_raw
WHERE customer_fname <> TRIM(customer_fname);

SELECT
    COUNT(*) AS customer_last_names_with_spaces
FROM bronze.dataco_supply_chain_raw
WHERE customer_lname <> TRIM(customer_lname);

SELECT
    COUNT(*) AS order_status_with_spaces
FROM bronze.dataco_supply_chain_raw
WHERE order_status <> TRIM(order_status);

-- =============================================================================
-- 16. FINAL BRONZE PROFILING DECISIONS
-- =============================================================================

-- DROP FROM SILVER:
--   customer_email
--   customer_password
--   order_zipcode
--   product_description
--   product_image
--   product_status
--
-- REASONS:
--   customer_email      -> masked / analytically useless
--   customer_password   -> sensitive and unnecessary
--   order_zipcode       -> ~86.2% NULL
--   product_description -> all NULL
--   product_image       -> no analytical value
--   product_status      -> constant value 0
--
--
-- CLEAN / STANDARDIZE:
--   TRIM text columns
--   Standardize casing where appropriate
--   Convert IDs to INTEGER
--   Convert quantity/shipping-day fields to INTEGER
--   Convert financial fields to NUMERIC
--   Round financial outputs where appropriate
--   Convert coordinates to NUMERIC
--   Convert order_date and shipping_date to TIMESTAMP
--
--
-- KEEP TIMESTAMP INFORMATION:
--   order_date
--   shipping_date
--
-- Date-only keys will be created later in Gold.
--
--
-- CONFIRMED FACT GRAIN:
--   One row per order_item_id
--
-- Total rows:           180,519
-- Distinct Order Items: 180,519
--
-- =============================================================================
