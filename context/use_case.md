# peloton_cf_commerce — Connected Fitness Commercial Analytics

**Customer:** Peloton Interactive · **Warehouse:** Google BigQuery · **Currency:** USD
**Window:** 2023-07-01 → 2026-06-30 (36 months = fiscal years **FY24, FY25, FY26**;
Peloton's fiscal year ends June 30). **Current month / latest snapshot:** 2026-06.
**Seed:** 42 (deterministic).

## Scenario

A conversational-analytics / semantic-layer demo for Peloton's two reportable
segments — **Connected Fitness Products** (hardware: Bike, Bike+, Tread, Tread+, Row,
Precor, accessories, apparel) and **Subscription** (All-Access Membership + App
memberships). One governed star schema serves three personas the way Peloton's own RFP
frames them:

- **Commercial / Sales** — units, revenue, AOV, refurb-vs-new mix, channel performance.
- **Membership leadership** — active subscriptions, churn, retention cohorts, net adds.
- **Finance** — MRR, MRR growth, segment revenue mix, tenure/LTV signals.

The data is deliberately engineered so a conversational agent grounded on the semantic
layer can answer the questions below *and* reason about the nuances (cohort maturity,
seasonality, a recall-style anomaly) rather than returning flat, storyless numbers.

## Brief NLQs (the demo must answer these)

| # | Persona | Question |
|---|---|---|
| 1 | Commercial | What were Bike+ unit sales last quarter vs. the same quarter last year? |
| 2 | Commercial | Which region had the highest average order value for hardware in FY26? |
| 3 | Commercial | Show refurbished vs. new hardware revenue mix over the last 12 months. |
| 4 | Membership | What's our monthly churn-rate trend for All-Access members over the past year? |
| 5 | Membership | How many net new subscriptions did we add last month vs. the prior month? |
| 6 | Membership | What's the retention curve for members who joined during the January promo? |
| 7 | Finance | What's total MRR right now, and how did it grow year-over-year? |
| 8 | Finance | Break down revenue by segment — Connected Fitness vs. Subscription — TTM. |
| 9 | Cross-domain | For members who bought a Tread, what's their subscription tenure vs. Bike buyers? |
| 10 | Cross-domain | Which acquisition channel drives members with the lowest churn? |

Each has a matching query in [`nlq_smoke_tests.sql`](nlq_smoke_tests.sql) (one per NLQ,
same numbering).

## Engineered narratives (deliberately baked into the data)

1. **Hardware holiday seasonality** — equipment orders peak Nov/Dec (~1.7× trough) with
   a January "new-year" bump; spring/summer are the trough. (Driven by seasonal
   member-join volume.)
2. **January new-member surge** — join volume spikes each January (~1.55×) and around
   the holidays.
3. **Post-holiday churn bump** — All-Access cancellations run ~1.5–1.6× the annual
   average in **February–March** every year (resolution fatigue).
4. **Tread+ launch ramp** — Tread+ has **zero** units before **2024-01**, then ramps
   over ~6 months to full run-rate. Because it's a mid-window launch, Tread+ buyers are a
   **younger cohort** (shorter observed tenure) — see Known Limitations / NLQ-9.
5. **Per-region AOV baselines** — **Germany** carries the highest hardware AOV (premium
   Bike+/Tread+/Row skew, less refurb); North America the lowest (broadest mix). Gap is
   ~10%+ in FY26, clearly detectable.
6. **Subscription growth** — active subs and MRR grow YoY (~+33% at the latest snapshot)
   even as new-member *volume* softens YoY (FY24 → FY26 join drift 1.08 → 0.94), the
   realistic "subscriptions resilient while hardware demand normalizes" story.
7. **Churn anomaly (recall-style)** — in **2025-05**, **All-Access churn in North
   America** spikes ~2.6× for that single month, and **Tread+ returns in North America**
   jump to ~12% (vs. ~4% baseline). NA is the dominant region, so the spike is visible at
   the rolled-up level and drillable to region + product. A good agent distinguishes this
   one-month event from the recurring Feb/Mar seasonal bump.
8. **Segment self-selection** — Enthusiasts (low churn) skew to premium new equipment;
   Deal-Seekers (high churn) skew to refurbished/entry. So premium-equipment buyers show
   longer tenure — a causal-looking retention signal that is really a mix effect (a nice
   "correlation vs. causation" talking point).
9. **Channel retention profile** — retention is highest for Commercial (Precor) and
   Retail Showroom, lowest for Amazon/Marketplace — answers NLQ-10.

## Grain

| Table | Grain | Kind |
|---|---|---|
| `dim_date` | one row per calendar day (2023-07-01 … 2026-06-30) | dimension |
| `dim_geography` | one row per country (region → country) | dimension |
| `dim_channel` | one row per sales/acquisition channel | dimension |
| `dim_subscription_plan` | one row per membership plan | dimension |
| `dim_product` | one row per SKU (model × condition, + accessories/apparel/Precor) | dimension |
| `dim_member` | one row per member (join, geography, channel, plan, segment, initial product, tenure, active flag) | dimension |
| `fact_sales_orders` | one row per **order line** (equipment / accessory / apparel) | transaction fact |
| `fact_subscription_events` | one row per **lifecycle event** (New Subscription / Cancellation) | transaction fact |
| `fact_subscription_snapshot` | one row per **month × plan × geography × channel** | periodic snapshot |

### Additivity (matters for the semantic model)

- `fact_sales_orders`: `quantity`, `gross_revenue`, `discount_amount`, `net_revenue`,
  `returned_amount` are **fully additive**.
- `fact_subscription_events`: `mrr_delta`, `event_count` are **additive** (signed).
- `fact_subscription_snapshot`: `new_subscriptions`, `churned_subscriptions`,
  `net_new_subscriptions` are **additive flows**; `active_subscriptions` and `mrr` are
  **semi-additive balances** — sum across plan/geography/channel within a snapshot, but
  **do not sum across `snapshot_date_key`** (take last / as-of over the date). The
  snapshot reconciles exactly: `active_t = active_{t-1} + new_t − churned_t`.

## Aggregate shape (rough, at seed 42)

- Members: **150,000** created over the window; **~96,900** active at 2026-06.
- `fact_sales_orders`: **~211,000** lines (~91K equipment + ~120K accessory/apparel).
- `fact_subscription_events`: **~203,000** (150K New + ~53K Cancellation).
- `fact_subscription_snapshot`: **2,698** rows (36 months × active plan/geo/channel cells).
- Latest MRR ≈ **$3.7M/mo**; FY26 hardware net revenue ≈ **$64M**.

## Known limitations

- **Scaled volumes.** Member/MRR counts are demo-scaled (tens of thousands, not
  Peloton's real millions) so the bundle loads fast; ratios, trends, and seasonality are
  realistic, absolute dollars are not.
- **No mid-life plan changes.** Each member has one plan for their whole lifecycle — no
  App→All-Access upgrades/downgrades, no win-back/reactivation. Every member has exactly
  one New Subscription and at most one Cancellation. (Future extension.)
- **NLQ-9 cohort confound (intentional).** Raw average tenure by initial product is
  affected by cohort recency: Tread category tenure looks slightly *lower* than Bike
  partly because **Tread+ launched in 2024** and its buyers are younger (right-censored).
  This is deliberate — it exercises an agent's ability to separate "newer cohort" from
  "churns faster." Pair tenure with `still_active_pct` and cohort filters for the honest read.
- **Subscription "revenue" proxy.** NLQ-8 approximates trailing-12-month subscription
  revenue as the sum of month-end MRR over the 12 snapshots; there is no separate billed-
  revenue fact.
- **Returns are flagged, not reversed.** `is_returned` / `returned_amount` mark returns;
  `net_revenue` is not reduced for them (net-of-returns is a semantic-layer calculation).
- **Single currency (USD).** International regions exist for geography drill but there is
  no native-currency or FX modeling.
