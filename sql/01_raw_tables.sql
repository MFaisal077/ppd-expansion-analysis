-- 01_raw_tables.sql
-- Raw layer: one table per source, every column text, values exactly as in
-- the file. Typing and cleaning happen in staging. Rebuilt on every load.
--
-- source_file records which file each row came from. For spreadsheets,
-- row_num is the 1-based row in the worksheet, so any value can be traced
-- back to its cell.

-- HM Land Registry Price Paid Data, yearly files (no header row).
-- Column order follows the HM Land Registry field guide.
DROP TABLE IF EXISTS raw.ppd;
CREATE TABLE raw.ppd (
    transaction_id    text,
    price             text,
    date_of_transfer  text,
    postcode          text,
    property_type     text,   -- D, S, T, F, O
    new_build         text,   -- Y, N
    tenure            text,   -- F, L
    paon              text,
    saon              text,
    street            text,
    locality          text,
    town_city         text,
    district          text,
    county            text,
    ppd_category      text,   -- A standard, B additional
    record_status     text,   -- A added, C changed, D deleted
    source_file       text
);

-- ONS Postcode Directory, single UK file. Column names match the file
-- header; the loader stops if the header changes in a new edition.
DROP TABLE IF EXISTS raw.onspd;
CREATE TABLE raw.onspd (
    pcd7 text, pcd8 text, pcds text, dointr text, doterm text,
    cty26cd text, ced25cd text, lad26cd text, wd26cd text, parncp26cd text,
    usrtypind text, east1m text, north1m text, gridind text, hlth19cd text,
    nhser24cd text, ctry26cd text, rgn26cd text, ssr95cd text, pcon24cd text,
    eer20cd text, educ23cd text, ttwa15cd text, pco19cd text, itl25cd text,
    wdstl05cd text, oa01cd text, wdcas03cd text, npark16cd text, lsoa01cd text,
    msoa01cd text, ruc01ind text, oac01ind text, oa11cd text, lsoa11cd text,
    msoa11cd text, wz11cd text, sicbl26cd text, bua24cd text, ruc11ind text,
    oac11ind text, lat text, long text, lep21cd1 text, lep21cd2 text,
    pfa23cd text, imd20ind text, cal26cd text, icb26cd text, oa21cd text,
    lsoa21cd text, msoa21cd text, ruc21ind text, oac21ind text, imd25ind text,
    source_file text
);

-- Local authority names, from the ONSPD Documents folder.
DROP TABLE IF EXISTS raw.lad_names;
CREATE TABLE raw.lad_names (
    lad25cd     text,
    lad25nm     text,
    lad25nmw    text,
    source_file text
);

-- ASHE Table 8 (earnings by place of residence). Every worksheet of each
-- loaded file, every row below the header, footnotes included; staging keeps
-- the rows with a geography code. 8.7a holds the estimates and 8.7b their
-- coefficients of variation (the quality measure).
DROP TABLE IF EXISTS raw.ashe_table8;
CREATE TABLE raw.ashe_table8 (
    source_file        text,
    sheet              text,   -- All, Full-Time, Male Part-Time, ...
    row_num            integer,
    description        text,
    code               text,
    jobs_thousand      text,
    median             text,
    median_pct_change  text,
    mean               text,
    mean_pct_change    text,
    p10 text, p20 text, p25 text, p30 text, p40 text,
    p60 text, p70 text, p75 text, p80 text, p90 text
);

-- ONS ad hoc: Private rental market in London, worksheet 2 (by borough and
-- bedroom category). '..' and '-' are suppressed values; kept as text here.
DROP TABLE IF EXISTS raw.rents_borough;
CREATE TABLE raw.rents_borough (
    source_file       text,
    row_num           integer,
    borough           text,
    bedroom_category  text,
    count_of_rents    text,
    mean              text,
    lower_quartile    text,
    median            text,
    upper_quartile    text
);
