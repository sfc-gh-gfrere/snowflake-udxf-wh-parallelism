-- =====================================================================
-- UDxF Enablement Setup: warehouses, grants, synthetic data, stage
-- Author: Garrett Frere (garrett.frere@snowflake.com)
-- Run as ML_PERF_ROLE (has CREATE WAREHOUSE + schema CREATE privileges),
-- so ML_PERF_ROLE owns everything created here.
-- =====================================================================
USE ROLE ML_PERF_ROLE;
USE DATABASE ML_PERF;
USE SCHEMA PUBLIC;

-- ---------------------------------------------------------------------
-- 1. Warehouses for the scaling demo
--    SMALL = 2 nodes, MEDIUM = 4 nodes, LARGE = 8 nodes
--    (same query, each size doubles the compute)
-- ---------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS UDXF_S_WH
  WAREHOUSE_SIZE = 'SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'UDxF enablement - Small (2 nodes)';

CREATE WAREHOUSE IF NOT EXISTS UDXF_M_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'UDxF enablement - Medium (4 nodes)';

CREATE WAREHOUSE IF NOT EXISTS UDXF_L_WH
  WAREHOUSE_SIZE = 'LARGE'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'UDxF enablement - Large (8 nodes)';

-- ---------------------------------------------------------------------
-- 2. Synthetic retail sales data (100M rows, 1,000 stores, 2 years)
--    ~100k rows per store (uniform -> homogeneous partition sizes).
--    Each store has its own price elasticity so a per-store model
--    (UDTF partitioned by STORE_ID) has a real signal to recover.
-- ---------------------------------------------------------------------
USE WAREHOUSE UDXF_M_WH;

CREATE OR REPLACE TABLE ML_PERF.PUBLIC.STORE_SALES AS
WITH base AS (
    SELECT
        SEQ8()                                   AS sale_id,
        UNIFORM(1, 1000, RANDOM())               AS store_id,
        UNIFORM(1, 500, RANDOM())                AS sku_id,
        DATEADD(day, UNIFORM(0, 729, RANDOM()), '2024-01-01'::DATE) AS sale_date,
        ROUND(UNIFORM(2::FLOAT, 50::FLOAT, RANDOM()), 2)            AS price,
        IFF(UNIFORM(1, 10, RANDOM()) = 1, 1, 0)  AS promo_flag,
        NORMAL(0, 1, RANDOM())                   AS noise
    FROM TABLE(GENERATOR(ROWCOUNT => 100000000))
)
SELECT
    sale_id,
    store_id,
    CASE MOD(store_id, 4)
        WHEN 0 THEN 'NORTHEAST' WHEN 1 THEN 'SOUTH'
        WHEN 2 THEN 'MIDWEST'   ELSE 'WEST' END            AS region,
    sku_id,
    sale_date,
    price,
    promo_flag,
    -- log(units) = a - elasticity_store * log(price) + promo lift + noise
    -- true elasticity per store = 0.5 + MOD(store_id*37,100)/100  (0.5 .. 1.49)
    GREATEST(1, ROUND(EXP(
        8.0
        - (0.5 + MOD(store_id * 37, 100) / 100.0) * LN(price)
        + 0.3 * promo_flag
        + 0.2 * noise
    )))::INT                                               AS units
FROM base;

-- ---------------------------------------------------------------------
-- 3. Stage for permanent UDF/UDTF code
-- ---------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS ML_PERF.PUBLIC.UDXF_STAGE
  COMMENT = 'Code artifacts for UDxF enablement permanent functions';

-- ---------------------------------------------------------------------
-- 4. Grants
--    ML_PERF_ROLE owns the warehouses, table and stage above, so it
--    already has full privileges. Grants below are for other roles
--    if you share this enablement (uncomment and set the role).
-- ---------------------------------------------------------------------
-- GRANT USAGE, OPERATE ON WAREHOUSE UDXF_S_WH TO ROLE <ATTENDEE_ROLE>;
-- GRANT USAGE, OPERATE ON WAREHOUSE UDXF_M_WH TO ROLE <ATTENDEE_ROLE>;
-- GRANT USAGE, OPERATE ON WAREHOUSE UDXF_L_WH TO ROLE <ATTENDEE_ROLE>;
-- GRANT USAGE ON DATABASE ML_PERF TO ROLE <ATTENDEE_ROLE>;
-- GRANT USAGE, CREATE FUNCTION ON SCHEMA ML_PERF.PUBLIC TO ROLE <ATTENDEE_ROLE>;
-- GRANT SELECT ON TABLE ML_PERF.PUBLIC.STORE_SALES TO ROLE <ATTENDEE_ROLE>;
-- GRANT READ, WRITE ON STAGE ML_PERF.PUBLIC.UDXF_STAGE TO ROLE <ATTENDEE_ROLE>;

-- Make sure your user has the role (requires SECURITYADMIN / USERADMIN;
-- skip if MLFCTO_USER already uses ML_PERF_ROLE):
-- USE ROLE SECURITYADMIN;
-- GRANT ROLE ML_PERF_ROLE TO USER MLFCTO_USER;

-- ---------------------------------------------------------------------
-- 5. Sanity checks
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS n_rows, COUNT(DISTINCT store_id) AS n_stores,
       MIN(sale_date) AS min_date, MAX(sale_date) AS max_date
FROM ML_PERF.PUBLIC.STORE_SALES;

ALTER WAREHOUSE UDXF_M_WH SUSPEND;
USE WAREHOUSE ML_MODEL_WH;
