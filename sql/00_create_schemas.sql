-- 00_create_schemas.sql
-- Schemas for each warehouse layer, plus the logs that every build writes to.
-- Safe to re-run: nothing here is dropped, so load and check history is kept.

CREATE SCHEMA IF NOT EXISTS raw;   -- untouched loads of the source files
CREATE SCHEMA IF NOT EXISTS stg;   -- typed, cleaned, deduplicated
CREATE SCHEMA IF NOT EXISTS core;  -- one row per sale, joined to borough
CREATE SCHEMA IF NOT EXISTS mart;  -- borough-by-year tables and metric views
CREATE SCHEMA IF NOT EXISTS qa;    -- data quality results

-- One row per source file loaded into the raw layer.
CREATE TABLE IF NOT EXISTS raw.load_log (
    run_id       text        NOT NULL,
    table_name   text        NOT NULL,
    source_file  text        NOT NULL,
    file_bytes   bigint,
    file_sha256  text,
    file_rows    bigint,              -- data rows counted in the file itself
    loaded_rows  bigint,              -- rows the database accepted
    loaded_at    timestamptz NOT NULL DEFAULT now()
);

-- One row per data quality check, from every layer.
-- status is 'pass', 'fail' or 'info'; a 'fail' stops the build.
CREATE TABLE IF NOT EXISTS qa.check_log (
    run_id      text        NOT NULL,
    layer       text        NOT NULL,
    check_name  text        NOT NULL,
    subject     text,                 -- table or file the check ran against
    status      text        NOT NULL CHECK (status IN ('pass', 'fail', 'info')),
    expected    text,
    observed    text,
    detail      text,
    checked_at  timestamptz NOT NULL DEFAULT now()
);
