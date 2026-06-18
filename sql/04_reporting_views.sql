USE supply_chain_db;


-- Task 1: Master vendor risk view — primary Power BI source
-- Task 1a: alter imported from Python Stage 3
CREATE VIEW vw_vendor_risk_master AS
SELECT
    vs.vendor_id, vs.vendor_name, vs.vendor_tier,
    vs.total_orders, vs.total_spend, vs.avg_spend_per_order,
    lt.avg_lead_time, lt.std_lead_time,
    lr.late_delivery_rate_pct,
    vrs.composite_risk_score,
    vrs.risk_band
FROM vw_vendor_spend vs
JOIN vw_vendor_lead_time lt  ON vs.vendor_id = lt.vendor_id
JOIN vw_vendor_late_rate lr  ON vs.vendor_id = lr.vendor_id
LEFT JOIN vendor_risk_scores vrs ON vs.vendor_id = vrs.vendor;


-- Task 2: Dual-sourcing recommendations — top 12 from Python Stage 4
CREATE VIEW vw_dual_sourcing_recommendations AS
SELECT
    t.rank_order,
    t.category,
    t.vendor,
    v.vendor_name,
    v.vendor_tier,
    t.market_share,
    t.breach_probability,
    t.spend_at_risk,
    t.disruption_exposure,
    t.projected_risk_reduction_pct,
    t.recommendation
FROM top12_dual_sourcing t
LEFT JOIN dim_vendor v ON t.vendor = v.vendor_id
ORDER BY t.rank_order;


-- Task 3: KPI summary — Executive Dashboard cards
CREATE VIEW vw_kpi_summary AS
SELECT
    COUNT(DISTINCT f.vendor_id)               AS total_vendors,
    COUNT(DISTINCT p.category_name)           AS total_categories,
    ROUND(SUM(f.spend_per_order), 0)          AS total_spend,
    ROUND(AVG(f.lead_time_days), 1)           AS avg_lead_time_days,
    ROUND(AVG(f.late_delivery_flag) * 100, 1) AS overall_late_rate_pct,
    (SELECT COUNT(*)
     FROM monte_carlo_results)                AS categories_simulated,
    (SELECT COUNT(*)
     FROM vw_vendor_risk_master
     WHERE risk_band = 'Critical')            AS critical_risk_vendors,
    (SELECT ROUND(SUM(spend_at_risk), 0)
     FROM top12_dual_sourcing)                AS total_spend_at_risk,
    (SELECT ROUND(SUM(disruption_exposure), 0)
     FROM top12_dual_sourcing)                AS total_disruption_exposure
FROM fact_orders f
JOIN dim_product p ON f.product_id = p.product_id;


-- Task 4: Category concentration — Vendor Risk Matrix page
CREATE VIEW vw_category_concentration AS
SELECT
    h.category_name,
    h.hhi_score,
    h.vendor_count,
    h.concentration_band,
    ss.market_share          AS top_vendor_share,
    ss.sole_vendor_id        AS top_vendor_id,
    v.vendor_name            AS top_vendor_name,
    ROUND(SUM(f.spend_per_order), 2)        AS total_category_spend,
    ROUND(AVG(f.lead_time_days), 2)         AS avg_category_lead_time,
    ROUND(AVG(f.late_delivery_flag)*100, 2) AS category_late_rate_pct
FROM vw_hhi_by_category h
JOIN vw_single_source ss  ON h.category_name = ss.category_name
JOIN dim_vendor v          ON ss.sole_vendor_id = v.vendor_id
JOIN fact_orders f ON f.product_id IN (
    SELECT product_id FROM dim_product
    WHERE category_name = h.category_name
)
GROUP BY h.category_name, h.hhi_score, h.vendor_count,
         h.concentration_band, ss.market_share,
         ss.sole_vendor_id, v.vendor_name;


-- Task 5: YoY spend trend per vendor
CREATE VIEW vw_yoy_spend AS
WITH yearly_spend AS (
    SELECT
        f.vendor_id, v.vendor_name, d.year,
        SUM(f.spend_per_order) AS annual_spend
    FROM fact_orders f
    JOIN dim_vendor v ON f.vendor_id = v.vendor_id
    JOIN dim_date d   ON f.order_date = d.date_id
    GROUP BY f.vendor_id, v.vendor_name, d.year
)
SELECT
    curr.vendor_id,
    curr.vendor_name,
    curr.year,
    ROUND(curr.annual_spend, 2)                      AS current_year_spend,
    ROUND(prev.annual_spend, 2)                      AS prev_year_spend,
    ROUND(curr.annual_spend - prev.annual_spend, 2)  AS yoy_spend_change,
    ROUND((curr.annual_spend - prev.annual_spend) /
          NULLIF(prev.annual_spend, 0) * 100, 2)     AS yoy_growth_pct
FROM yearly_spend curr
LEFT JOIN yearly_spend prev
    ON curr.vendor_id = prev.vendor_id
    AND curr.year = prev.year + 1
ORDER BY curr.vendor_id, curr.year;