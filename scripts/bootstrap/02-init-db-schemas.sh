#!/bin/bash
# 02-init-db-schemas.sh - Initialize OSDU database schemas
# Usage: ./02-init-db-schemas.sh

set -e

TOOLBOX_POD="deploy/osdu-toolbox"
NAMESPACE="osdu-core"
PG_HOST="osdu-postgres.osdu-data.svc.cluster.local"
PG_USER="osduadmin"
PG_PASS="CHANGE_ME_STRONG"

echo "=== Initializing Entitlements Database Schema ==="

kubectl -n $NAMESPACE exec -it $TOOLBOX_POD -- bash -c "
PGPASSWORD=$PG_PASS psql -h $PG_HOST -U $PG_USER -d entitlements << 'EOF'
-- Entitlements schema
CREATE TABLE IF NOT EXISTS member (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    partition_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS \"group\" (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    partition_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS member_to_group (
    id BIGSERIAL PRIMARY KEY,
    member_id BIGINT NOT NULL REFERENCES member(id) ON DELETE CASCADE,
    group_id BIGINT NOT NULL REFERENCES \"group\"(id) ON DELETE CASCADE,
    role VARCHAR(50) DEFAULT 'MEMBER',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(member_id, group_id)
);

CREATE TABLE IF NOT EXISTS embedded_group (
    id BIGSERIAL PRIMARY KEY,
    parent_id BIGINT NOT NULL REFERENCES \"group\"(id) ON DELETE CASCADE,
    child_id BIGINT NOT NULL REFERENCES \"group\"(id) ON DELETE CASCADE,
    UNIQUE(parent_id, child_id)
);

CREATE INDEX IF NOT EXISTS idx_member_email ON member(email);
CREATE INDEX IF NOT EXISTS idx_member_partition ON member(partition_id);
CREATE INDEX IF NOT EXISTS idx_group_email ON \"group\"(email);
CREATE INDEX IF NOT EXISTS idx_group_partition ON \"group\"(partition_id);
CREATE INDEX IF NOT EXISTS idx_m2g_member ON member_to_group(member_id);
CREATE INDEX IF NOT EXISTS idx_m2g_group ON member_to_group(group_id);

SELECT 'Entitlements schema OK';
EOF
"

echo "=== Initializing Legal Database Schema ==="

kubectl -n $NAMESPACE exec -it $TOOLBOX_POD -- bash -c "
PGPASSWORD=$PG_PASS psql -h $PG_HOST -U $PG_USER -d legal << 'EOF'
-- Legal schema
CREATE SCHEMA IF NOT EXISTS osdu;

CREATE TABLE IF NOT EXISTS osdu.\"LegalTagOsm\" (
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

CREATE INDEX IF NOT EXISTS idx_legaltag_name ON osdu.\"LegalTagOsm\"(name);

SELECT 'Legal schema OK';
EOF
"

echo "=== All database schemas initialized ==="
