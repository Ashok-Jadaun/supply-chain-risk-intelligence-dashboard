-- Task 1: Create and select database
CREATE DATABASE IF NOT EXISTS supply_chain_db;
USE supply_chain_db;

-- Task 1b: Staging table — mirrors supply_chain_clean.csv column-for-column
CREATE TABLE staging_orders (
    type                        VARCHAR(50),
    days_for_shipping_real      INT,
    days_for_shipment_scheduled INT,
    benefit_per_order           DECIMAL(12,2),
    sales_per_customer          DECIMAL(12,2),
    delivery_status             VARCHAR(50),
    late_delivery_risk          INT,
    category_id                 INT,
    category_name               VARCHAR(100),
    customer_city               VARCHAR(100),
    customer_country            VARCHAR(100),
    customer_id                 INT,
    customer_segment            VARCHAR(50),
    customer_state              VARCHAR(50),
    customer_zipcode            VARCHAR(20),
    department_id               INT,
    department_name             VARCHAR(100),
    latitude                     DECIMAL(10,6),
    longitude                    DECIMAL(10,6),
    market                      VARCHAR(100),
    order_city                  VARCHAR(100),
    order_country               VARCHAR(100),
    order_customer_id           INT,
    order_date_dateorders       DATETIME,
    order_id                    INT,
    order_item_cardprod_id      INT,
    order_item_discount         DECIMAL(12,2),
    order_item_discount_rate    DECIMAL(6,4),
    order_item_id               INT,
    order_item_product_price    DECIMAL(12,2),
    order_item_profit_ratio     DECIMAL(10,4),
    order_item_quantity         INT,
    sales                       DECIMAL(12,2),
    order_item_total            DECIMAL(12,2),
    order_profit_per_order      DECIMAL(12,2),
    order_region                VARCHAR(100),
    order_state                 VARCHAR(100),
    order_status                VARCHAR(50),
    product_card_id             INT,
    product_category_id         INT,
    product_name                VARCHAR(255),
    product_price               DECIMAL(12,2),
    product_status              INT,
    shipping_date_dateorders    DATETIME,
    shipping_mode               VARCHAR(50),
    lead_time_days              INT,
    late_delivery_flag          TINYINT,
    spend_per_order             DECIMAL(12,2),
    delivery_delay_days         INT,
    order_year                  INT,
    order_month                 INT,
    order_quarter               INT,
    order_weekday               VARCHAR(20),
    vendor_tier                 VARCHAR(50)
);

SHOW VARIABLES LIKE 'secure_file_priv';

-- Task 1c: Load CSV into staging (column order = pandas df.columns order)
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/supply_chain_clean.csv'
INTO TABLE staging_orders
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SET GLOBAL max_allowed_packet = 1073741824;  -- 1GB
SET GLOBAL net_read_timeout = 600;
SET GLOBAL net_write_timeout = 600;

select count(*) from supply_chain_db.staging_orders;

SELECT MIN(order_item_id),
       MAX(order_item_id),
       COUNT(DISTINCT order_item_id),
       COUNT(*)
FROM staging_orders;

-- =============================================================
-- DIMENSION TABLES
-- =============================================================

-- Task 2a: Dimension table — Vendor
CREATE TABLE dim_vendor (
    vendor_id       INT PRIMARY KEY,
    vendor_name     VARCHAR(255),
    vendor_tier     VARCHAR(50),
    country         VARCHAR(100),
    region          VARCHAR(100)
);

-- Task 2b: Dimension table — Product/Category
CREATE TABLE dim_product (
    product_id      INT PRIMARY KEY,
    product_name    VARCHAR(255),
    category_name   VARCHAR(100),
    sub_category    VARCHAR(100)
);

-- Task 2c: Dimension table — Region
CREATE TABLE dim_region (
    region_id       INT PRIMARY KEY,
    region_name     VARCHAR(100),
    country         VARCHAR(100),
    market          VARCHAR(100)
);

-- Task 2d: Dimension table — Date
CREATE TABLE dim_date (
    date_id         DATE PRIMARY KEY,
    year            INT,
    quarter         INT,
    month           INT,
    month_name      VARCHAR(20),
    week            INT
);

-- Task 2e: Fact table — Orders
CREATE TABLE fact_orders (
    order_id            INT,
    order_item_id       INT PRIMARY KEY,
    vendor_id           INT,
    product_id          INT,
    region_id           INT,
    order_date          DATE,
    shipping_date       DATE,
    lead_time_days      INT,
    order_quantity      INT,
    spend_per_order     DECIMAL(12,2),
    late_delivery_flag  TINYINT,
    delivery_status     VARCHAR(50),
    FOREIGN KEY (vendor_id)  REFERENCES dim_vendor(vendor_id),
    FOREIGN KEY (product_id) REFERENCES dim_product(product_id),
    FOREIGN KEY (region_id)  REFERENCES dim_region(region_id),
    FOREIGN KEY (order_date) REFERENCES dim_date(date_id)
);

-- =============================================================
-- POPULATE DIMENSIONS & FACT FROM STAGING
-- =============================================================

-- Task 3a: Populate dim_vendor
/*
INSERT INTO dim_vendor (vendor_id, vendor_name, vendor_tier, country, region)
SELECT DISTINCT order_customer_id, CONCAT('Vendor_', order_customer_id),
       vendor_tier, order_country, order_region
FROM staging_orders;
*/

-- Task 3a: Populate dim_vendor
INSERT INTO dim_vendor
    (vendor_id, vendor_name, vendor_tier, country, region)

SELECT
    order_customer_id AS vendor_id,
    CONCAT('Vendor_', order_customer_id) AS vendor_name,
    MAX(vendor_tier) AS vendor_tier,
    MAX(order_country) AS country,
    MAX(order_region) AS region
FROM staging_orders
GROUP BY order_customer_id;

-- Task X2: Populate dim_product
INSERT INTO dim_product
    (product_id, product_name, category_name, sub_category)

SELECT
    product_card_id AS product_id,
    MAX(product_name) AS product_name,
    MAX(category_name) AS category_name,
    MAX(category_name) AS sub_category
FROM staging_orders
GROUP BY product_card_id;

-- Task X3: Populate dim_region
INSERT INTO dim_region
    (region_id, region_name, country, market)

SELECT
    ROW_NUMBER() OVER (
        ORDER BY order_region, order_country
    ) AS region_id,
    order_region,
    order_country,
    market
FROM (
    SELECT DISTINCT
        order_region,
        order_country,
        market
    FROM staging_orders
) t;

-- Task X4: Populate dim_date
INSERT INTO dim_date
    (date_id, year, quarter, month, month_name, week)

SELECT DISTINCT
    DATE(order_date_dateorders) AS date_id,
    YEAR(order_date_dateorders),
    QUARTER(order_date_dateorders),
    MONTH(order_date_dateorders),
    MONTHNAME(order_date_dateorders),
    WEEK(order_date_dateorders)
FROM staging_orders;

-- Task X5: Populate fact_orders
INSERT INTO fact_orders
    (
        order_id,
        order_item_id,
        vendor_id,
        product_id,
        region_id,
        order_date,
        shipping_date,
        lead_time_days,
        order_quantity,
        spend_per_order,
        late_delivery_flag,
        delivery_status
    )

SELECT
    s.order_id,
    s.order_item_id,
    s.order_customer_id,
    s.product_card_id,
    r.region_id,
    DATE(s.order_date_dateorders),
    DATE(s.shipping_date_dateorders),
    s.lead_time_days,
    s.order_item_quantity,
    s.spend_per_order,
    s.late_delivery_flag,
    s.delivery_status
FROM staging_orders s
JOIN dim_region r
    ON s.order_region = r.region_name
   AND s.order_country = r.country;
   
   SELECT * FROM fact_orders LIMIT 20;
   
-- Adding shipping_mode into facts_orders for dashboard requirement
ALTER TABLE supply_chain_db.fact_orders
ADD COLUMN shipping_mode VARCHAR(50);

UPDATE fact_orders f
JOIN staging_orders s
	ON f.order_item_id =  s.order_item_id
SET f.shipping_mode = s.shipping_mode;

SELECT order_item_id, shipping_mode
FROM supply_chain_db.fact_orders
LIMIT 10;