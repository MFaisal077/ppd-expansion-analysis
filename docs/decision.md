# Assumptions and Decisions Log

Every choice that changes a number in the analysis is recorded here, with the
reason and the alternative considered. When a decision changes, the old entry is
marked **Superseded** and kept, rather than deleted.

Status: **Decided**, **Open** (still to settle) or **Superseded**.

| # | Decision | Layer | Status | Date |
|---|---|---|---|---|
| D01 | [Borough is assigned from the ONS Postcode Directory](#d01) | core | Decided | 2026-10-03 |
| D02 | [Staging keeps all England and Wales sales](#d02) | stg | Decided | 2026-10-03 |
| D03 | [Category B sales are kept in staging](#d03) | stg | Decided | 2026-10-03 |
| D04 | [Staging keeps 8 of 16 Price Paid columns](#d04) | stg | Decided | 2026-10-03 |
| D05 | [Scope exclusions and their order](#d05) | stg | Decided | 2026-10-03 |
| D06 | [No transaction dedupe rule is needed](#d06) | stg | Decided | 2026-10-03 |
| D07 | [Deleted-records check kept, expected to find none](#d07) | stg | Decided | 2026-10-03 |
| D08 | [Raw layer stores every value as text, unchanged](#d08) | raw | Decided | 2026-10-03 |
| D09 | [Earnings: ASHE Table 8.7, residence-based, full-time median](#d09) | stg | Decided | 2026-10-03 |
| D10 | [Rent source: ONS ad hoc London private rents, Apr 2025 to Mar 2026](#d10) | stg | Decided | 2026-10-03 |
| D11 | [Rent basis for gross rental yield](#d11) | mart | **Open** | |
| D12 | [Price upper cap](#d12) | stg | **Open** | |

---

<a id="d01"></a>
## D01. Borough is assigned from the ONS Postcode Directory

**Decision.** A sale's borough is the `lad26cd` of its postcode in the ONS
Postcode Directory (August 2026). London boroughs are the codes starting `E09`.

**Why.**
- The brief requires it ("joined to borough through the postcode directory").
- It gives an official code that joins directly to the earnings data. Names
  differ in spelling and case between sources.
- The Price Paid `town_city` field is the postal town, not the borough.
  Filtering on `town_city = 'LONDON'` finds 767,120 London sales out of
  1,265,693 (61%), missing boroughs such as Croydon, Bromley and Harrow.

**Evidence (raw data).** Comparing the Price Paid `county` field with the
postcode directory:

| County says London | Postcode says London | Sales |
|---|---|---|
| Yes | Yes | 1,260,829 |
| Yes | No match | 4,797 |
| No | Yes | 79 |
| Yes | No (different area) | 67 |

99.62% of county-London sales match a postcode, above the brief's 99% target.
Most non-matches (4,648) have a blank postcode.

**Alternative considered.** Price Paid `county = 'GREATER LONDON'` and
`district` as the borough. Rejected: it is address text rather than an official
geography, and the brief specifies the postcode directory. `county` remains
useful as a cross-check.

---

<a id="d02"></a>
## D02. Staging keeps all England and Wales sales

**Decision.** `stg.ppd` covers all of England and Wales. London is selected in
core, through the postcode join (D01).

**Why.** London is defined in one place only. Filtering by location in staging
would mean a second, different definition.

**Alternative considered.** Filter to London in staging to make the table
smaller. Rejected for the reason above; 10.6M rows is manageable.

---

<a id="d03"></a>
## D03. Category B sales are kept in staging

**Decision.** `stg.ppd` keeps both `ppd_category` A (standard) and B
(additional, such as repossessions and buy-to-let mortgages). Headline metrics
filter to category A in the marts.

**Why.** The brief excludes category B from headline metrics but shows it as a
sensitivity. Dropping B in staging would make that sensitivity impossible.

**Alternative considered.** Drop category B in staging. Rejected for the
reason above.

---

<a id="d04"></a>
## D04. Staging keeps 8 of 16 Price Paid columns

**Decision.** Kept: `transaction_id`, `price`, `date_of_transfer`, `postcode`,
`property_type`, `ppd_category`, `record_status`, `source_file`.

Dropped: `new_build`, `tenure`, `paon`, `saon`, `street`, `locality`,
`town_city`, `district`, `county`.

**Why.** A column is kept only if a later step needs it. The analysis is at
borough level, so address fields are not used, and borough comes from the
postcode (D01). Raw keeps every column, so any dropped column can be brought
back.

**Alternative considered.** Keep `new_build` to explain medians that new
builds push up. Not needed for the five metrics; revisit if the memo needs it.

---

<a id="d05"></a>
## D05. Scope exclusions and their order

**Decision.** A raw row is excluded if it fails any rule below. Each excluded
row is written to `stg.ppd_dropped` with the **first** rule it fails, so every
row has exactly one reason.

| Order | Reason | Rule | Rows (2015 to 2025) |
|---|---|---|---|
| 1 | `record_status_D` | Deleted record | 0 |
| 2 | `property_type_O` | Property type "other" | 625,410 |
| 3 | `price_below_10000` | Price under £10,000 | 304 |
| | **Total excluded** | | **625,714** |

Reconciliation: 11,200,195 raw = 10,574,481 kept + 625,714 excluded.

**Why.** These are the brief's scope rules. Excluded rows keep their raw values
so they can be inspected.

**Note.** The £10,000 floor keeps a sale of exactly £10,000 (`>= 10000`).
Counts are for England and Wales; London counts follow from the core join.

---

<a id="d06"></a>
## D06. No transaction dedupe rule is needed

**Decision.** No deduplication step in staging.

**Why.** All 1,265,693 London transaction IDs in the raw data are unique
across the 11 yearly files. Each yearly file holds only sales transferred in
that year.

**Safeguard.** Uniqueness of `transaction_id` is still checked in staging and
core, so a future duplicate stops the build rather than passing silently.

---

<a id="d07"></a>
## D07. Deleted-records check kept, expected to find none

**Decision.** Keep the `record_status = 'D'` exclusion and its check.

**Why.** The yearly files are snapshots of current records and contain only
status `A`. Status `C` (changed) and `D` (deleted) appear only in HM Land
Registry's monthly change files. The brief requires the check, and it would
matter if the pipeline later switched to the monthly files.

---

<a id="d08"></a>
## D08. Raw layer stores every value as text, unchanged

**Decision.** Raw tables have only text columns, loaded exactly as in the
source file. Spreadsheet rows keep their worksheet `row_num`; every row keeps
its `source_file`.

**Why.** No value is lost or altered on load, so any number can be traced to
its source cell or line. Typing and cleaning happen in staging, where each
change is visible in SQL.

---

<a id="d09"></a>
## D09. Earnings: ASHE Table 8.7, residence-based, full-time median

**Decision.** Affordability uses the median gross annual pay of full-time
employees by place of residence: ASHE Table 8.7a, 2025 provisional, `Full-Time`
sheet. Estimate quality comes from the matching coefficients of variation in
Table 8.7b.

**Why.** The brief's affordability question is about people who live in the
borough, so residence-based (Table 8) is right and workplace-based (Table 7)
is not.

**Known gap.** The City of London is suppressed (`x`). It is not ranked, so
this does not affect the shortlist.

---

<a id="d10"></a>
## D10. Rent source: ONS ad hoc London private rents, Apr 2025 to Mar 2026

**Decision.** Gross rental yield uses the ONS ad hoc release *Private rental
market in London: April 2025 to March 2026*, worksheet 2 (borough by bedroom
category).

**Why.** It covers all 33 London areas with count, median and quartiles, for a
recent 12 months.

**Caveats to state in the memo.**
- Not adjusted for property mix.
- The publisher's notes say the figures should not be compared across areas
  or time periods, because the sample is purposive.
- There is no all-properties median per borough (see D11).

**Alternative considered.** ONS Price Index of Private Rents (PIPR). Kept as
the cross-check source.

---

<a id="d11"></a>
## D11. Rent basis for gross rental yield (Open)

**Question.** The rent file gives medians by bedroom category only, and
medians cannot be combined into one borough median. The brief's current choice
("all dwellings for both rent and price") cannot be built from this file
as-is.

**Options.**

| Option | For | Against |
|---|---|---|
| A. 2-bed median rent against median flat price | Close to like-for-like; the brief lists separate flat yields as an alternative | Ignores houses |
| B. Count-weighted average of bedroom medians, against all-dwelling median price | Uses all property types | An approximation, not a true median |
| C. PIPR all-dwellings average rent | A true all-properties figure | A mean, not a median; different method from the price data |

**To decide before** building `stg.rents`.

---

<a id="d12"></a>
## D12. Price upper cap (Open)

**Question.** The brief sets a £10,000 floor and an upper cap "after inspecting
the distribution". The highest raw price is £900,000,000, almost certainly a
portfolio or commercial transfer recorded as one sale.

**Plan.** Inspect the top of the London price distribution in core, choose a
cap or percentile trim, and record it here. Medians are robust to a few
extreme values, so the cap mainly matters for volatility and outlier logging.
