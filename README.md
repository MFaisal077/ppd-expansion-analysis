# London Borough Expansion Analysis

> **Draft.** The raw layer is built and Price Paid staging is done; staging for
> the other sources, core, marts, scoring and the dashboard are still to come. Expect this README to change as they land.

Which two London boroughs should a lettings and sales agency open new branches
in? This project ranks the 32 London boroughs on five metrics (price growth,
sales volume trend, price volatility, gross rental yield and affordability),
using public data led by HM Land Registry Price Paid Data, 2015 to 2025.

The client is fictional; this is a portfolio project. The full brief, including
metric definitions, weights and data quality rules, is in
`Project Brief London Borough Expansion Analysis (HM Land Registry Price Paid Data).docx`.

## How it is built

A layered warehouse in PostgreSQL, each layer built by numbered SQL files:

| Layer | Schema | What it holds | Status |
|---|---|---|---|
| Raw | `raw` | Source files loaded as text, unchanged | Done |
| Staging | `stg` | Typed columns, clean postcodes, deleted and duplicate rows removed, every drop counted | Price Paid done |
| Core | `core` | One row per sale, joined to its borough through the postcode directory | To do |
| Marts | `mart` | Borough-by-year medians and the five metrics | To do |
| Scoring | `mart` | Rescaled, weighted ranking and weight sensitivity | To do |

Data quality checks write to `qa.check_log`. A failed check stops the build.

## Prerequisites

- Python 3.10 or newer (developed on 3.14)
- PostgreSQL 15 or newer (developed on 18)
- About 10 GB of free disk space: 6 GB of source files, plus the database

## Setup

**1. Clone and install**

```bash
git clone https://github.com/MFaisal077/ppd-expansion-analysis.git
cd ppd-expansion-analysis
python -m venv .venv
.venv\Scripts\activate          # Windows
# source .venv/bin/activate     # macOS / Linux
pip install -r requirements.txt
```

**2. Create the database**

```bash
createdb -U postgres -h localhost ppd_expansion
```

Store the password in a password file rather than on the command line, so the
scripts can connect without prompting:

- Windows: `%APPDATA%\postgresql\pgpass.conf`
- macOS / Linux: `~/.pgpass` (then `chmod 600 ~/.pgpass`)

containing one line:

```
localhost:5432:*:postgres:YOUR_PASSWORD
```

The scripts connect to `host=localhost dbname=ppd_expansion user=postgres` by
default. To use something else, set `DATABASE_URL` or pass `--dsn`.

## Get the data

Source files are not in the repository (about 6 GB). Only
`data/raw/MANIFEST.csv` (file sizes and SHA-256 hashes) and
`data/raw/ppd_profile.csv` are committed, so you can check your copies match.

**Price Paid Data** downloads automatically:

```bash
python raw_data/collect_data.py
```

This fetches the 2015 to 2025 yearly files into `data/raw/ppd/`, rewrites the
manifest and profile, and reports which manual downloads are missing. HM Land
Registry regenerates the yearly files every month, so a fresh download may not
match the committed hashes; that is expected.

**Three files must be downloaded by hand.** `python raw_data/collect_data.py --manual`
prints the links. Put them here:

| Dataset | Save to | Notes |
|---|---|---|
| ONS Postcode Directory, August 2026 | `data/raw/onspd/` | Unzip in place, keeping the `Data`, `Documents` and `User Guide` folders |
| ASHE Table 8, 2025 provisional | `data/raw/ashe/` | Residence-based earnings. The loader uses Table 8.7a (annual pay) and 8.7b (its CVs) |
| Private rental market in London, April 2025 to March 2026 | `data/raw/rents/` | ONS ad hoc release, one xlsx |

Then confirm everything is in place:

```bash
python raw_data/collect_data.py --report-only
```

## Load the raw layer

```bash
python scripts/load_raw.py
```

This creates the schemas and raw tables, then loads:

| Table | Source | Rows (approx.) |
|---|---|---|
| `raw.ppd` | Price Paid yearly files, England and Wales | 11.1 million |
| `raw.onspd` | Postcode directory, whole UK | 2.7 million |
| `raw.lad_names` | Local authority codes and names | 361 |
| `raw.ashe_table8` | ASHE 8.7a and 8.7b, every worksheet | 7,200 |
| `raw.rents_borough` | Rents by borough and bedroom category | 198 |

Every table is rebuilt on each run, so it is safe to re-run. Load and check
history is kept across runs. To see the latest results:

```sql
SELECT * FROM qa.check_log WHERE run_id = (SELECT max(run_id) FROM qa.check_log);
SELECT * FROM raw.load_log  WHERE run_id = (SELECT max(run_id) FROM raw.load_log);
```

## Build staging

Run the staging SQL against the database, in pgAdmin's Query Tool or with psql:

```bash
psql -U postgres -h localhost -d ppd_expansion -f sql/02_stg_ppd.sql
```

This builds `stg.ppd` (10.6 million sales in scope, with real types) and
`stg.ppd_dropped` (625,714 excluded sales, each with a reason). Every raw row
lands in exactly one of the two:

```sql
SELECT reason, count(*) FROM stg.ppd_dropped GROUP BY reason;
```

## Repository layout

```
raw_data/collect_data.py   download Price Paid Data, profile it, check manual downloads
scripts/load_raw.py        load every source into the raw schema
sql/00_create_schemas.sql  schemas, raw.load_log, qa.check_log
sql/01_raw_tables.sql      raw table definitions
sql/02_stg_ppd.sql         Price Paid staging: stg.ppd (kept) and stg.ppd_dropped (with reason)
docs/decision.md           assumptions and decisions log
data/raw/                  source files (git-ignored apart from the manifest and profile)
```

## Building on this

Conventions the next layers should follow:

- **Raw is never edited.** All columns are text, values exactly as in the
  file. Spreadsheet rows keep `row_num` so any value traces back to its cell.
  Typing, trimming and filtering belong in staging.
- **Number SQL files in build order** (`02_stg_...`, `03_core_...`), one layer
  or topic per file.
- **Log every check** to `qa.check_log` with `status` of `pass`, `fail` or
  `info`, and stop the build on `fail`. The brief lists the eight checks
  required (row reconciliation, unique transactions, price floor, at least 99%
  postcode match and so on).
- **Count every dropped row by reason** in staging, so raw rows equal staging
  rows plus dropped rows.

Things already learned about the data:

- The yearly Price Paid files contain only record status `A`. Status `C` and
  `D` rows appear only in the monthly change files, so the deleted-records
  check will find none here.
- The postcode directory keeps retired postcodes (`doterm` is set). Keep them,
  because older sales use them. London boroughs are `lad26cd` codes starting
  `E09`; `E09000001` is the City of London, shown but not ranked.
- ASHE suppresses unreliable estimates as `x` (the City of London, for
  example). The CV file (8.7b) gives the quality of each estimate.
- The rents file has no all-properties median per borough, only medians by
  bedroom category, and its notes warn against comparing areas.

## Decisions

Every choice that changes a number is recorded in
[docs/decision.md](docs/decision.md), with the reason and the alternative.
Still open: the rent basis for yield (D11) and the price upper cap (D12).

## Data sources and licences

- Contains HM Land Registry data © Crown copyright and database right 2026.
  This data is licensed under the Open Government Licence v3.0.
- ONS Postcode Directory: Source: Office for National Statistics, licensed
  under the Open Government Licence v3.0. Contains OS data © Crown copyright
  and database right 2026. Contains Royal Mail data © Royal Mail copyright and
  database right 2026.
- Annual Survey of Hours and Earnings and private rental statistics: Office for
  National Statistics, licensed under the Open Government Licence v3.0.
