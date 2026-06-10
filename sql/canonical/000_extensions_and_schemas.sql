-- LALA-next canonical SQL baseline.
-- Shared migrations must be non-destructive.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS locallink;
CREATE SCHEMA IF NOT EXISTS daangn;
CREATE SCHEMA IF NOT EXISTS monitoring;

