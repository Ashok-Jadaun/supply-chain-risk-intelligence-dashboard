USE supply_chain_db;

-- =============================================================
-- STAGE 4 IMPORTS — run before any reporting views
-- =============================================================

-- task 1: Create monte_carlo_results table
CREATE TABLE monte_carlo_results (
    vendor               INT,
    category             VARCHAR(100),
    market_share         DECIMAL(10,4),
    avg_lead_time        DECIMAL(10,2),
    lead_time_std        DECIMAL(10,2),
    breach_threshold     DECIMAL(10,2),
    breach_probability   DECIMAL(10,4),
    spend_at_risk        DECIMAL(14,2),
    disruption_exposure  DECIMAL(14,4)
);

-- Task 2: Load Data into monte_carlo_results
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/monte_carlo_results.csv'
INTO TABLE monte_carlo_results
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS monte_carlo_rows FROM monte_carlo_results;

-- Task 3: Create top12_dual_sourcing table
CREATE TABLE top12_dual_sourcing (
    vendor                       INT,
    category                     VARCHAR(100),
    market_share                 DECIMAL(10,4),
    avg_lead_time                DECIMAL(10,2),
    lead_time_std                DECIMAL(10,2),
    breach_threshold             DECIMAL(10,2),
    breach_probability           DECIMAL(10,4),
    spend_at_risk                DECIMAL(14,2),
    disruption_exposure          DECIMAL(14,4),
    rank_order                   INT,
    recommendation               VARCHAR(100),
    projected_risk_reduction_pct DECIMAL(5,1)
);

-- Task 4: Load Data into top12_dual_sourcing table
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/top12_dual_sourcing.csv'
INTO TABLE top12_dual_sourcing
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- verifu results
SELECT COUNT(*) AS top12_rows FROM top12_dual_sourcing;
SELECT * FROM top12_dual_sourcing ORDER BY rank_order;

-- Task 5: Dominant vendor per category = top vendor by spend share
-- Consistent with Python simulation_targets definition
CREATE VIEW vw_single_source AS
WITH ranked_vendors AS (
    SELECT
        category_name,
        vendor_id,
        vendor_spend,
        market_share,
        ROW_NUMBER() OVER (
            PARTITION BY category_name
            ORDER BY market_share DESC
        ) AS spend_rank
    FROM vw_category_hhi
)
SELECT
    r.category_name,
    r.vendor_id         AS sole_vendor_id,
    r.market_share,
    r.vendor_spend      AS category_spend,
    h.vendor_count
FROM ranked_vendors r
JOIN vw_hhi_by_category h ON r.category_name = h.category_name
WHERE r.spend_rank = 1;


-- Task 6: Disruption exposure — joins dominant vendor with lead time and late rate
CREATE VIEW vw_disruption_exposure AS
SELECT
    ss.category_name,
    ss.sole_vendor_id        AS vendor_id,
    v.vendor_name,
    v.vendor_tier,
    ss.market_share,
    ss.category_spend        AS spend_at_risk,
    lt.avg_lead_time,
    lt.std_lead_time,
    lr.late_delivery_rate_pct,
    h.hhi_score,
    h.concentration_band
FROM vw_single_source ss
JOIN dim_vendor v            ON ss.sole_vendor_id = v.vendor_id
JOIN vw_vendor_lead_time lt  ON ss.sole_vendor_id = lt.vendor_id
JOIN vw_vendor_late_rate lr  ON ss.sole_vendor_id = lr.vendor_id
JOIN vw_hhi_by_category h    ON ss.category_name  = h.category_name;