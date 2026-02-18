#!/bin/bash
#===============================================================================
# OSDU POC - Comprehensive E2E Test Suite
# Usage: ./scripts/osdu-e2e-test.sh [--cleanup]
#===============================================================================

CLEANUP=false
if [ "$1" == "--cleanup" ]; then
    CLEANUP=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
WARN=0

# Functions
log_header() { echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"; }
log_section() { echo -e "\n${YELLOW}--- $1 ---${NC}"; }
log_pass() { echo -e "${GREEN}✅ PASS:${NC} $1"; ((PASS++)) || true; }
log_fail() { echo -e "${RED}❌ FAIL:${NC} $1"; ((FAIL++)) || true; }
log_warn() { echo -e "${YELLOW}⚠️  WARN:${NC} $1"; ((WARN++)) || true; }
log_info() { echo -e "   ℹ️  $1"; }

TOOLBOX="kubectl -n osdu-core exec deploy/osdu-toolbox --"

log_header "OSDU POC - COMPREHENSIVE E2E TEST"
echo "Date: $(date)"
echo "Cleanup mode: $CLEANUP"

#===============================================================================
# PHASE 1: INFRASTRUCTURE
#===============================================================================
log_header "PHASE 1: INFRASTRUCTURE CHECK"

log_section "1.1 Kubernetes Cluster"
NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
if [ "$NODES" -eq "$READY_NODES" ] && [ "$NODES" -gt 0 ]; then
    log_pass "Kubernetes nodes: $READY_NODES/$NODES Ready"
else
    log_fail "Kubernetes nodes: $READY_NODES/$NODES Ready"
fi

log_section "1.2 OSDU Core Pods"
OSDU_RUNNING=$(kubectl -n osdu-core get pods --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [ "$OSDU_RUNNING" -ge 8 ]; then
    log_pass "OSDU Core pods: $OSDU_RUNNING Running"
else
    log_warn "OSDU Core pods: $OSDU_RUNNING Running"
fi

log_section "1.3 OSDU Data Pods"
DATA_RUNNING=$(kubectl -n osdu-data get pods --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [ "$DATA_RUNNING" -ge 4 ]; then
    log_pass "OSDU Data pods: $DATA_RUNNING Running"
else
    log_warn "OSDU Data pods: $DATA_RUNNING Running"
fi

log_section "1.4 OpenSearch"
OS_HEALTH=$($TOOLBOX curl -s "http://osdu-opensearch.osdu-data:9200/_cluster/health" 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
if [ "$OS_HEALTH" == "green" ] || [ "$OS_HEALTH" == "yellow" ]; then
    log_pass "OpenSearch: $OS_HEALTH"
else
    log_fail "OpenSearch: $OS_HEALTH"
fi

log_section "1.5 RabbitMQ"
RMQ_CHECK=$(kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl status 2>/dev/null | grep -c "rabbit" || echo "0")
if [ "$RMQ_CHECK" -gt 0 ]; then
    log_pass "RabbitMQ: Running"
else
    log_fail "RabbitMQ: Not responding"
fi

log_section "1.6 PostgreSQL"
PG_CHECK=$(kubectl -n osdu-data exec sts/osdu-postgres -- pg_isready -U osduadmin 2>/dev/null | grep -c "accepting" || echo "0")
if [ "$PG_CHECK" -gt 0 ]; then
    log_pass "PostgreSQL: Ready"
else
    log_fail "PostgreSQL: Not ready"
fi

log_section "1.7 Redis"
REDIS_CHECK=$(kubectl -n osdu-data exec deploy/osdu-redis -- redis-cli ping 2>/dev/null || echo "")
if [ "$REDIS_CHECK" == "PONG" ]; then
    log_pass "Redis: PONG"
else
    log_warn "Redis: $REDIS_CHECK"
fi

#===============================================================================
# PHASE 2: AUTHENTICATION
#===============================================================================
log_header "PHASE 2: AUTHENTICATION"

log_section "2.1 Get Access Token"
TOKEN_RESP=$($TOOLBOX curl -s -X POST \
  "http://keycloak.osdu-identity.svc.cluster.local/realms/osdu/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=osdu-cli&username=test&password=Test@12345" 2>/dev/null)

ADMIN_TOKEN=$(echo "$TOKEN_RESP" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -n "$ADMIN_TOKEN" ] && [ ${#ADMIN_TOKEN} -gt 100 ]; then
    log_pass "Token acquired (${#ADMIN_TOKEN} chars)"
else
    log_fail "Token acquisition failed"
    echo "Response: $(echo "$TOKEN_RESP" | head -c 100)"
fi

#===============================================================================
# PHASE 3: OSDU SERVICES
#===============================================================================
log_header "PHASE 3: OSDU SERVICES"

log_section "3.1 Partition Service"
PARTITION_RESP=$($TOOLBOX curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  "http://osdu-partition:8080/api/partition/v1/partitions/osdu" 2>/dev/null)
PARTITION_KEYS=$(echo "$PARTITION_RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$PARTITION_KEYS" -gt 100 ]; then
    log_pass "Partition: $PARTITION_KEYS properties"
else
    log_fail "Partition: $PARTITION_KEYS properties"
fi

log_section "3.2 Entitlements Service"
GROUPS_RESP=$($TOOLBOX curl -s -H "Authorization: Bearer $ADMIN_TOKEN" -H "data-partition-id: osdu" \
  "http://osdu-entitlements:8080/api/entitlements/v2/groups" 2>/dev/null)
GROUPS_COUNT=$(echo "$GROUPS_RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('groups',[])))" 2>/dev/null || echo "0")
if [ "$GROUPS_COUNT" -gt 0 ]; then
    log_pass "Entitlements: $GROUPS_COUNT groups"
else
    log_fail "Entitlements: No groups"
fi

log_section "3.3 Legal Service"
LEGAL_RESP=$($TOOLBOX curl -s -H "Authorization: Bearer $ADMIN_TOKEN" -H "data-partition-id: osdu" \
  "http://osdu-legal:8080/api/legal/v1/legaltags" 2>/dev/null)
LEGAL_COUNT=$(echo "$LEGAL_RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('legalTags',[])))" 2>/dev/null || echo "0")
if [ "$LEGAL_COUNT" -gt 0 ]; then
    log_pass "Legal: $LEGAL_COUNT tags"
else
    log_fail "Legal: No tags"
fi

log_section "3.4 Schema Service"
SCHEMA_RESP=$($TOOLBOX curl -s -H "Authorization: Bearer $ADMIN_TOKEN" -H "data-partition-id: osdu" \
  "http://osdu-schema:8080/api/schema-service/v1/schema?limit=100" 2>/dev/null)
SCHEMA_COUNT=$(echo "$SCHEMA_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('totalCount',0))" 2>/dev/null || echo "0")
if [ "$SCHEMA_COUNT" -gt 0 ]; then
    log_pass "Schema: $SCHEMA_COUNT schemas"
else
    log_warn "Schema: No schemas"
fi

log_section "3.5 Storage Service"
STORAGE_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" -H "data-partition-id: osdu" \
  "http://osdu-storage:8080/api/storage/v2/records/osdu:test:dummy" 2>/dev/null)
if [ "$STORAGE_CODE" == "404" ] || [ "$STORAGE_CODE" == "200" ]; then
    log_pass "Storage: Responding (HTTP $STORAGE_CODE)"
else
    log_fail "Storage: HTTP $STORAGE_CODE"
fi

log_section "3.6 Search Service"
SEARCH_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" -X POST \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "data-partition-id: osdu" -H "Content-Type: application/json" \
  "http://osdu-search:8080/api/search/v2/query" -d '{"kind":"*:*:*:*","limit":1}' 2>/dev/null)
if [ "$SEARCH_CODE" == "200" ]; then
    log_pass "Search: Responding"
else
    log_fail "Search: HTTP $SEARCH_CODE"
fi

#===============================================================================
# PHASE 4: OPENSEARCH
#===============================================================================
log_header "PHASE 4: OPENSEARCH INDICES"

log_section "4.1 OSDU Indices"
INDEX_COUNT=$($TOOLBOX curl -s "http://osdu-opensearch.osdu-data:9200/_cat/indices" 2>/dev/null | grep -c "osdu-wks" || echo "0")
if [ "$INDEX_COUNT" -gt 0 ]; then
    log_pass "OpenSearch: $INDEX_COUNT OSDU indices"
    $TOOLBOX curl -s "http://osdu-opensearch.osdu-data:9200/_cat/indices?v&s=index" 2>/dev/null | grep "osdu-wks" | while read line; do
        log_info "$line"
    done
else
    log_warn "No OSDU indices"
fi

#===============================================================================
# PHASE 5: S3 BUCKETS
#===============================================================================
log_header "PHASE 5: S3 BUCKETS"

log_section "5.1 List Buckets"
S3_ACCESS=$(kubectl -n rook-ceph get secret rook-ceph-object-user-osdu-store-osdu-s3-user -o jsonpath='{.data.AccessKey}' 2>/dev/null | base64 -d)
S3_SECRET=$(kubectl -n rook-ceph get secret rook-ceph-object-user-osdu-store-osdu-s3-user -o jsonpath='{.data.SecretKey}' 2>/dev/null | base64 -d)

if [ -n "$S3_ACCESS" ]; then
    BUCKETS=$($TOOLBOX python3 << PYEOF 2>/dev/null
import boto3
from botocore.client import Config
try:
    s3 = boto3.client('s3',
        endpoint_url='http://rook-ceph-rgw-osdu-store.rook-ceph:80',
        aws_access_key_id='$S3_ACCESS',
        aws_secret_access_key='$S3_SECRET',
        config=Config(signature_version='s3v4'))
    for b in s3.list_buckets().get('Buckets', []):
        print(b['Name'])
except Exception as e:
    print(f"ERROR: {e}")
PYEOF
)
    BUCKET_COUNT=$(echo "$BUCKETS" | grep -v "ERROR" | wc -l)
    if [ "$BUCKET_COUNT" -gt 0 ]; then
        log_pass "S3 Buckets: $BUCKET_COUNT found"
        echo "$BUCKETS" | while read b; do log_info "- $b"; done
    else
        log_fail "Cannot list buckets"
    fi
else
    log_fail "S3 credentials not found"
fi

#===============================================================================
# PHASE 6: E2E DATA FLOW
#===============================================================================
log_header "PHASE 6: E2E DATA FLOW TEST"

TIMESTAMP=$(date +%s)
TEST_KIND="osdu:wks:master-data--Well:1.0.0"
TEST_NAME="E2E-TEST-$TIMESTAMP"

log_section "6.1 Create Test Record"
CREATE_RESP=$($TOOLBOX curl -s -X PUT \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "data-partition-id: osdu" \
  -H "Content-Type: application/json" \
  "http://osdu-storage:8080/api/storage/v2/records" \
  -d "[{
    \"kind\": \"$TEST_KIND\",
    \"acl\": {\"viewers\": [\"data.default.viewers@osdu.osdu.local\"], \"owners\": [\"data.default.owners@osdu.osdu.local\"]},
    \"legal\": {\"legaltags\": [\"osdu-public-usa-dataset\"], \"otherRelevantDataCountries\": [\"US\"]},
    \"data\": {\"FacilityName\": \"$TEST_NAME\", \"FacilityID\": \"e2e-$TIMESTAMP\"}
  }]" 2>/dev/null)

RECORD_ID=$(echo "$CREATE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('recordIds',[''])[0])" 2>/dev/null || echo "")

if [ -n "$RECORD_ID" ] && [ "$RECORD_ID" != "" ]; then
    log_pass "Record created: $RECORD_ID"
else
    log_fail "Record creation failed: $(echo "$CREATE_RESP" | head -c 100)"
fi

log_section "6.2 Wait for Indexing (20s)"
echo -n "   Waiting: "
for i in $(seq 1 20); do echo -n "."; sleep 1; done
echo " Done"

log_section "6.3 Check Queue"
QUEUE_MSG=$(kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_queues name messages 2>/dev/null | grep "indexer-records-changed" | awk '{print $2}' || echo "?")
log_info "Indexer queue: $QUEUE_MSG pending"

log_section "6.4 Search Results"
SEARCH_RESP=$($TOOLBOX curl -s -X POST \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "data-partition-id: osdu" \
  -H "Content-Type: application/json" \
  "http://osdu-search:8080/api/search/v2/query" \
  -d "{\"kind\": \"$TEST_KIND\", \"limit\": 100}" 2>/dev/null)

SEARCH_TOTAL=$(echo "$SEARCH_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('totalCount',0))" 2>/dev/null || echo "0")

if [ "$SEARCH_TOTAL" -gt 0 ]; then
    log_pass "Search: $SEARCH_TOTAL records"
    echo "$SEARCH_RESP" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for r in data.get('results',[])[:5]:
    print(f\"   ℹ️  {r.get('id','?')}: {r.get('data',{}).get('FacilityName','N/A')}\")
" 2>/dev/null || true
else
    log_fail "Search: No records"
fi

log_section "6.5 Verify Test Record"
if echo "$SEARCH_RESP" | grep -q "$TEST_NAME"; then
    log_pass "Test record indexed successfully"
else
    log_warn "Test record not yet in search (may need more time)"
fi

#===============================================================================
# PHASE 7: CLEANUP (Optional)
#===============================================================================
if [ "$CLEANUP" == "true" ] && [ -n "$RECORD_ID" ]; then
    log_header "PHASE 7: CLEANUP"
    
    log_section "7.1 Delete Test Record"
    DELETE_RESP=$($TOOLBOX curl -s -X POST \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "data-partition-id: osdu" \
      -H "Content-Type: application/json" \
      "http://osdu-storage:8080/api/storage/v2/records/delete" \
      -d "[\"$RECORD_ID\"]" 2>/dev/null)
    
    if echo "$DELETE_RESP" | grep -q "notFound\|error"; then
        log_warn "Delete may have failed: $(echo "$DELETE_RESP" | head -c 100)"
    else
        log_pass "Record deleted: $RECORD_ID"
    fi
    
    log_section "7.2 Wait for Index Update (10s)"
    sleep 10
    
    log_section "7.3 Verify Deletion"
    VERIFY_DELETE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "data-partition-id: osdu" \
      "http://osdu-storage:8080/api/storage/v2/records/$RECORD_ID" 2>/dev/null)
    
    if [ "$VERIFY_DELETE" == "404" ]; then
        log_pass "Record confirmed deleted"
    else
        log_warn "Record still exists (HTTP $VERIFY_DELETE)"
    fi
fi

#===============================================================================
# SUMMARY
#===============================================================================
log_header "TEST SUMMARY"

TOTAL=$((PASS + FAIL + WARN))
echo ""
echo -e "${GREEN}✅ PASSED: $PASS${NC}"
echo -e "${RED}❌ FAILED: $FAIL${NC}"
echo -e "${YELLOW}⚠️  WARNINGS: $WARN${NC}"
echo "   TOTAL: $TOTAL tests"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  🎉 ALL CRITICAL TESTS PASSED!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  ⚠️  SOME TESTS NEED ATTENTION${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
fi

echo ""
echo "Usage:"
echo "  ./scripts/osdu-e2e-test.sh           # Run test, keep test record"
echo "  ./scripts/osdu-e2e-test.sh --cleanup # Run test, delete test record after"
