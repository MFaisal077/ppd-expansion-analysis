#!/usr/bin/env python3
"""Collect raw data for the London borough expansion project.

Downloads the HM Land Registry Price Paid Data (PPD) yearly files, profiles
them, and checks that the three manual downloads (ONSPD, ASHE earnings, rents)
are in place. Raw files are never modified. Standard library only.

Run from anywhere:

    python data/download_data.py                  # download 2015-2025, then report
    python data/download_data.py --years 2020-2026
    python data/download_data.py --report-only    # skip downloads, just profile + check
    python data/download_data.py --manual         # print the manual download steps
"""
import argparse
import csv
import datetime as dt
import hashlib
import sys
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
PPD_DIR = RAW / "ppd"
MANIFEST = RAW / "MANIFEST.csv"
PROFILE = RAW / "ppd_profile.csv"

# Tried in order. The file is also linked from the GOV.UK yearly-file page.
PPD_URLS = [
    # Confirmed working on a real run (3 Oct 2026). The prod1 address did not resolve there.
    "http://prod.publicdata.landregistry.gov.uk.s3-website-eu-west-1.amazonaws.com/pp-{year}.csv",
    "https://prod1.publicdata.landregistry.gov.uk/file/pp-{year}.csv",
]
PPD_PAGE = "https://www.gov.uk/government/statistical-data-sets/price-paid-data-downloads"

PPD_COLUMNS = [
    "transaction_id", "price", "date_of_transfer", "postcode", "property_type",
    "new_build", "tenure", "paon", "saon", "street", "locality", "town_city",
    "district", "county", "ppd_category", "record_status",
]

MANUAL = {
    "onspd": {
        "dir": RAW / "onspd",
        "what": "ONS Postcode Directory, August 2026 (about 242 MB zip)",
        "page": "https://geoportal.statistics.gov.uk/datasets/9e5a92a3cfb14dc7ad43d6ea7a7b8c7f/about",
        "steps": [
            "Open the page, click Download, save the zip.",
            "Put the zip in data/raw/onspd/ (unzip it there too; keep the Documents folder).",
            "Keep terminated postcodes: older sales may use postcodes that no longer exist.",
        ],
    },
    "ashe": {
        "dir": RAW / "ashe",
        "what": "Earnings by place of residence, local authority: ASHE Table 8 (2025 provisional edition)",
        "page": "https://www.ons.gov.uk/employmentandlabourmarket/peopleinwork/earningsandworkinghours/datasets/placeofresidencebylocalauthorityashetable8",
        "steps": [
            "Open the page, choose the 2025 provisional edition, download the xlsx.",
            "Put it in data/raw/ashe/. Use residence-based (Table 8), not workplace-based (Table 7).",
            "Optional for a trend: download the earlier editions too, one file per year.",
            "A newer edition may appear around late October 2026; check the release calendar.",
        ],
    },
    "rents": {
        "dir": RAW / "rents",
        "what": "ONS: Private rental market in London, April 2025 to March 2026 (xlsx, about 130 KB)",
        "page": "https://www.ons.gov.uk/economy/inflationandpriceindices/adhocs/3389privaterentalmarketinlondonapril2025tomarch2026",
        "steps": [
            "Open the page and download the xlsx. It has count, mean, median and quartile rents by borough.",
            "Put it in data/raw/rents/.",
            "Cross-check source, optional: Price Index of Private Rents, UK: monthly price statistics (ONS).",
            "Caveat to log: these rents are not adjusted for property mix, so compare with care.",
        ],
    },
}


def parse_years(text):
    if "-" in text:
        a, b = text.split("-", 1)
        return list(range(int(a), int(b) + 1))
    return [int(y) for y in text.split(",")]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url, dest):
    part = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": "ppd-expansion-analysis/1.0"})
    written = 0
    with urllib.request.urlopen(req, timeout=60) as resp, open(part, "wb") as out:
        expected = resp.headers.get("Content-Length")
        while True:
            chunk = resp.read(1 << 20)
            if not chunk:
                break
            out.write(chunk)
            written += len(chunk)
    if expected is not None and int(expected) != written:
        part.unlink(missing_ok=True)
        raise OSError(f"incomplete download: got {written} of {expected} bytes")
    part.replace(dest)


def fetch_ppd(year, urls):
    """Return the source URL used, 'existing' if already present, or None on failure."""
    dest = PPD_DIR / f"pp-{year}.csv"
    if dest.exists() and dest.stat().st_size > 0:
        print(f"  {year}: already present, skipped")
        return "existing"
    for template in urls:
        url = template.format(year=year)
        try:
            print(f"  {year}: downloading {url}")
            download(url, dest)
            print(f"  {year}: done ({dest.stat().st_size / 1e6:.0f} MB)")
            return url
        except (urllib.error.URLError, OSError) as exc:
            print(f"  {year}: failed ({exc})")
    print(f"  {year}: could not download. Save the {year} file from {PPD_PAGE}")
    print(f"        as {dest}, then re-run with --report-only.")
    return None


def update_manifest(urls_used):
    old = {}
    if MANIFEST.exists():
        with open(MANIFEST, newline="") as f:
            old = {r["file"]: r for r in csv.DictReader(f)}
    rows = []
    for path in sorted(PPD_DIR.glob("pp-*.csv")):
        rel = str(path.relative_to(ROOT))
        prev = old.get(rel)
        used = urls_used.get(path.name)
        if used and used != "existing":
            url, when = used, dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
        elif prev:
            url, when = prev["source_url"], prev["downloaded_at_utc"]
        else:
            url, when = "saved manually", ""
        rows.append({"file": rel, "source_url": url, "bytes": path.stat().st_size,
                     "sha256": sha256(path), "downloaded_at_utc": when})
    if rows:
        with open(MANIFEST, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)
        print(f"Manifest written: {MANIFEST.relative_to(ROOT)}")


def profile_file(path):
    stats = {"file": path.name, "rows": 0, "bad_width": 0, "london_rows": 0,
             "status_A": 0, "status_C": 0, "status_D": 0, "category_A": 0, "category_B": 0,
             "transfer_min": "", "transfer_max": ""}
    london_ids = []
    lo, hi = None, None
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        for row in csv.reader(f):
            stats["rows"] += 1
            if len(row) != len(PPD_COLUMNS):
                stats["bad_width"] += 1
                continue
            status, cat, county = row[15], row[14], row[13]
            if status in ("A", "C", "D"):
                stats[f"status_{status}"] += 1
            if cat in ("A", "B"):
                stats[f"category_{cat}"] += 1
            d = row[2][:10]
            lo = d if lo is None or d < lo else lo
            hi = d if hi is None or d > hi else hi
            if county.strip().upper() == "GREATER LONDON":
                stats["london_rows"] += 1
                london_ids.append(row[0])
    stats["transfer_min"], stats["transfer_max"] = lo or "", hi or ""
    return stats, london_ids


def report():
    files = sorted(PPD_DIR.glob("pp-*.csv"))
    if not files:
        print("No Price Paid files found in", PPD_DIR)
        return
    print("\nPrice Paid Data profile (London = county GREATER LONDON)")
    all_stats, seen = [], defaultdict(set)
    for path in files:
        stats, ids = profile_file(path)
        all_stats.append(stats)
        for i in ids:
            seen[i].add(path.name)
        print(f"  {stats['file']}: {stats['rows']:,} rows, {stats['london_rows']:,} London, "
              f"status A/C/D {stats['status_A']:,}/{stats['status_C']:,}/{stats['status_D']:,}, "
              f"category A/B {stats['category_A']:,}/{stats['category_B']:,}, "
              f"transfers {stats['transfer_min']} to {stats['transfer_max']}, "
              f"bad-width rows {stats['bad_width']}")
    repeated = sum(1 for v in seen.values() if len(v) > 1)
    print(f"\nLondon transaction IDs appearing in more than one file: {repeated:,}")
    print("Use this, and the C/D counts, to settle the staging dedupe rule; log the decision.")
    with open(PROFILE, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(all_stats[0]))
        w.writeheader()
        w.writerows(all_stats)
    print(f"Profile written: {PROFILE.relative_to(ROOT)}")


def print_manual():
    for key, m in MANUAL.items():
        print(f"\n[{key}] {m['what']}\n  {m['page']}")
        for i, s in enumerate(m["steps"], 1):
            print(f"  {i}. {s}")


def check_manual():
    print("\nManual downloads")
    missing = 0
    for key, m in MANUAL.items():
        files = [p for p in m["dir"].rglob("*") if p.is_file()] if m["dir"].exists() else []
        if files:
            size = sum(p.stat().st_size for p in files) / 1e6
            print(f"  {key}: OK ({len(files)} files, {size:.1f} MB) in {m['dir'].relative_to(ROOT)}")
        else:
            missing += 1
            print(f"  {key}: MISSING, expected in {m['dir'].relative_to(ROOT)}")
    if missing:
        print("Run with --manual for the steps.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--years", default="2015-2025", help="range (2015-2025) or list (2015,2016)")
    ap.add_argument("--report-only", action="store_true", help="skip downloads")
    ap.add_argument("--manual", action="store_true", help="print manual download steps and exit")
    ap.add_argument("--base-url", help="override download URL template, e.g. http://localhost:8000/pp-{year}.csv")
    args = ap.parse_args()

    if args.manual:
        print_manual()
        return 0

    PPD_DIR.mkdir(parents=True, exist_ok=True)
    used = {}
    if not args.report_only:
        print(f"Price Paid Data: {args.years}")
        urls = [args.base_url] if args.base_url else PPD_URLS
        for year in parse_years(args.years):
            result = fetch_ppd(year, urls)
            if result:
                used[f"pp-{year}.csv"] = result
    update_manifest(used)
    report()
    check_manual()
    return 0


if __name__ == "__main__":
    sys.exit(main())