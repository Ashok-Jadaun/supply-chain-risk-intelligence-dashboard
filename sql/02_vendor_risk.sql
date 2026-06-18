USE supply_chain_db;

-- Task 1: Create vendor_risk_scores table (receives Python Stage 3 output)
CREATE TABLE vendor_risk_scores (
    vendor                   INT,
    avg_lead_time            DECIMAL(10,2),
    lead_time_std            DECIMAL(10,2),
    lead_time_variance_score DECIMAL(10,6),
    late_delivery_rate       DECIMAL(10,6),
    composite_risk_score     DECIMAL(10,6),
    risk_band                VARCHAR(20)
);

-- Task 2:Load CSV
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/vendor_risk_scores.csv'
INTO TABLE vendor_risk_scores
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- Verify
SELECT COUNT(*) FROM vendor_risk_scores;
SELECT risk_band, COUNT(*) FROM vendor_risk_scores GROUP BY risk_band;

-- Task 3: Vendor spend aggregation
CREATE VIEW vw_vendor_spend AS
SELECT
    v.vendor_id, v.vendor_name, v.vendor_tier,
    COUNT(f.order_item_id)   AS total_orders,
    SUM(f.spend_per_order)   AS total_spend,
    AVG(f.spend_per_order)   AS avg_spend_per_order,
    SUM(f.order_quantity)    AS total_units_ordered
FROM fact_orders f
JOIN dim_vendor v ON f.vendor_id = v.vendor_id
GROUP BY v.vendor_id, v.vendor_name, v.vendor_tier;


-- Task 4: Lead time statistics per vendor
CREATE VIEW vw_vendor_lead_time AS
SELECT
    v.vendor_id, v.vendor_name,
    COUNT(f.order_item_id)           AS order_count,
    ROUND(AVG(f.lead_time_days), 2)  AS avg_lead_time,
    ROUND(STD(f.lead_time_days), 2)  AS std_lead_time,
    MIN(f.lead_time_days)            AS min_lead_time,
    MAX(f.lead_time_days)            AS max_lead_time
FROM fact_orders f
JOIN dim_vendor v ON f.vendor_id = v.vendor_id
GROUP BY v.vendor_id, v.vendor_name;


-- Task 5: Late delivery rate per vendor
CREATE VIEW vw_vendor_late_rate AS
SELECT
    v.vendor_id, v.vendor_name,
    COUNT(f.order_item_id)                     AS total_orders,
    SUM(f.late_delivery_flag)                  AS late_orders,
    ROUND(AVG(f.late_delivery_flag) * 100, 2)  AS late_delivery_rate_pct
FROM fact_orders f
JOIN dim_vendor v ON f.vendor_id = v.vendor_id
GROUP BY v.vendor_id, v.vendor_name;


-- Task 7: HHI input — vendor market share per category
CREATE VIEW vw_category_hhi AS
WITH vendor_category_spend AS (
    SELECT p.category_name, f.vendor_id,
           SUM(f.spend_per_order) AS vendor_spend
    FROM fact_orders f
    JOIN dim_product p ON f.product_id = p.product_id
    GROUP BY p.category_name, f.vendor_id
),
category_totals AS (
    SELECT category_name, SUM(vendor_spend) AS category_total
    FROM vendor_category_spend
    GROUP BY category_name
)
SELECT
    vcs.category_name, vcs.vendor_id,
    ROUND(vcs.vendor_spend, 2)                              AS vendor_spend,
    ROUND(vcs.vendor_spend / ct.category_total, 4)          AS market_share,
    ROUND(POW(vcs.vendor_spend / ct.category_total, 2), 4)  AS share_squared
FROM vendor_category_spend vcs
JOIN category_totals ct ON vcs.category_name = ct.category_name;


-- HHI score + concentration band per category
CREATE VIEW vw_hhi_by_category AS
SELECT
    category_name,
    ROUND(SUM(share_squared), 4) AS hhi_score,
    COUNT(vendor_id)              AS vendor_count,
    CASE
        WHEN SUM(share_squared) >= 0.75 THEN 'Critical'
        WHEN SUM(share_squared) >= 0.50 THEN 'High'
        WHEN SUM(share_squared) >= 0.25 THEN 'Medium'
        ELSE 'Low'
    END AS concentration_band
FROM vw_category_hhi
GROUP BY category_name;

-- Late Delivery Rate % by shipping mode
select * from supply_chain_db.fact_orders where shipping_mode = 'First Class' limit 10;

select shipping_mode,
	count(*) as total_orders,
    sum(late_delivery_flag) as late_orders,
    round(100 * sum(late_delivery_flag)/count(*), 2) as Late_delivery_rate
from supply_chain_db.fact_orders
group by shipping_mode
order by late_delivery_rate desc;