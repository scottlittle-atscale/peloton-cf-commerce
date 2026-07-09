# Connected Fitness Commercial — AtScale SML Model

A governed AtScale semantic model over a Connected Fitness commercial mart: hardware
**sales** and **subscription / membership** analytics on Google BigQuery. Generated from
a demo-data bundle; it answers 10 conversational NLQs spanning Commercial/Sales,
Membership, and Finance personas, with fiscal (July–June) time-intelligence and
semi-additive subscription balances.

> **Naming note (Rule 18):** logical model metadata is genericized to *Connected Fitness
> Commercial* rather than the customer name. The physical BigQuery schema
> (`PELOTON_CF_COMMERCE_DEMO`) is retained because that is where the data lives. Rebrand
> labels freely for a customer-facing presentation.

## Inputs

Handed in as `context/peloton_cf_commerce_context.zip` (copied verbatim; extracted files also in `context/`):

- **use_case.md** — scenario, the 10 brief NLQs, engineered narratives, grain, additivity, limitations.
- **02_ddl.sql** — BigQuery `CREATE TABLE` DDL for the 9-table star (6 dims + 3 facts).
- **erd.mmd** — Mermaid ERD confirming relationships/cardinality.
- **data_profile.yaml** — column-level profile (types, distinct counts, row counts) used to derive `is_unique_key`.
- **NLQs** — embedded in use_case.md (not a separate file).
- **Target warehouse** — Google BigQuery, project `atscale-sales-demo`, dataset `PELOTON_CF_COMMERCE_DEMO` (data already loaded live).
- **build.yaml** — (not provided; all parameters derived from inputs + defaults).
- **Existing SML** — (not provided; fresh model).

## Build parameters

- **warehouse** = BigQuery
- **model_unique_name** = `connected_fitness_commerce`
- **catalog_unique_name** = `connected_fitness_commerce_catalog`
- **connection** database = `atscale-sales-demo` (project), schema = `PELOTON_CF_COMMERCE_DEMO` (dataset)
- **unrelated_dimension_handling** = `repeat` (applied to every base metric; multi-fact model)
- **currency** = USD
- **time_window** = fiscal (fiscal year ends June 30; primary hierarchy is the Fiscal Calendar)
- **semi_additive_default** = last_non_empty (applied to the snapshot balances `Active Subscriptions`, `MRR`)
- **use_cases_covered** = Hardware Sales + Subscription/Membership (all NLQs)
- **use_cases_excluded** = none within the bundle (supply chain / finance-GL are separate bundles)

## Assumptions and decisions

- **warehouse = BigQuery** — stated by the caller and matches lowercase unquoted identifiers in `context/02_ddl.sql`.
- **connection.database = atscale-sales-demo / connection.schema = PELOTON_CF_COMMERCE_DEMO** — concrete values from the caller (Rule 17); the schema retains the customer name because that is the physical dataset the data was loaded into (Rule 18 physical-identifier exception). Reload into a generically-named dataset and re-point the connection to remove it.
- **model/catalog/labels genericized to "Connected Fitness Commercial"** — Rule 18 (no customer name in logical metadata). Product names, regions, etc. are data values from the warehouse and are not masked.
- **No role-play on any dimension** — no fact carries two FKs to the same dimension (each fact joins Date once, Product once, etc.), so a single conformed Date/Product/Geography/Channel/Plan/Member dimension is joined by multiple facts without role-play. This keeps the MDX free of prefix propagation (Rule 2 not triggered).
- **Date Dimension is `type: time` with two hierarchies** — `Fiscal Calendar` (Fiscal Year → Fiscal Quarter → Fiscal Month → Day; primary, since the NLQs are fiscal-oriented) and `Calendar` (Year → Quarter → Month → Day). They share the `Day` leaf (Rule 10 allows a shared leaf); the month/quarter levels are distinct per hierarchy so each carries its own `parallel_periods`.
- **Prior-year time-intelligence uses `ParallelPeriod`** on the Fiscal Year level (Rule 13), backed by calculated columns `prior_fiscal_year_num` / `prior_year_num` and `parallel_periods` blocks on the Quarter and Month levels. YoY calcs are wired to the fiscal hierarchy because the NLQs reference fiscal quarters/years.
- **Semi-additive `Active Subscriptions` and `MRR`** — `semi_additive: {position: last}` over the `fact_subscription_snapshot → Date Dimension` relationship, `calculation_method: sum` (Rule 19; `average` is illegal on a semi-additive metric). All other snapshot measures (new/churned/net-new) are additive flows.
- **`dim_member` is both a dimension source and a member-grain fact** (Rule 20) — it carries `Member Count`, `Active Members`, `Total Tenure Months`, so it is attached to the model as the `from.dataset` of a 1:1 relationship to the Member Dimension plus join relationships to Date (join date), Product (initial product), Geography, Channel, and Plan. This powers cohort/retention (NLQ-6), tenure-by-initial-product (NLQ-9), and channel-retention (NLQ-10).
- **Calculated columns added** — `dim_date`: `prior_fiscal_year_num`, `prior_year_num`, `month_year_label`, `cal_quarter_label`, `cal_year_name`; `fact_sales_orders`: `is_returned_int`, `is_financed_int`; `fact_subscription_events`: `new_flag_int`, `cancel_flag_int`; `dim_member`: `active_flag_int`, `membership_status`. Each carries a BigQuery `dialects` entry.
- **`is_unique_key` derived from the data profile** (Rule 16) — set on Day (date_key 1096==1096), Country (5==5), Channel (5==5), Plan (3==3), Product (15==15), Member (150000==150000); omitted on non-unique parent levels and composite quarter keys.
- **Monthly Churn Rate definition** — churned ÷ (active + churned) = cancellations as a share of the start-of-period active base; a within-period ratio needing no time navigation. Documented so consumers read it consistently with the NLQ-4 story.
- **`unrelated_dimensions_handling = repeat`** — default; multi-fact model where most dimension/metric pairs cross fact boundaries.

## Generation summary

- **Datasets:** 9 (6 dimension sources + 3 fact tables; `dim_member` doubles as a fact).
- **Dimensions:** 6 — Date (time, 2 hierarchies), Product (Line→Category→Product + Condition/Refurbished secondary attrs), Geography (Region→Country), Channel (Type→Channel), Plan (Type→Plan), Member (Segment→Member + Membership Status).
- **Base metrics:** 20 — 8 sales, 9 subscription (snapshot + events), 3 member. `Active Subscriptions` and `MRR` are semi-additive.
- **Calculated metrics:** 13 — AOV, Return Rate; fiscal YoY for Net Revenue / Units Sold / MRR (prior-year + %); Monthly Churn Rate; MoM net-adds (prior period + change); Average Tenure Months; Member Retention Rate.
- **Relationships:** 20 fact↔dimension joins across the 4 facts. No role-play, no snowflake, no degenerate dims (so the model `dimensions:` block is omitted).
- **Role-play prefixes:** none. **Snowflake bridges:** none. **Calculated columns added:** 11.
- **NLQ coverage:** all 10 — NLQ-1 Units Sold + fiscal-quarter YoY; NLQ-2 Net Revenue/Order Count (AOV) by Region; NLQ-3 Net Revenue by Condition; NLQ-4 Monthly Churn Rate by month; NLQ-5 Net New MoM; NLQ-6 Member Retention Rate by join cohort (Date join role via dim_member); NLQ-7 MRR + MRR YoY %; NLQ-8 Net Revenue by Product Line vs MRR; NLQ-9 Average Tenure Months by initial Product Category; NLQ-10 Member Retention Rate by Channel.
- **Caveats:** NLQ-9 raw tenure is confounded by Tread+ cohort recency (documented in use_case.md); pair with Member Retention Rate. Subscription "revenue" (NLQ-8) is proxied by summed month-end MRR (no billed-revenue fact).

## Reproducing this build

`context/` holds verbatim copies of every input (the original `peloton_cf_commerce_context.zip`
plus its extracted `02_ddl.sql`, `erd.mmd`, `data_profile.yaml`, `use_case.md`). Re-running
the SML generator with the same inputs and the build parameters above produces an
equivalent model. The underlying data is deterministic (seed 42) and already loaded in
`atscale-sales-demo.PELOTON_CF_COMMERCE_DEMO`.
