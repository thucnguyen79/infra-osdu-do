-- Legal Database Schema
-- Required for OSDU Core Plus Legal service

-- Create osdu schema
CREATE SCHEMA IF NOT EXISTS osdu;

-- LegalTagOsm table (OSM = Object Storage Model)
CREATE TABLE IF NOT EXISTS osdu."LegalTagOsm" (
    pk BIGSERIAL PRIMARY KEY,
    id VARCHAR(255),
    name VARCHAR(255),
    description TEXT,
    properties JSONB,
    data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255),
    modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_by VARCHAR(255)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_legaltag_name ON osdu."LegalTagOsm"(name);
CREATE INDEX IF NOT EXISTS idx_legaltag_id ON osdu."LegalTagOsm"(id);
