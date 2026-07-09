-- peloton_cf_commerce :: BigQuery DDL
-- Connected Fitness commercial mart: hardware sales + subscription/membership.
-- Column order matches the CSV column order exactly (bq load maps CSV positionally).
-- FOREIGN KEYs are documented as comments only: BigQuery rejects any project
-- qualifier in a FK REFERENCES target, and these tables are fully qualified.
-- Joins live in the AtScale semantic model, not in BigQuery metadata.

-- ============================ DIMENSIONS ============================

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.dim_date` (
  date_key            INT64   NOT NULL,   -- YYYYMMDD surrogate key
  full_date           DATE    NOT NULL,
  day_of_month        INT64,
  month_number        INT64,
  month_name          STRING,
  month_start_key     INT64,              -- YYYYMM01 for the month
  calendar_quarter    INT64,
  calendar_year       INT64,
  fiscal_year         INT64,              -- Peloton FY ends June 30
  fiscal_quarter      INT64,
  fiscal_year_label   STRING,             -- e.g. FY26
  fiscal_period_label STRING,             -- e.g. FY26 Q3
  is_holiday_season   BOOL,
  PRIMARY KEY (date_key) NOT ENFORCED
);

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.dim_geography` (
  geography_key INT64  NOT NULL,
  region        STRING,                   -- North America / United Kingdom / Germany / Australia
  country       STRING,
  PRIMARY KEY (geography_key) NOT ENFORCED
);

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.dim_channel` (
  channel_key  INT64  NOT NULL,
  channel_name STRING,                    -- Web / D2C, Retail Showroom, Phone Sales, ...
  channel_type STRING,                    -- Direct / Retail / Partner / Commercial
  PRIMARY KEY (channel_key) NOT ENFORCED
);

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.dim_subscription_plan` (
  plan_key       INT64   NOT NULL,
  plan_name      STRING,                  -- All-Access Membership, App+, App One
  plan_type      STRING,                  -- Connected Fitness / App
  monthly_price  NUMERIC,
  billing_period STRING,
  PRIMARY KEY (plan_key) NOT ENFORCED
);

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.dim_product` (
  product_key          INT64   NOT NULL,
  product_name         STRING,            -- Bike, Bike+, Tread, Tread+, Row, ...
  product_display_name STRING,            -- includes "(Refurbished)" where applicable
  product_category     STRING,            -- Bike / Tread / Row / Accessory / Apparel / Precor
  product_line         STRING,            -- Connected Fitness / Accessories / Apparel / Commercial
  condition            STRING,            -- New / Refurbished / N/A
  is_refurbished       BOOL,
  list_price           NUMERIC,
  launch_date          DATE,              -- nullable; set for SKUs launched mid-window (Tread+)
  PRIMARY KEY (product_key) NOT ENFORCED
);

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.dim_member` (
  member_key              INT64  NOT NULL,
  join_date_key           INT64,          -- FK -> dim_date.date_key
  join_month_key          INT64,          -- YYYYMM01 cohort key
  geography_key           INT64,          -- FK -> dim_geography.geography_key
  acquisition_channel_key INT64,          -- FK -> dim_channel.channel_key
  plan_key                INT64,          -- FK -> dim_subscription_plan.plan_key
  member_segment          STRING,         -- Enthusiast / Mainstream / Deal-Seeker
  initial_product_key     INT64,          -- FK -> dim_product.product_key (nullable)
  tenure_months           INT64,          -- months subscribed (through churn or window end)
  is_active_current       BOOL,           -- active as of the latest snapshot
  PRIMARY KEY (member_key) NOT ENFORCED
);

-- ============================== FACTS ==============================

-- Transaction grain: one row per order line (equipment, accessory, or apparel).
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.fact_sales_orders` (
  order_key       INT64  NOT NULL,
  member_key      INT64,                  -- FK -> dim_member.member_key
  product_key     INT64,                  -- FK -> dim_product.product_key
  date_key        INT64,                  -- FK -> dim_date.date_key (order date)
  geography_key   INT64,                  -- FK -> dim_geography.geography_key
  channel_key     INT64,                  -- FK -> dim_channel.channel_key
  order_type      STRING,                 -- Equipment / Accessory / Apparel
  quantity        INT64,
  unit_price      NUMERIC,
  gross_revenue   NUMERIC,                -- list price x quantity (additive)
  discount_amount NUMERIC,                -- additive
  net_revenue     NUMERIC,                -- gross - discount (additive)
  is_financed     BOOL,                   -- Affirm financing used
  is_returned     BOOL,
  returned_amount NUMERIC,                -- net_revenue if returned else 0 (additive)
  PRIMARY KEY (order_key) NOT ENFORCED
)
CLUSTER BY date_key, product_key, geography_key, channel_key;

-- Subscription lifecycle events (member grain): New Subscription / Cancellation.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.fact_subscription_events` (
  event_key        INT64  NOT NULL,
  member_key       INT64,                 -- FK -> dim_member.member_key
  event_date_key   INT64,                 -- FK -> dim_date.date_key
  plan_key         INT64,                 -- FK -> dim_subscription_plan.plan_key
  geography_key    INT64,                 -- FK -> dim_geography.geography_key
  channel_key      INT64,                 -- FK -> dim_channel.channel_key
  event_type       STRING,                -- New Subscription / Cancellation
  mrr_delta        NUMERIC,               -- +price on new, -price on cancellation (additive)
  cohort_month_key INT64,                 -- member join month (YYYYMM01) for cohorting
  event_count      INT64,                 -- 1 (additive event counter)
  PRIMARY KEY (event_key) NOT ENFORCED
)
CLUSTER BY event_date_key, member_key, plan_key;

-- Periodic snapshot (monthly): active balances are SEMI-ADDITIVE (do not sum across
-- snapshot_date_key); flows (new/churned/net_new) are additive over time.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.fact_subscription_snapshot` (
  snapshot_key           INT64  NOT NULL,
  snapshot_date_key      INT64,           -- FK -> dim_date.date_key (month-end)
  plan_key               INT64,           -- FK -> dim_subscription_plan.plan_key
  geography_key          INT64,           -- FK -> dim_geography.geography_key
  channel_key            INT64,           -- FK -> dim_channel.channel_key
  active_subscriptions   INT64,           -- SEMI-ADDITIVE balance (as-of snapshot)
  mrr                    NUMERIC,         -- SEMI-ADDITIVE balance $ (as-of snapshot)
  new_subscriptions      INT64,           -- additive flow
  churned_subscriptions  INT64,           -- additive flow
  net_new_subscriptions  INT64,           -- additive flow (new - churned)
  PRIMARY KEY (snapshot_key) NOT ENFORCED
)
CLUSTER BY snapshot_date_key, plan_key, geography_key;
