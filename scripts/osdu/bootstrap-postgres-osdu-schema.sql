-- ============================================
-- OSDU PostgreSQL Bootstrap Script
-- Step 24: Storage Service Fix
-- Created: 2026-01-25
-- ============================================

-- ============================================
-- 1. Configure search_path for osduadmin role
-- ============================================
ALTER ROLE osduadmin SET search_path TO osdu, dataecosystem, public;

-- ============================================
-- 2. Configure search_path for databases (optional - role-level takes precedence)
-- ============================================
ALTER DATABASE legal SET search_path TO osdu, dataecosystem, public;
ALTER DATABASE storage SET search_path TO osdu, dataecosystem, public;
ALTER DATABASE schema SET search_path TO osdu, dataecosystem, public;

-- ============================================
-- 3. Create osdu schema in storage database
-- ============================================
\c storage
CREATE SCHEMA IF NOT EXISTS osdu;

-- Create sequences
CREATE SEQUENCE IF NOT EXISTS osdu."LegalTagOsm_pk_seq";
CREATE SEQUENCE IF NOT EXISTS osdu."RecordMetadataOsm_pk_seq";
CREATE SEQUENCE IF NOT EXISTS osdu."SchemaOsm_pk_seq";
CREATE SEQUENCE IF NOT EXISTS osdu."StorageRecord_pk_seq";

-- Create LegalTagOsm table (used by Legal service via shared osm.postgres.datasource)
CREATE TABLE IF NOT EXISTS osdu."LegalTagOsm" (
    pk bigint NOT NULL DEFAULT nextval('osdu."LegalTagOsm_pk_seq"'::regclass),
    id text NOT NULL,
    data jsonb NOT NULL,
    CONSTRAINT "LegalTagOsm_storage_osdu_pkey" PRIMARY KEY (pk),
    CONSTRAINT "LegalTagOsm_storage_osdu_id_key" UNIQUE (id)
);

-- Create RecordMetadataOsm table
CREATE TABLE IF NOT EXISTS osdu."RecordMetadataOsm" (
    pk bigint NOT NULL DEFAULT nextval('osdu."RecordMetadataOsm_pk_seq"'::regclass),
    id text NOT NULL,
    data jsonb NOT NULL,
    CONSTRAINT "RecordMetadataOsm_osdu_pkey" PRIMARY KEY (pk),
    CONSTRAINT "RecordMetadataOsm_osdu_id_key" UNIQUE (id)
);

-- Create SchemaOsm table
CREATE TABLE IF NOT EXISTS osdu."SchemaOsm" (
    pk bigint NOT NULL DEFAULT nextval('osdu."SchemaOsm_pk_seq"'::regclass),
    id text NOT NULL,
    data jsonb NOT NULL,
    CONSTRAINT "SchemaOsm_osdu_pkey" PRIMARY KEY (pk),
    CONSTRAINT "SchemaOsm_osdu_id_key" UNIQUE (id)
);

-- Create StorageRecord table
CREATE TABLE IF NOT EXISTS osdu."StorageRecord" (
    pk bigint NOT NULL DEFAULT nextval('osdu."StorageRecord_pk_seq"'::regclass),
    id text NOT NULL,
    data jsonb NOT NULL,
    CONSTRAINT "StorageRecord_osdu_pkey" PRIMARY KEY (pk),
    CONSTRAINT "StorageRecord_osdu_id_key" UNIQUE (id)
);

-- Grant permissions
GRANT ALL ON SCHEMA osdu TO osduadmin;
GRANT ALL ON ALL TABLES IN SCHEMA osdu TO osduadmin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA osdu TO osduadmin;

-- ============================================
-- 4. Verify
-- ============================================
\echo '=== Tables in storage.osdu schema ==='
\dt osdu.*

\echo '=== search_path for osduadmin ==='
SELECT rolname, rolconfig FROM pg_roles WHERE rolname = 'osduadmin';
