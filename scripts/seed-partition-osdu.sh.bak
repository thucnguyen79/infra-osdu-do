#!/bin/bash
# =============================================================================
# OSDU Partition "osdu" Seeding Script
# =============================================================================
# File: scripts/seed-partition-osdu.sh
# Mục đích: Tạo partition "osdu" với tất cả properties cần thiết cho OSDU Core Services
# Chạy từ: ToolServer01 (trong VPN)
# Điều kiện: Tất cả OSDU Core services đang Running
# =============================================================================

set -e

NAMESPACE="${NAMESPACE:-osdu-core}"
TOOLBOX="kubectl -n $NAMESPACE exec deploy/osdu-toolbox --"
PARTITION_API="http://osdu-partition:8080/api/partition/v1"
PARTITION_ID="${PARTITION_ID:-osdu}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== OSDU Partition Seeding Script ===${NC}"
echo "Namespace: $NAMESPACE"
echo "Partition ID: $PARTITION_ID"
echo ""

# -----------------------------------------------------------------------------
# 1. Check prerequisites
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/4] Checking prerequisites...${NC}"

# Check toolbox is running
if ! kubectl -n $NAMESPACE get deploy osdu-toolbox &>/dev/null; then
    echo -e "${RED}ERROR: osdu-toolbox deployment not found${NC}"
    exit 1
fi

# Check partition service is running
if ! $TOOLBOX curl -s "$PARTITION_API/partitions" &>/dev/null; then
    echo -e "${RED}ERROR: Cannot reach Partition service${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}"
echo ""

# -----------------------------------------------------------------------------
# 2. Check if partition already exists
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[2/4] Checking if partition '$PARTITION_ID' exists...${NC}"

EXISTING=$($TOOLBOX curl -s "$PARTITION_API/partitions" 2>/dev/null)
if echo "$EXISTING" | grep -q "\"$PARTITION_ID\""; then
    echo -e "${YELLOW}⚠ Partition '$PARTITION_ID' already exists. Updating properties...${NC}"
    METHOD="PATCH"
else
    echo "Partition '$PARTITION_ID' does not exist. Creating..."
    METHOD="POST"
fi
echo ""

# -----------------------------------------------------------------------------
# 3. Create/Update partition with properties
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/4] Creating/Updating partition '$PARTITION_ID'...${NC}"

# Build JSON payload
PAYLOAD=$(cat <<'ENDJSON'
{
  "properties": {
    "compliance-ruleset": {"sensitive": false, "value": "shared"},
    "elastic-endpoint": {"sensitive": false, "value": "http://osdu-opensearch.osdu-data:9200"},
    "elastic-username": {"sensitive": false, "value": "admin"},
    "elastic-password": {"sensitive": false, "value": "admin"},
    "storage-account-name": {"sensitive": false, "value": "osdu"},
    "redis-database": {"sensitive": false, "value": "4"},
    
    "entitlements.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/entitlements"},
    "entitlements.datasource.username": {"sensitive": false, "value": "osduadmin"},
    "entitlements.datasource.password": {"sensitive": true, "value": "ENTITLEMENTS_DB_PASSWORD"},
    "entitlements.datasource.schema": {"sensitive": false, "value": "public"},
    
    "legal.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/legal"},
    "legal.datasource.username": {"sensitive": false, "value": "osduadmin"},
    "legal.datasource.password": {"sensitive": true, "value": "LEGAL_DB_PASSWORD"},
    "legal.datasource.schema": {"sensitive": false, "value": "public"},
    
    "storage.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/storage"},
    "storage.datasource.username": {"sensitive": false, "value": "osduadmin"},
    "storage.datasource.password": {"sensitive": true, "value": "STORAGE_DB_PASSWORD"},
    "storage.datasource.schema": {"sensitive": false, "value": "public"},
    
    "schema.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/schema"},
    "schema.datasource.username": {"sensitive": false, "value": "osduadmin"},
    "schema.datasource.password": {"sensitive": true, "value": "SCHEMA_DB_PASSWORD"},
    "schema.datasource.schema": {"sensitive": false, "value": "public"},
    
    "file.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/file"},
    "file.datasource.username": {"sensitive": false, "value": "osduadmin"},
    "file.datasource.password": {"sensitive": true, "value": "FILE_DB_PASSWORD"},
    "file.datasource.schema": {"sensitive": false, "value": "public"}
  }
}
ENDJSON
)

# Execute API call
RESPONSE=$($TOOLBOX curl -s -X POST "$PARTITION_API/partitions/$PARTITION_ID" \
  -H "Content-Type: application/json" \
  -H "data-partition-id: $PARTITION_ID" \
  -d "$PAYLOAD" 2>&1)

if echo "$RESPONSE" | grep -qE "error|Error|ERROR"; then
    echo -e "${RED}ERROR: Failed to create/update partition${NC}"
    echo "$RESPONSE"
    exit 1
fi

echo -e "${GREEN}✓ Partition '$PARTITION_ID' created/updated successfully${NC}"
echo ""

# -----------------------------------------------------------------------------
# 4. Verify
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[4/4] Verifying partition...${NC}"

echo "Listing all partitions:"
$TOOLBOX curl -s "$PARTITION_API/partitions" | jq .

echo ""
echo "Partition '$PARTITION_ID' properties count:"
$TOOLBOX curl -s "$PARTITION_API/partitions/$PARTITION_ID" | jq 'keys | length'

echo ""
echo -e "${GREEN}=== SEEDING COMPLETE ===${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: Restart services to pick up new properties:${NC}"
echo "kubectl -n $NAMESPACE rollout restart deploy osdu-entitlements osdu-storage osdu-legal osdu-schema osdu-file"
echo ""
echo -e "${YELLOW}Then verify services are healthy:${NC}"
echo "kubectl -n $NAMESPACE get pods"
