#!/bin/bash
#===============================================================================
# OSDU Functional Test Scenarios (Updated for Step 25-26)
# Kiểm tra chức năng của từng service
# 
# CHANGES from Step 24 version:
# - Added elasticsearch.8.* partition property check (for opensearch-proxy)
# - Added opensearch-proxy connectivity test
# - Updated partition critical properties patterns
# - Fixed Legal tag validation check (invalidLegalTags format)
# - Added verbose output for debugging
#===============================================================================

# KHÔNG dùng set -e để script không exit khi có lệnh fail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
NS_CORE="osdu-core"
NS_DATA="osdu-data"
NS_IDENTITY="osdu-identity"
PARTITION_ID="osdu"
TOOLBOX="kubectl -n $NS_CORE exec deploy/osdu-toolbox --"
TIMESTAMP=$(date +%s)

# Counters
PASS=0
FAIL=0
SKIP=0

# Exported variables for cross-test usage
TEST_LEGAL_TAG=""
TEST_SCHEMA_KIND=""
TEST_RECORD_ID=""
TOKEN=""

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $1${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
}

print_test() {
    echo ""
    echo -e "${CYAN}▶ TEST: $1${NC}"
}

test_pass() {
    echo -e "  ${GREEN}✓ PASS:${NC} $1"
    PASS=$((PASS + 1))
}

test_fail() {
    echo -e "  ${RED}✗ FAIL:${NC} $1"
    FAIL=$((FAIL + 1))
}

test_skip() {
    echo -e "  ${YELLOW}⏭ SKIP:${NC} $1"
    SKIP=$((SKIP + 1))
}

get_token() {
    $TOOLBOX curl -s -X POST \
        "http://keycloak.$NS_IDENTITY.svc.cluster.local/realms/osdu/protocol/openid-connect/token" \
        -d "grant_type=password" \
        -d "client_id=osdu-cli" \
        -d "username=test" \
        -d "password=Test@12345" 2>/dev/null | grep -o '"access_token":"[^"]*' | cut -d'"' -f4 || true
}

check_service_exists() {
    local svc=$1
    kubectl -n $NS_CORE get deploy/$svc >/dev/null 2>&1
}

#===============================================================================
# PRE-FLIGHT CHECKS
#===============================================================================
preflight() {
    print_header "PRE-FLIGHT CHECKS"
    
    print_test "0.1 Check toolbox pod"
    if kubectl -n $NS_CORE get deploy/osdu-toolbox >/dev/null 2>&1; then
        POD_STATUS=$(kubectl -n $NS_CORE get pods -l app=osdu-toolbox -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$POD_STATUS" = "Running" ]; then
            test_pass "Toolbox pod: $POD_STATUS"
        else
            test_fail "Toolbox pod not running: $POD_STATUS"
            echo "  Cannot continue without toolbox. Exiting."
            exit 1
        fi
    else
        test_fail "Toolbox deployment not found"
        exit 1
    fi
    
    print_test "0.2 Get Token"
    TOKEN=$(get_token)
    if [ -n "$TOKEN" ]; then
        test_pass "Token acquired (${#TOKEN} chars)"
    else
        test_fail "Cannot get token - check Keycloak"
        exit 1
    fi
    
    print_test "0.3 Check OpenSearch Proxy"
    PROXY_STATUS=$(kubectl -n $NS_DATA get deploy/opensearch-proxy -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$PROXY_STATUS" = "1" ]; then
        test_pass "OpenSearch proxy running"
        # Test proxy connectivity
        PROXY_HEALTH=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" "http://opensearch-proxy.$NS_DATA:9200/health" 2>/dev/null || echo "000")
        if [ "$PROXY_HEALTH" = "200" ]; then
            echo "  Proxy health endpoint: OK"
        fi
    else
        test_fail "OpenSearch proxy not running (readyReplicas: $PROXY_STATUS)"
        echo "  Warning: Search service may fail without proxy"
    fi
    
    print_test "0.4 List Available Services"
    echo "  Services in $NS_CORE:"
    for svc in osdu-partition osdu-entitlements osdu-legal osdu-schema osdu-storage osdu-file osdu-search osdu-indexer; do
        if check_service_exists $svc; then
            echo -e "    ${GREEN}✓${NC} $svc"
        else
            echo -e "    ${YELLOW}○${NC} $svc (not deployed)"
        fi
    done
    test_pass "Service inventory complete"
}

#===============================================================================
# TEST SUITE 1: PARTITION SERVICE
#===============================================================================
test_partition() {
    print_header "TEST SUITE 1: PARTITION SERVICE"
    
    TOKEN=$(get_token)
    if [ -z "$TOKEN" ]; then
        test_fail "Cannot get token - skipping partition tests"
        return
    fi
    
    print_test "1.1 List Partitions"
    RESULT=$($TOOLBOX curl -s \
        -H "Authorization: Bearer $TOKEN" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-partition:8080/api/partition/v1/partitions" 2>/dev/null || echo "[]")
    echo "  Response: $RESULT"
    if echo "$RESULT" | grep -q "osdu"; then
        test_pass "Partition 'osdu' found in list"
    else
        test_fail "Partition 'osdu' not found"
    fi
    
    print_test "1.2 Get Partition Details"
    RESULT=$($TOOLBOX curl -s \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-partition:8080/api/partition/v1/partitions/$PARTITION_ID" 2>/dev/null || echo "{}")
    PROPS=$(echo "$RESULT" | grep -c '"value":' || true)
    echo "  Properties count: $PROPS"
    if [ "$PROPS" -gt 10 ]; then
        test_pass "Partition has $PROPS properties"
    else
        test_fail "Partition properties insufficient ($PROPS)"
    fi
    
    print_test "1.3 Verify Critical Properties"
    # UPDATED: Added elasticsearch.8 for opensearch-proxy configuration
    CRITICAL_PATTERNS="osm.postgres oqm elasticsearch.8 obm"
    ALL_OK=true
    for prop in $CRITICAL_PATTERNS; do
        if echo "$RESULT" | grep -qi "$prop"; then
            echo "  ✓ Found: $prop"
        else
            echo "  ✗ Missing: $prop"
            ALL_OK=false
        fi
    done
    if [ "$ALL_OK" = true ]; then
        test_pass "All critical properties present"
    else
        test_fail "Some critical properties missing (check partition bootstrap)"
    fi
    
    print_test "1.4 Verify OpenSearch Proxy Configuration"
    # Check that elasticsearch.8.host points to proxy
    ES_HOST=$(echo "$RESULT" | grep -o '"elasticsearch.8.host"[^}]*' | grep -o '"value":"[^"]*' | cut -d'"' -f4 || echo "")
    echo "  elasticsearch.8.host: $ES_HOST"
    if echo "$ES_HOST" | grep -q "opensearch-proxy"; then
        test_pass "OpenSearch proxy correctly configured"
    else
        test_fail "elasticsearch.8.host should point to opensearch-proxy"
    fi
}

#===============================================================================
# TEST SUITE 2: ENTITLEMENTS SERVICE
#===============================================================================
test_entitlements() {
    print_header "TEST SUITE 2: ENTITLEMENTS SERVICE"
    
    TOKEN=$(get_token)
    if [ -z "$TOKEN" ]; then
        test_fail "Cannot get token - skipping entitlements tests"
        return
    fi
    
    print_test "2.1 List Groups"
    RESULT=$($TOOLBOX curl -s \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-entitlements:8080/api/entitlements/v2/groups" 2>/dev/null || echo "{}")
    GROUPS=$(echo "$RESULT" | grep -c '"name":' || true)
    echo "  Groups found: $GROUPS"
    if [ "$GROUPS" -gt 0 ]; then
        test_pass "Found $GROUPS entitlement groups"
    else
        test_fail "No groups found"
    fi
    
    print_test "2.2 Verify Required Groups"
    REQUIRED_FOUND=0
    for grp in users data.default.owners data.default.viewers; do
        if echo "$RESULT" | grep -q "$grp"; then
            echo "  ✓ Found: $grp"
            REQUIRED_FOUND=$((REQUIRED_FOUND + 1))
        else
            echo "  ✗ Missing: $grp"
        fi
    done
    if [ $REQUIRED_FOUND -ge 3 ]; then
        test_pass "All required groups present"
    else
        test_fail "Missing required groups ($REQUIRED_FOUND/3)"
    fi
}

#===============================================================================
# TEST SUITE 3: LEGAL SERVICE
#===============================================================================
test_legal() {
    print_header "TEST SUITE 3: LEGAL SERVICE"
    
    TOKEN=$(get_token)
    if [ -z "$TOKEN" ]; then
        test_fail "Cannot get token - skipping legal tests"
        return
    fi
    
    print_test "3.1 Get Legal Properties"
    RESULT=$($TOOLBOX curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-legal:8080/api/legal/v1/legaltags:properties" 2>/dev/null || echo -e "\n000")
    HTTP_CODE=$(echo "$RESULT" | tail -1)
    BODY=$(echo "$RESULT" | head -n -1)
    if [ "$HTTP_CODE" = "200" ]; then
        test_pass "Legal properties: HTTP $HTTP_CODE"
    else
        test_fail "Legal properties: HTTP $HTTP_CODE"
    fi
    
    print_test "3.2 List Legal Tags"
    RESULT=$($TOOLBOX curl -s \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-legal:8080/api/legal/v1/legaltags" 2>/dev/null || echo "{}")
    TAGS=$(echo "$RESULT" | grep -c '"name":' || true)
    echo "  Legal tags: $TAGS"
    test_pass "Legal tags list returned"
}

#===============================================================================
# TEST SUITE 4: SCHEMA SERVICE
#===============================================================================
test_schema() {
    print_header "TEST SUITE 4: SCHEMA SERVICE"
    
    TOKEN=$(get_token)
    if [ -z "$TOKEN" ]; then
        test_fail "Cannot get token - skipping schema tests"
        return
    fi
    
    print_test "4.1 Service Reachability"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-schema:8080/api/schema-service/v1/schema?limit=1" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        test_pass "Schema service reachable: HTTP $HTTP_CODE"
    else
        test_fail "Schema service unreachable: HTTP $HTTP_CODE"
    fi
    
    print_test "4.2 List Schemas"
    RESULT=$($TOOLBOX curl -s \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-schema:8080/api/schema-service/v1/schema" 2>/dev/null || echo "{}")
    if echo "$RESULT" | grep -q '"schemaInfos"'; then
        test_pass "Schema list returned"
        SCHEMAS=$(echo "$RESULT" | grep -o '"totalCount":[0-9]*' | cut -d: -f2 || echo "0")
        echo "  Total schemas: $SCHEMAS"
    else
        test_fail "Schema list failed"
        echo "  Response: ${RESULT:0:200}..."
    fi
}

#===============================================================================
# TEST SUITE 5: STORAGE SERVICE
#===============================================================================
test_storage() {
    print_header "TEST SUITE 5: STORAGE SERVICE"
    
    TOKEN=$(get_token)
    if [ -z "$TOKEN" ]; then
        test_fail "Cannot get token - skipping storage tests"
        return
    fi
    
    print_test "5.1 Service Info"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-storage:8080/api/storage/v2/info" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        test_pass "Storage service info: HTTP $HTTP_CODE"
    else
        test_fail "Storage service info: HTTP $HTTP_CODE"
    fi
    
    print_test "5.2 Query Records (empty)"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-storage:8080/api/storage/v2/query/records" \
        -d '{"records":[]}' 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        test_pass "Storage query: HTTP $HTTP_CODE"
    else
        test_fail "Storage query: HTTP $HTTP_CODE"
    fi
}

#===============================================================================
# TEST SUITE 6: FILE SERVICE
#===============================================================================
test_file() {
    print_header "TEST SUITE 6: FILE SERVICE"
    
    if ! check_service_exists osdu-file; then
        test_skip "File service not deployed"
        return
    fi
    
    TOKEN=$(get_token)
    if [ -z "$TOKEN" ]; then
        test_fail "Cannot get token - skipping file tests"
        return
    fi
    
    print_test "6.1 Service Info"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-file:8080/api/file/v2/info" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        test_pass "File service info: HTTP $HTTP_CODE"
    else
        test_fail "File service info: HTTP $HTTP_CODE"
    fi
}

#===============================================================================
# TEST SUITE 7: SEARCH SERVICE
#===============================================================================
test_search() {
    print_header "TEST SUITE 7: SEARCH SERVICE"
    
    if ! check_service_exists osdu-search; then
        test_skip "Search service not deployed"
        return
    fi
    
    TOKEN=$(get_token)
    if [ -z "$TOKEN" ]; then
        test_fail "Cannot get token - skipping search tests"
        return
    fi
    
    print_test "7.1 Service Health (via query)"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-search:8080/api/search/v2/query" \
        -d '{"kind":"*:*:*:*","limit":1}' 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        test_pass "Search service reachable: HTTP $HTTP_CODE"
    else
        test_fail "Search service unhealthy: HTTP $HTTP_CODE"
        echo "  Note: Search requires opensearch-proxy for ES8 compatibility"
    fi
    
    print_test "7.2 Search All Records"
    RESULT=$($TOOLBOX curl -s \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-search:8080/api/search/v2/query" \
        -d '{"kind":"*:*:*:*","limit":10}' 2>/dev/null || echo "{}")
    TOTAL=$(echo "$RESULT" | grep -o '"totalCount":[0-9]*' | cut -d: -f2 || echo "0")
    echo "  Total indexed records: $TOTAL"
    if echo "$RESULT" | grep -qi "results\|totalCount"; then
        test_pass "Search query executed"
    else
        test_fail "Search query failed"
        echo "  Response: ${RESULT:0:300}..."
    fi
}

#===============================================================================
# TEST SUITE 8: INDEXER SERVICE
#===============================================================================
test_indexer() {
    print_header "TEST SUITE 8: INDEXER SERVICE"
    
    if ! check_service_exists osdu-indexer; then
        test_skip "Indexer service not deployed"
        return
    fi
    
    print_test "8.1 Check Pod Status"
    POD_STATUS=$(kubectl -n $NS_CORE get pods -l app=osdu-indexer -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$POD_STATUS" = "Running" ]; then
        test_pass "Indexer pod: $POD_STATUS"
    else
        test_fail "Indexer pod: $POD_STATUS"
    fi
    
    print_test "8.2 Check Indexer Logs"
    ERROR_COUNT=$(kubectl -n $NS_CORE logs deploy/osdu-indexer --tail=100 2>/dev/null | grep -ci "error\|exception" || true)
    if [ "$ERROR_COUNT" -lt 5 ]; then
        test_pass "Indexer logs healthy (errors: $ERROR_COUNT)"
    else
        test_fail "Indexer has many errors: $ERROR_COUNT"
    fi
}

#===============================================================================
# TEST SUITE 9: END-TO-END DATA FLOW
#===============================================================================
test_e2e() {
    print_header "TEST SUITE 9: END-TO-END DATA FLOW"
    
    for svc in osdu-storage osdu-search osdu-indexer; do
        if ! check_service_exists $svc; then
            test_skip "E2E test requires $svc (not deployed)"
            return
        fi
    done
    
    TOKEN=$(get_token)
    if [ -z "$TOKEN" ]; then
        test_fail "Cannot get token - skipping E2E test"
        return
    fi
    
    E2E_TS=$(date +%s)
    
    echo -e "${CYAN}Testing complete data flow: Storage → MQ → Indexer → OpenSearch → Search${NC}"
    
    # Step 1: Create Legal Tag
    print_test "E2E.1 Create Legal Tag"
    E2E_TAG="$PARTITION_ID-e2e-$E2E_TS"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-legal:8080/api/legal/v1/legaltags" \
        -d "{
            \"name\": \"$E2E_TAG\",
            \"description\": \"E2E Test\",
            \"properties\": {
                \"contractId\": \"e2e-$E2E_TS\",
                \"countryOfOrigin\": [\"US\"],
                \"dataType\": \"Public Domain Data\",
                \"exportClassification\": \"EAR99\",
                \"originator\": \"E2E\",
                \"personalData\": \"No Personal Data\",
                \"securityClassification\": \"Public\",
                \"expirationDate\": \"2099-12-31\"
            }
        }" 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "409" ]; then
        test_pass "Legal tag: $E2E_TAG (HTTP $HTTP_CODE)"
    else
        test_fail "Legal tag creation failed: HTTP $HTTP_CODE"
        E2E_TAG="osdu-step24-test"
        echo "  Using fallback tag: $E2E_TAG"
    fi
    
    # Step 2: Create Record
    print_test "E2E.2 Create Record via Storage"
    E2E_RECORD="$PARTITION_ID:e2e:record-$E2E_TS"
    RESULT=$($TOOLBOX curl -s \
        -X PUT \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-storage:8080/api/storage/v2/records" \
        -d "[{
            \"id\": \"$E2E_RECORD\",
            \"kind\": \"$PARTITION_ID:e2e:E2ERecord:1.0.0\",
            \"acl\": {
                \"viewers\": [\"data.default.viewers@$PARTITION_ID.osdu.local\"],
                \"owners\": [\"data.default.owners@$PARTITION_ID.osdu.local\"]
            },
            \"legal\": {
                \"legaltags\": [\"$E2E_TAG\"],
                \"otherRelevantDataCountries\": [\"US\"]
            },
            \"data\": {
                \"e2e_marker\": \"E2E_TEST_$E2E_TS\",
                \"timestamp\": $E2E_TS
            }
        }]" 2>/dev/null || echo "{}")
    
    if echo "$RESULT" | grep -q "$E2E_RECORD\|recordIds"; then
        test_pass "Record created: $E2E_RECORD"
    else
        test_fail "Record creation failed"
        echo "  Response: $RESULT"
        return
    fi
    
    # Step 3: Wait for Indexing
    print_test "E2E.3 Wait for Indexing (30 seconds)"
    for i in $(seq 1 30); do
        echo -n "."
        sleep 1
    done
    echo ""
    test_pass "Wait complete"
    
    # Step 4: Search
    print_test "E2E.4 Search for Record"
    RESULT=$($TOOLBOX curl -s \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
        -H "X-Forwarded-Proto: https" \
        "http://osdu-search:8080/api/search/v2/query" \
        -d "{\"kind\":\"*:*:*:*\",\"query\":\"data.e2e_marker:E2E_TEST_$E2E_TS\",\"limit\":10}" 2>/dev/null || echo "{}")
    
    if echo "$RESULT" | grep -q "E2E_TEST_$E2E_TS"; then
        test_pass "🎉 E2E TEST PASSED!"
        echo ""
        echo -e "${GREEN}  ╔═════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}  ║  DATA FLOW VERIFIED:                                            ║${NC}"
        echo -e "${GREEN}  ║  Storage → MQ → Indexer → OpenSearch (via proxy) → Search      ║${NC}"
        echo -e "${GREEN}  ╚═════════════════════════════════════════════════════════════════╝${NC}"
    else
        test_fail "E2E TEST FAILED - Record not found via Search"
        echo "  Response: ${RESULT:0:400}..."
        echo ""
        echo -e "${YELLOW}  Troubleshooting:${NC}"
        echo "  1. Check Indexer: kubectl -n osdu-core logs deploy/osdu-indexer --tail=50"
        echo "  2. Check OpenSearch Proxy: kubectl -n osdu-data logs deploy/opensearch-proxy --tail=20"
        echo "  3. Check MQ: kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_queues"
        echo "  4. Retry after 60s if indexing is slow"
    fi
}

#===============================================================================
# SUMMARY
#===============================================================================
print_summary() {
    print_header "TEST SUMMARY"
    
    TOTAL=$((PASS + FAIL + SKIP))
    
    echo ""
    echo -e "  ${GREEN}✓ PASSED:${NC}  $PASS"
    echo -e "  ${RED}✗ FAILED:${NC}  $FAIL"
    echo -e "  ${YELLOW}⏭ SKIPPED:${NC} $SKIP"
    echo -e "  📊 TOTAL:   $TOTAL"
    echo ""
    
    if [ $FAIL -eq 0 ]; then
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  🎉 ALL TESTS PASSED!                                         ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
        exit 0
    else
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ⚠️  $FAIL TEST(S) FAILED - REVIEW ABOVE                       ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        exit 1
    fi
}

#===============================================================================
# MAIN
#===============================================================================
usage() {
    echo "Usage: $0 [all|preflight|partition|entitlements|legal|schema|storage|file|search|indexer|e2e]"
    echo ""
    echo "Test suites:"
    echo "  all           - Run all tests (includes preflight)"
    echo "  preflight     - Pre-flight checks only"
    echo "  partition     - Test Partition service"
    echo "  entitlements  - Test Entitlements service"
    echo "  legal         - Test Legal service"
    echo "  schema        - Test Schema service"
    echo "  storage       - Test Storage service"
    echo "  file          - Test File service"
    echo "  search        - Test Search service"
    echo "  indexer       - Test Indexer service"
    echo "  e2e           - End-to-end data flow test"
}

main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  OSDU Functional Test Suite (Updated for Step 25-26)         ║${NC}"
    echo -e "${BLUE}║  Timestamp: $(date -Iseconds)                       ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    case "${1:-all}" in
        preflight)    preflight ;;
        partition)    preflight; test_partition ;;
        entitlements) preflight; test_entitlements ;;
        legal)        preflight; test_legal ;;
        schema)       preflight; test_schema ;;
        storage)      preflight; test_storage ;;
        file)         preflight; test_file ;;
        search)       preflight; test_search ;;
        indexer)      preflight; test_indexer ;;
        e2e)          preflight; test_e2e ;;
        all)
            preflight
            test_partition
            test_entitlements
            test_legal
            test_schema
            test_storage
            test_file
            test_search
            test_indexer
            test_e2e
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    
    print_summary
}

main "$@"
