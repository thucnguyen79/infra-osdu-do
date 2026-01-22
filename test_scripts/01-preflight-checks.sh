#!/bin/bash
#===============================================================================
# OSDU Pre-flight Checks Script (Fixed)
# Kiểm tra tất cả services và dependencies trước khi test
#===============================================================================

# Bỏ set -e để script không exit khi có lệnh fail
# set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    PASS=$((PASS + 1))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    FAIL=$((FAIL + 1))
}

check_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    WARN=$((WARN + 1))
}

#===============================================================================
# SECTION 1: KUBERNETES CLUSTER HEALTH
#===============================================================================
print_header "1. KUBERNETES CLUSTER HEALTH"

print_section "1.1 Node Status"
NODES_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || true)
NODES_TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || true)

if [ "$NODES_READY" -eq "$NODES_TOTAL" ] && [ "$NODES_TOTAL" -ge 5 ]; then
    check_pass "All nodes Ready: $NODES_READY/$NODES_TOTAL"
else
    check_fail "Nodes not ready: $NODES_READY/$NODES_TOTAL"
fi

kubectl get nodes -o wide 2>/dev/null || true

print_section "1.2 System Pods (kube-system)"
KUBE_SYSTEM_READY=$(kubectl -n kube-system get pods --no-headers 2>/dev/null | grep -c "Running" || true)
KUBE_SYSTEM_TOTAL=$(kubectl -n kube-system get pods --no-headers 2>/dev/null | wc -l || true)

if [ "$KUBE_SYSTEM_READY" -eq "$KUBE_SYSTEM_TOTAL" ] && [ "$KUBE_SYSTEM_TOTAL" -gt 0 ]; then
    check_pass "kube-system pods: $KUBE_SYSTEM_READY/$KUBE_SYSTEM_TOTAL Running"
else
    check_warn "kube-system pods: $KUBE_SYSTEM_READY/$KUBE_SYSTEM_TOTAL Running"
fi

#===============================================================================
# SECTION 2: INFRASTRUCTURE SERVICES
#===============================================================================
print_header "2. INFRASTRUCTURE SERVICES"

print_section "2.1 Keycloak (osdu-identity)"
KEYCLOAK_READY=$(kubectl -n $NS_IDENTITY get pods -l app=keycloak --no-headers 2>/dev/null | grep -c "1/1.*Running" || true)
if [ "$KEYCLOAK_READY" -ge 1 ]; then
    check_pass "Keycloak: Running ($KEYCLOAK_READY pod)"
else
    check_fail "Keycloak: NOT Running"
fi

print_section "2.2 PostgreSQL (osdu-data)"
POSTGRES_READY=$(kubectl -n $NS_DATA get pods -l app=osdu-postgres --no-headers 2>/dev/null | grep -c "1/1.*Running" || true)
if [ "$POSTGRES_READY" -ge 1 ]; then
    check_pass "PostgreSQL: Running ($POSTGRES_READY pod)"
else
    check_fail "PostgreSQL: NOT Running"
fi

print_section "2.3 OpenSearch (osdu-data)"
OPENSEARCH_READY=$(kubectl -n $NS_DATA get pods -l app=osdu-opensearch --no-headers 2>/dev/null | grep -c "1/1.*Running" || true)
if [ "$OPENSEARCH_READY" -ge 1 ]; then
    check_pass "OpenSearch: Running ($OPENSEARCH_READY pod)"
else
    check_fail "OpenSearch: NOT Running"
fi

print_section "2.4 Redis (osdu-data)"
REDIS_READY=$(kubectl -n $NS_DATA get pods -l app=osdu-redis --no-headers 2>/dev/null | grep -c "1/1.*Running" || true)
if [ "$REDIS_READY" -ge 1 ]; then
    check_pass "Redis: Running ($REDIS_READY pod)"
else
    check_fail "Redis: NOT Running"
fi

print_section "2.5 RabbitMQ (osdu-data)"
RABBITMQ_READY=$(kubectl -n $NS_DATA get pods -l app=osdu-rabbitmq --no-headers 2>/dev/null | grep -c "1/1.*Running" || true)
if [ "$RABBITMQ_READY" -ge 1 ]; then
    check_pass "RabbitMQ: Running ($RABBITMQ_READY pod)"
else
    check_fail "RabbitMQ: NOT Running"
fi

print_section "2.6 Redpanda/Kafka (osdu-data)"
REDPANDA_READY=$(kubectl -n $NS_DATA get pods -l app.kubernetes.io/name=redpanda --no-headers 2>/dev/null | grep -c "Running" || true)
if [ "$REDPANDA_READY" -ge 1 ]; then
    check_pass "Redpanda: Running ($REDPANDA_READY pod)"
else
    check_warn "Redpanda: NOT Running (may use RabbitMQ instead)"
fi

print_section "2.7 Ceph S3 Storage (rook-ceph)"
CEPH_READY=$(kubectl -n $NS_CEPH get pods -l app=rook-ceph-rgw --no-headers 2>/dev/null | grep -c "Running" || true)
if [ "$CEPH_READY" -ge 1 ]; then
    check_pass "Ceph RGW: Running ($CEPH_READY pod)"
else
    check_fail "Ceph RGW: NOT Running"
fi

#===============================================================================
# SECTION 3: OSDU CORE SERVICES
#===============================================================================
print_header "3. OSDU CORE SERVICES"

OSDU_SERVICES="partition entitlements legal schema storage file search indexer"
SVC_NUM=1

for svc in $OSDU_SERVICES; do
    print_section "3.$SVC_NUM $svc service"
    SVC_READY=$(kubectl -n $NS_CORE get pods -l app=osdu-$svc --no-headers 2>/dev/null | grep -c "1/1.*Running" || true)
    if [ "$SVC_READY" -ge 1 ]; then
        check_pass "osdu-$svc: Running ($SVC_READY pod)"
    else
        check_fail "osdu-$svc: NOT Running"
    fi
    SVC_NUM=$((SVC_NUM + 1))
done

#===============================================================================
# SECTION 4: SERVICE CONNECTIVITY
#===============================================================================
print_header "4. SERVICE CONNECTIVITY (via toolbox)"

TOOLBOX="kubectl -n $NS_CORE exec deploy/osdu-toolbox --"

print_section "4.1 Keycloak OIDC Endpoint"
KC_STATUS=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
    "http://keycloak.$NS_IDENTITY.svc.cluster.local/realms/osdu/.well-known/openid-configuration" 2>/dev/null || echo "000")
if [ "$KC_STATUS" = "200" ]; then
    check_pass "Keycloak OIDC: HTTP $KC_STATUS"
else
    check_fail "Keycloak OIDC: HTTP $KC_STATUS"
fi

print_section "4.2 OpenSearch Cluster Health"
OS_HEALTH=$($TOOLBOX curl -s "http://osdu-opensearch.$NS_DATA.svc.cluster.local:9200/_cluster/health" 2>/dev/null || echo '{"status":"error"}')
OS_STATUS=$(echo "$OS_HEALTH" | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "error")
if [ "$OS_STATUS" = "green" ] || [ "$OS_STATUS" = "yellow" ]; then
    check_pass "OpenSearch cluster: $OS_STATUS"
else
    check_fail "OpenSearch cluster: $OS_STATUS"
fi

print_section "4.3 RabbitMQ Management API"
RMQ_STATUS=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" -u osdu:osdu123 \
    "http://osdu-rabbitmq.$NS_DATA.svc.cluster.local:15672/api/overview" 2>/dev/null || echo "000")
if [ "$RMQ_STATUS" = "200" ]; then
    check_pass "RabbitMQ Management: HTTP $RMQ_STATUS"
else
    check_warn "RabbitMQ Management: HTTP $RMQ_STATUS"
fi

#===============================================================================
# SECTION 5: ACCESS TOKEN
#===============================================================================
print_header "5. ACCESS TOKEN"

print_section "5.1 Acquire Access Token"
TOKEN=$($TOOLBOX curl -s -X POST \
    "http://keycloak.$NS_IDENTITY.svc.cluster.local/realms/osdu/protocol/openid-connect/token" \
    -d "grant_type=password" \
    -d "client_id=osdu-cli" \
    -d "username=test" \
    -d "password=Test@12345" 2>/dev/null | grep -o '"access_token":"[^"]*' | cut -d'"' -f4 || true)

if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    check_pass "Access token acquired"
    echo "  Token (first 50 chars): ${TOKEN:0:50}..."
else
    check_fail "Failed to get access token"
fi

#===============================================================================
# SECTION 6: OSDU SERVICE HEALTH
#===============================================================================
print_header "6. OSDU SERVICE HEALTH ENDPOINTS"

if [ -n "$TOKEN" ]; then
    HEALTH_CHECKS="partition:8080/api/partition/v1/info entitlements:8080/api/entitlements/v2/info legal:8080/api/legal/v1/info schema:8080/api/schema-service/v1/info storage:8080/api/storage/v2/info file:8080/api/file/v2/info search:8080/api/search/v2/info indexer:8080/actuator/health"
    
    for check in $HEALTH_CHECKS; do
        SVC_NAME=$(echo $check | cut -d: -f1)
        ENDPOINT="http://osdu-$check"
        print_section "6.x $SVC_NAME health"
        
        HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
            "$ENDPOINT" \
            -H "Authorization: Bearer $TOKEN" \
            -H "data-partition-id: osdu" 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" = "200" ]; then
            check_pass "osdu-$SVC_NAME: HTTP $HTTP_CODE"
        elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
            check_warn "osdu-$SVC_NAME: HTTP $HTTP_CODE (service up, auth issue)"
        else
            check_fail "osdu-$SVC_NAME: HTTP $HTTP_CODE"
        fi
    done
else
    check_fail "Skipping health checks - no token"
fi

#===============================================================================
# SECTION 7: PARTITION CHECK
#===============================================================================
print_header "7. PARTITION STATUS"

if [ -n "$TOKEN" ]; then
    print_section "7.1 List Partitions"
    PARTITIONS=$($TOOLBOX curl -s \
        "http://osdu-partition:8080/api/partition/v1/partitions" \
        -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "[]")
    
    if echo "$PARTITIONS" | grep -q "osdu"; then
        check_pass "Partition 'osdu' exists"
        echo "  Partitions: $PARTITIONS"
    else
        check_fail "Partition 'osdu' NOT found"
    fi
    
    print_section "7.2 Partition Properties"
    PROPS=$($TOOLBOX curl -s \
        "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: osdu" 2>/dev/null || echo "{}")
    PROPS_COUNT=$(echo "$PROPS" | grep -o '"value":' | wc -l || true)
    
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
echo -e "  ${GREEN}PASSED:${NC}   $PASS"
echo -e "  ${YELLOW}WARNINGS:${NC} $WARN"
echo -e "  ${RED}FAILED:${NC}   $FAIL"
echo ""

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
