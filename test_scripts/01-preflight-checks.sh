#!/bin/bash
#===============================================================================
# OSDU Pre-flight Checks Script
# Kiểm tra tất cả services và dependencies trước khi test
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Namespaces
NS_CORE="osdu-core"
NS_DATA="osdu-data"
NS_IDENTITY="osdu-identity"
NS_CEPH="rook-ceph"

# Counters
PASS=0
FAIL=0
WARN=0

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_section() {
    echo ""
    echo -e "${YELLOW}▶ $1${NC}"
    echo "───────────────────────────────────────────────────────────────"
}

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASS++))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((FAIL++))
}

check_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    ((WARN++))
}

#===============================================================================
# SECTION 1: KUBERNETES CLUSTER HEALTH
#===============================================================================
print_header "1. KUBERNETES CLUSTER HEALTH"

print_section "1.1 Node Status"
NODES_READY=$(kubectl get nodes --no-headers | grep -c " Ready" || echo "0")
NODES_TOTAL=$(kubectl get nodes --no-headers | wc -l)

if [ "$NODES_READY" -eq "$NODES_TOTAL" ] && [ "$NODES_TOTAL" -ge 5 ]; then
    check_pass "All nodes Ready: $NODES_READY/$NODES_TOTAL"
else
    check_fail "Nodes not ready: $NODES_READY/$NODES_TOTAL"
fi

kubectl get nodes -o wide

print_section "1.2 System Pods (kube-system)"
KUBE_SYSTEM_READY=$(kubectl -n kube-system get pods --no-headers | grep -c "Running" || echo "0")
KUBE_SYSTEM_TOTAL=$(kubectl -n kube-system get pods --no-headers | wc -l)

if [ "$KUBE_SYSTEM_READY" -eq "$KUBE_SYSTEM_TOTAL" ]; then
    check_pass "kube-system pods: $KUBE_SYSTEM_READY/$KUBE_SYSTEM_TOTAL Running"
else
    check_warn "kube-system pods: $KUBE_SYSTEM_READY/$KUBE_SYSTEM_TOTAL Running"
fi

#===============================================================================
# SECTION 2: INFRASTRUCTURE SERVICES
#===============================================================================
print_header "2. INFRASTRUCTURE SERVICES"

print_section "2.1 Keycloak (osdu-identity)"
KEYCLOAK_READY=$(kubectl -n $NS_IDENTITY get pods -l app=keycloak --no-headers 2>/dev/null | grep -c "1/1.*Running" || echo "0")
if [ "$KEYCLOAK_READY" -ge 1 ]; then
    check_pass "Keycloak: Running"
else
    check_fail "Keycloak: NOT Running"
fi

print_section "2.2 PostgreSQL (osdu-data)"
POSTGRES_READY=$(kubectl -n $NS_DATA get pods -l app=osdu-postgres --no-headers 2>/dev/null | grep -c "1/1.*Running" || echo "0")
if [ "$POSTGRES_READY" -ge 1 ]; then
    check_pass "PostgreSQL: Running"
else
    check_fail "PostgreSQL: NOT Running"
fi

print_section "2.3 OpenSearch (osdu-data)"
OPENSEARCH_READY=$(kubectl -n $NS_DATA get pods -l app=osdu-opensearch --no-headers 2>/dev/null | grep -c "1/1.*Running" || echo "0")
if [ "$OPENSEARCH_READY" -ge 1 ]; then
    check_pass "OpenSearch: Running"
else
    check_fail "OpenSearch: NOT Running"
fi

print_section "2.4 Redis (osdu-data)"
REDIS_READY=$(kubectl -n $NS_DATA get pods -l app=osdu-redis --no-headers 2>/dev/null | grep -c "1/1.*Running" || echo "0")
if [ "$REDIS_READY" -ge 1 ]; then
    check_pass "Redis: Running"
else
    check_fail "Redis: NOT Running"
fi

print_section "2.5 RabbitMQ (osdu-data)"
RABBITMQ_READY=$(kubectl -n $NS_DATA get pods -l app=osdu-rabbitmq --no-headers 2>/dev/null | grep -c "1/1.*Running" || echo "0")
if [ "$RABBITMQ_READY" -ge 1 ]; then
    check_pass "RabbitMQ: Running"
else
    check_fail "RabbitMQ: NOT Running"
fi

print_section "2.6 Redpanda/Kafka (osdu-data)"
REDPANDA_READY=$(kubectl -n $NS_DATA get pods -l app.kubernetes.io/name=redpanda --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [ "$REDPANDA_READY" -ge 1 ]; then
    check_pass "Redpanda: Running"
else
    check_warn "Redpanda: NOT Running (may use RabbitMQ instead)"
fi

print_section "2.7 Ceph S3 Storage (rook-ceph)"
CEPH_READY=$(kubectl -n $NS_CEPH get pods -l app=rook-ceph-rgw --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [ "$CEPH_READY" -ge 1 ]; then
    check_pass "Ceph RGW: Running"
else
    check_fail "Ceph RGW: NOT Running"
fi

#===============================================================================
# SECTION 3: OSDU CORE SERVICES
#===============================================================================
print_header "3. OSDU CORE SERVICES"

OSDU_SERVICES=("partition" "entitlements" "legal" "schema" "storage" "file" "search" "indexer")

for svc in "${OSDU_SERVICES[@]}"; do
    print_section "3.x $svc service"
    SVC_READY=$(kubectl -n $NS_CORE get pods -l app=osdu-$svc --no-headers 2>/dev/null | grep -c "1/1.*Running" || echo "0")
    if [ "$SVC_READY" -ge 1 ]; then
        check_pass "osdu-$svc: Running"
    else
        check_fail "osdu-$svc: NOT Running"
    fi
done

#===============================================================================
# SECTION 4: NETWORK CONNECTIVITY
#===============================================================================
print_header "4. NETWORK CONNECTIVITY (from toolbox)"

TOOLBOX="kubectl -n $NS_CORE exec deploy/osdu-toolbox --"

print_section "4.1 DNS Resolution"
DNS_TESTS=(
    "osdu-postgres.osdu-data.svc.cluster.local"
    "osdu-opensearch.osdu-data.svc.cluster.local"
    "osdu-redis.osdu-data.svc.cluster.local"
    "osdu-rabbitmq.osdu-data.svc.cluster.local"
    "keycloak.osdu-identity.svc.cluster.local"
    "osdu-partition.osdu-core.svc.cluster.local"
)

for host in "${DNS_TESTS[@]}"; do
    if $TOOLBOX nslookup "$host" > /dev/null 2>&1; then
        check_pass "DNS: $host"
    else
        check_fail "DNS: $host"
    fi
done

print_section "4.2 Service Connectivity"
CONN_TESTS=(
    "osdu-postgres.osdu-data:5432"
    "osdu-opensearch.osdu-data:9200"
    "osdu-redis.osdu-data:6379"
    "osdu-rabbitmq.osdu-data:5672"
)

for endpoint in "${CONN_TESTS[@]}"; do
    HOST=$(echo $endpoint | cut -d: -f1)
    PORT=$(echo $endpoint | cut -d: -f2)
    if $TOOLBOX sh -c "cat < /dev/tcp/$HOST/$PORT" 2>/dev/null; then
        check_pass "TCP: $endpoint"
    else
        # Try nc as fallback
        if $TOOLBOX nc -zv $HOST $PORT 2>&1 | grep -q "succeeded\|open"; then
            check_pass "TCP: $endpoint"
        else
            check_fail "TCP: $endpoint"
        fi
    fi
done

#===============================================================================
# SECTION 5: SERVICE HEALTH ENDPOINTS
#===============================================================================
print_header "5. SERVICE HEALTH ENDPOINTS"

print_section "5.1 Getting Access Token"
TOKEN=$($TOOLBOX curl -s -X POST \
    "http://keycloak.osdu-identity.svc.cluster.local/realms/osdu/protocol/openid-connect/token" \
    -d "grant_type=password" \
    -d "client_id=osdu-cli" \
    -d "username=test" \
    -d "password=Test@12345" 2>/dev/null | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    check_pass "Access token acquired"
    echo "  Token (first 50 chars): ${TOKEN:0:50}..."
else
    check_fail "Failed to get access token"
    echo -e "${RED}  Cannot proceed with health checks without token${NC}"
fi

print_section "5.2 Service Info Endpoints"

if [ -n "$TOKEN" ]; then
    HEALTH_ENDPOINTS=(
        "osdu-partition:8080/api/partition/v1/info"
        "osdu-entitlements:8080/api/entitlements/v2/info"
        "osdu-legal:8080/api/legal/v1/info"
        "osdu-schema:8080/api/schema-service/v1/info"
        "osdu-storage:8080/api/storage/v2/info"
        "osdu-file:8080/api/file/v2/info"
        "osdu-search:8080/api/search/v2/info"
        "osdu-indexer:8080/api/indexer/v2/info"
    )
    
    for endpoint in "${HEALTH_ENDPOINTS[@]}"; do
        SVC_NAME=$(echo $endpoint | cut -d: -f1)
        HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
            "http://$endpoint" \
            -H "Authorization: Bearer $TOKEN" \
            -H "data-partition-id: osdu" 2>/dev/null)
        
        if [ "$HTTP_CODE" = "200" ]; then
            check_pass "$SVC_NAME: HTTP $HTTP_CODE"
        elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
            check_warn "$SVC_NAME: HTTP $HTTP_CODE (Auth issue)"
        else
            check_fail "$SVC_NAME: HTTP $HTTP_CODE"
        fi
    done
fi

#===============================================================================
# SECTION 6: RABBITMQ TOPOLOGY
#===============================================================================
print_header "6. RABBITMQ TOPOLOGY"

print_section "6.1 Exchanges"
EXCHANGES=$($TOOLBOX curl -s -u osdu:osdu123 \
    "http://osdu-rabbitmq.osdu-data:15672/api/exchanges/%2F" 2>/dev/null | grep -o '"name":"[^"]*' | cut -d'"' -f4 | grep -v "^amq\." | grep -v "^$")

REQUIRED_EXCHANGES=("records-changed" "schema-changed" "legaltags-changed" "reprocess" "reindex")
for ex in "${REQUIRED_EXCHANGES[@]}"; do
    if echo "$EXCHANGES" | grep -q "^$ex$"; then
        check_pass "Exchange: $ex"
    else
        check_fail "Exchange: $ex (missing)"
    fi
done

print_section "6.2 Queues"
QUEUES=$($TOOLBOX curl -s -u osdu:osdu123 \
    "http://osdu-rabbitmq.osdu-data:15672/api/queues/%2F" 2>/dev/null | grep -o '"name":"[^"]*' | cut -d'"' -f4)

REQUIRED_QUEUES=("indexer-records-changed" "indexer-schema-changed" "indexer-legaltags-changed")
for q in "${REQUIRED_QUEUES[@]}"; do
    if echo "$QUEUES" | grep -q "$q"; then
        check_pass "Queue: $q"
    else
        check_fail "Queue: $q (missing)"
    fi
done

#===============================================================================
# SECTION 7: OPENSEARCH STATUS
#===============================================================================
print_header "7. OPENSEARCH STATUS"

print_section "7.1 Cluster Health"
OS_HEALTH=$($TOOLBOX curl -s "http://osdu-opensearch.osdu-data:9200/_cluster/health" 2>/dev/null)
OS_STATUS=$(echo "$OS_HEALTH" | grep -o '"status":"[^"]*' | cut -d'"' -f4)

if [ "$OS_STATUS" = "green" ]; then
    check_pass "OpenSearch cluster: $OS_STATUS"
elif [ "$OS_STATUS" = "yellow" ]; then
    check_warn "OpenSearch cluster: $OS_STATUS (single node expected)"
else
    check_fail "OpenSearch cluster: $OS_STATUS"
fi

print_section "7.2 Indices"
INDICES=$($TOOLBOX curl -s "http://osdu-opensearch.osdu-data:9200/_cat/indices?h=index" 2>/dev/null | wc -l)
echo "  Total indices: $INDICES"

#===============================================================================
# SECTION 8: PARTITION STATUS
#===============================================================================
print_header "8. PARTITION STATUS"

if [ -n "$TOKEN" ]; then
    print_section "8.1 List Partitions"
    PARTITIONS=$($TOOLBOX curl -s \
        "http://osdu-partition:8080/api/partition/v1/partitions" \
        -H "Authorization: Bearer $TOKEN" 2>/dev/null)
    
    if echo "$PARTITIONS" | grep -q "osdu"; then
        check_pass "Partition 'osdu' exists"
        echo "  Partitions: $PARTITIONS"
    else
        check_fail "Partition 'osdu' NOT found"
    fi
    
    print_section "8.2 Partition Properties Count"
    PROPS_COUNT=$($TOOLBOX curl -s \
        "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: osdu" 2>/dev/null | grep -o '"[^"]*":' | wc -l)
    
    if [ "$PROPS_COUNT" -ge 20 ]; then
        check_pass "Partition properties: $PROPS_COUNT"
    else
        check_warn "Partition properties: $PROPS_COUNT (expected 20+)"
    fi
fi

#===============================================================================
# SUMMARY
#===============================================================================
print_header "SUMMARY"

echo ""
echo -e "  ${GREEN}PASSED:${NC}  $PASS"
echo -e "  ${YELLOW}WARNINGS:${NC} $WARN"
echo -e "  ${RED}FAILED:${NC}  $FAIL"
echo ""

TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ ALL PRE-FLIGHT CHECKS PASSED - READY FOR TESTING${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    exit 0
elif [ $FAIL -le 2 ]; then
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  ⚠️  MOSTLY READY - $FAIL issues to review${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    exit 1
else
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  ❌ NOT READY FOR TESTING - $FAIL critical issues${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    exit 2
fi
