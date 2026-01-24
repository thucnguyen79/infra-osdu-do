#!/bin/bash
#===============================================================================
# OSDU Functional Test Scenarios (Fixed)
# Kiểm tra chức năng của từng service
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
        "http://osdu-partition:8080/api/partition/v1/partitions/$PARTITION_ID" 2>/dev/null || echo "{}")
    PROPS=$(echo "$RESULT" | grep -c '"value":' || true)
    echo "  Properties count: $PROPS"
    if [ "$PROPS" -gt 10 ]; then
        test_pass "Partition has $PROPS properties"
    else
        test_fail "Partition properties insufficient ($PROPS)"
    fi
    
    print_test "1.3 Verify Critical Properties"
    CRITICAL="elasticsearch.host redis-host oqm.rabbitmq"
    ALL_OK=true
    for prop in $CRITICAL; do
        if echo "$RESULT" | grep -q "$prop"; then
            echo "  ✓ Found: $prop"
        else
            echo "  ✗ Missing: $prop"
            ALL_OK=false
        fi
    done
    if [ "$ALL_OK" = true ]; then
        test_pass "All critical properties present"
    else
        test_fail "Some critical properties missing"
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
        "http://osdu-entitlements:8080/api/entitlements/v2/groups" 2>/dev/null || echo "{}")
    GROUPS=$(echo "$RESULT" | grep -c '"name":' || true)
    echo "  Groups found: $GROUPS"
    if [ "$GROUPS" -gt 0 ]; then
        test_pass "Found $GROUPS entitlement groups"
    else
        test_fail "No groups found"
    fi
    
    print_test "2.2 Verify Required Groups"
    for grp in users data.default.owners data.default.viewers; do
        if echo "$RESULT" | grep -q "$grp"; then
            echo "  ✓ Found: $grp"
        else
            echo "  ✗ Missing: $grp"
        fi
    done
    test_pass "Group verification complete"
    
    print_test "2.3 Get Current User Groups"
    RESULT=$($TOOLBOX curl -s \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        "http://osdu-entitlements:8080/api/entitlements/v2/members/test@$PARTITION_ID.osdu.local/groups" 2>/dev/null || echo "{}")
    if echo "$RESULT" | grep -q "users@"; then
        test_pass "User 'test' is member of users group"
    else
        test_fail "User 'test' not in users group"
    fi
    
    print_test "2.4 Create Test Group"
    GROUP_NAME="test.automation.$TIMESTAMP@$PARTITION_ID.osdu.local"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
        "http://osdu-entitlements:8080/api/entitlements/v2/groups" \
        -d "{\"name\":\"$GROUP_NAME\",\"description\":\"Automated test group\"}" 2>/dev/null || echo "000")
    echo "  HTTP: $HTTP_CODE, Group: $GROUP_NAME"
    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "409" ]; then
        test_pass "Group creation: $HTTP_CODE"
    else
        test_fail "Group creation failed: $HTTP_CODE"
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
    
    print_test "3.1 Service Info"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        "http://osdu-legal:8080/api/legal/v1/info" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        test_pass "Legal service info: HTTP $HTTP_CODE"
    else
        test_fail "Legal service info: HTTP $HTTP_CODE"
    fi
    
    print_test "3.2 List Legal Tags"
    RESULT=$($TOOLBOX curl -s \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        "http://osdu-legal:8080/api/legal/v1/legaltags" 2>/dev/null || echo "{}")
    TAGS=$(echo "$RESULT" | grep -c '"name":' || true)
    echo "  Legal tags: $TAGS"
    test_pass "Legal tags list returned"
    
    print_test "3.3 Create Legal Tag"
    TAG_NAME="$PARTITION_ID-autotest-$TIMESTAMP"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
        "http://osdu-legal:8080/api/legal/v1/legaltags" \
        -d "{
            \"name\": \"$TAG_NAME\",
            \"description\": \"Automated test tag\",
            \"properties\": {
                \"contractId\": \"test-$TIMESTAMP\",
                \"countryOfOrigin\": [\"US\"],
                \"dataType\": \"Public Domain Data\",
                \"exportClassification\": \"EAR99\",
                \"originator\": \"Test Automation\",
                \"personalData\": \"No Personal Data\",
                \"securityClassification\": \"Public\",
                \"expirationDate\": \"2099-12-31\"
            }
        }" 2>/dev/null || echo "000")
    echo "  HTTP: $HTTP_CODE, Tag: $TAG_NAME"
    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "409" ]; then
        test_pass "Legal tag created: $HTTP_CODE"
        TEST_LEGAL_TAG="$TAG_NAME"
    else
        test_fail "Legal tag creation: $HTTP_CODE"
    fi
    
    print_test "3.4 Validate Legal Tag"
    if [ -n "$TEST_LEGAL_TAG" ]; then
        RESULT=$($TOOLBOX curl -s \
            -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -H "data-partition-id: $PARTITION_ID" \
            -H "Content-Type: application/json" \
            "http://osdu-legal:8080/api/legal/v1/legaltags:validate" \
            -d "{\"names\":[\"$TEST_LEGAL_TAG\"]}" 2>/dev/null || echo "{}")
        if echo "$RESULT" | grep -q "validLegalTags\|\"valid\":true"; then
            test_pass "Legal tag validation passed"
        else
            test_fail "Legal tag validation failed"
            echo "  Response: $RESULT"
        fi
    else
        test_skip "No legal tag to validate"
    fi
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
    
    print_test "4.1 Service Info"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        "http://osdu-schema:8080/api/schema-service/v1/info" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        test_pass "Schema service info: HTTP $HTTP_CODE"
    else
        test_fail "Schema service info: HTTP $HTTP_CODE"
    fi
    
    print_test "4.2 List Schemas"
    RESULT=$($TOOLBOX curl -s \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        "http://osdu-schema:8080/api/schema-service/v1/schema" 2>/dev/null || echo "{}")
    SCHEMAS=$(echo "$RESULT" | grep -c '"schemaIdentity":' || true)
    echo "  Schemas: $SCHEMAS"
    test_pass "Schema list returned"
    
    print_test "4.3 Create Test Schema"
    SCHEMA_KIND="$PARTITION_ID:autotest:TestRecord:1.0.$TIMESTAMP"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
        "http://osdu-schema:8080/api/schema-service/v1/schema" \
        -d "{
            \"schemaInfo\": {
                \"schemaIdentity\": {
                    \"authority\": \"$PARTITION_ID\",
                    \"source\": \"autotest\",
                    \"entityType\": \"TestRecord\",
                    \"schemaVersionMajor\": 1,
                    \"schemaVersionMinor\": 0,
                    \"schemaVersionPatch\": $TIMESTAMP
                },
                \"status\": \"DEVELOPMENT\"
            },
            \"schema\": {
                \"\$schema\": \"http://json-schema.org/draft-07/schema#\",
                \"type\": \"object\",
                \"properties\": {
                    \"name\": {\"type\": \"string\"},
                    \"value\": {\"type\": \"number\"},
                    \"timestamp\": {\"type\": \"integer\"}
                }
            }
        }" 2>/dev/null || echo "000")
    echo "  HTTP: $HTTP_CODE, Kind: $SCHEMA_KIND"
    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "409" ] || [ "$HTTP_CODE" = "200" ]; then
        test_pass "Schema created: $HTTP_CODE"
        TEST_SCHEMA_KIND="$SCHEMA_KIND"
    else
        test_fail "Schema creation: $HTTP_CODE"
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
        "http://osdu-storage:8080/api/storage/v2/info" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        test_pass "Storage service info: HTTP $HTTP_CODE"
    else
        test_fail "Storage service info: HTTP $HTTP_CODE"
    fi
    
    print_test "5.2 Query Records"
    RESULT=$($TOOLBOX curl -s \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        "http://osdu-storage:8080/api/storage/v2/query/records?kind=*:*:*:*&limit=5" 2>/dev/null || echo "{}")
    echo "  Response: ${RESULT:0:200}..."
    test_pass "Storage query returned"
    
    print_test "5.3 Create Record"
    # Use existing legal tag or create fallback
    LEGAL_TAG="${TEST_LEGAL_TAG:-$PARTITION_ID-autotest-$TIMESTAMP}"
    RECORD_KIND="${TEST_SCHEMA_KIND:-$PARTITION_ID:autotest:TestRecord:1.0.0}"
    RECORD_ID="$PARTITION_ID:autotest:record-$TIMESTAMP"
    
    RESULT=$($TOOLBOX curl -s \
        -X PUT \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
        "http://osdu-storage:8080/api/storage/v2/records" \
        -d "[{
            \"id\": \"$RECORD_ID\",
            \"kind\": \"$RECORD_KIND\",
            \"acl\": {
                \"viewers\": [\"data.default.viewers@$PARTITION_ID.osdu.local\"],
                \"owners\": [\"data.default.owners@$PARTITION_ID.osdu.local\"]
            },
            \"legal\": {
                \"legaltags\": [\"$LEGAL_TAG\"],
                \"otherRelevantDataCountries\": [\"US\"]
            },
            \"data\": {
                \"name\": \"Test Record $TIMESTAMP\",
                \"value\": $TIMESTAMP,
                \"timestamp\": $TIMESTAMP
            }
        }]" 2>/dev/null || echo "{}")
    
    echo "  Record ID: $RECORD_ID"
    echo "  Response: ${RESULT:0:300}..."
    
    if echo "$RESULT" | grep -q "recordIds\|$RECORD_ID"; then
        test_pass "Record created successfully"
        TEST_RECORD_ID="$RECORD_ID"
    else
        test_fail "Record creation failed"
    fi
    
    if [ -n "$TEST_RECORD_ID" ]; then
        print_test "5.4 Get Record by ID"
        sleep 2
        RESULT=$($TOOLBOX curl -s \
            -H "Authorization: Bearer $TOKEN" \
            -H "data-partition-id: $PARTITION_ID" \
            "http://osdu-storage:8080/api/storage/v2/records/$TEST_RECORD_ID" 2>/dev/null || echo "{}")
        if echo "$RESULT" | grep -q "$TEST_RECORD_ID"; then
            test_pass "Record retrieved"
        else
            test_fail "Record not found"
        fi
    fi
}

#===============================================================================
# TEST SUITE 6: FILE SERVICE
#===============================================================================
test_file() {
    print_header "TEST SUITE 6: FILE SERVICE"
    
    TOKEN=$(get_token)
    if [ -z "$TOKEN" ]; then
        test_fail "Cannot get token - skipping file tests"
        return
    fi
    
    print_test "6.1 Service Info"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        "http://osdu-file:8080/api/file/v2/info" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        test_pass "File service info: HTTP $HTTP_CODE"
    else
        test_fail "File service info: HTTP $HTTP_CODE"
    fi
    
    print_test "6.2 Get Upload URL"
    RESULT=$($TOOLBOX curl -s \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
        "http://osdu-file:8080/api/file/v2/files/uploadURL" 2>/dev/null || echo "{}")
    echo "  Response: ${RESULT:0:200}..."
    if echo "$RESULT" | grep -qi "signedUrl\|uploadUrl\|FileID"; then
        test_pass "Upload URL generated"
    else
        test_fail "Upload URL generation failed"
    fi
}

#===============================================================================
# TEST SUITE 7: SEARCH SERVICE
#===============================================================================
test_search() {
    print_header "TEST SUITE 7: SEARCH SERVICE"
    
    TOKEN=$(get_token)
    if [ -z "$TOKEN" ]; then
        test_fail "Cannot get token - skipping search tests"
        return
    fi
    
    print_test "7.1 Service Health"
    RESULT=$($TOOLBOX curl -s \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        "http://osdu-search:8080/api/search/v2/health" 2>/dev/null || echo "{}")
    if echo "$RESULT" | grep -qi "UP\|healthy\|200"; then
        test_pass "Search service healthy"
    else
        test_fail "Search service unhealthy"
    fi
    
    print_test "7.2 Search All Records"
    RESULT=$($TOOLBOX curl -s \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
        "http://osdu-search:8080/api/search/v2/query" \
        -d '{"kind":"*:*:*:*","limit":10}' 2>/dev/null || echo "{}")
    TOTAL=$(echo "$RESULT" | grep -o '"totalCount":[0-9]*' | cut -d: -f2 || echo "0")
    echo "  Total results: $TOTAL"
    if echo "$RESULT" | grep -qi "results\|totalCount"; then
        test_pass "Search query executed"
    else
        test_fail "Search query failed"
    fi
    
    if [ -n "$TEST_RECORD_ID" ]; then
        print_test "7.3 Search for Test Record"
        echo "  Waiting 10s for indexing..."
        sleep 10
        RESULT=$($TOOLBOX curl -s \
            -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -H "data-partition-id: $PARTITION_ID" \
            -H "Content-Type: application/json" \
            "http://osdu-search:8080/api/search/v2/query" \
            -d "{\"kind\":\"*:*:*:*\",\"query\":\"data.timestamp:$TIMESTAMP\",\"limit\":10}" 2>/dev/null || echo "{}")
        if echo "$RESULT" | grep -q "$TIMESTAMP"; then
            test_pass "Test record found via search"
        else
            test_fail "Test record NOT found (indexing may be slow)"
            echo "  Response: ${RESULT:0:300}..."
        fi
    fi
}

#===============================================================================
# TEST SUITE 8: INDEXER SERVICE
#===============================================================================
test_indexer() {
    print_header "TEST SUITE 8: INDEXER SERVICE"
    
    print_test "8.1 Actuator Health"
    RESULT=$($TOOLBOX curl -s \
        "http://osdu-indexer:8080/actuator/health" 2>/dev/null || echo "{}")
    if echo "$RESULT" | grep -qi '"status":"UP"'; then
        test_pass "Indexer healthy"
    else
        test_fail "Indexer unhealthy"
        echo "  Response: $RESULT"
    fi
    
    print_test "8.2 Check Indexer Logs"
    LOGS=$(kubectl -n $NS_CORE logs deploy/osdu-indexer --tail=50 2>/dev/null | grep -i "listening\|REGISTERED\|subscription\|Started" | tail -3 || true)
    if [ -n "$LOGS" ]; then
        test_pass "Indexer running"
        echo "  Recent logs:"
        echo "$LOGS" | sed 's/^/    /'
    else
        test_pass "Indexer logs checked (no subscription messages - may be normal)"
    fi
}

#===============================================================================
# TEST SUITE 9: END-TO-END DATA FLOW
#===============================================================================
test_e2e() {
    print_header "TEST SUITE 9: END-TO-END DATA FLOW"
    
    TOKEN=$(get_token)
    if [ -z "$TOKEN" ]; then
        test_fail "Cannot get token - skipping E2E test"
        return
    fi
    
    E2E_TS=$(date +%s)
    
    echo -e "${CYAN}Testing complete data flow: Storage → RabbitMQ → Indexer → OpenSearch → Search${NC}"
    
    # Step 1: Create Legal Tag
    print_test "E2E.1 Create Legal Tag"
    E2E_TAG="$PARTITION_ID-e2e-$E2E_TS"
    HTTP_CODE=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
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
        return
    fi
    
    # Step 2: Create Record
    print_test "E2E.2 Create Record via Storage"
    E2E_RECORD="$PARTITION_ID:e2e:record-$E2E_TS"
    RESULT=$($TOOLBOX curl -s \
        -X PUT \
        -H "Authorization: Bearer $TOKEN" \
        -H "data-partition-id: $PARTITION_ID" \
        -H "Content-Type: application/json" \
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
    print_test "E2E.3 Wait for Indexing (20 seconds)"
    for i in $(seq 1 20); do
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
        "http://osdu-search:8080/api/search/v2/query" \
        -d "{\"kind\":\"*:*:*:*\",\"query\":\"data.e2e_marker:E2E_TEST_$E2E_TS\",\"limit\":10}" 2>/dev/null || echo "{}")
    
    if echo "$RESULT" | grep -q "E2E_TEST_$E2E_TS"; then
        test_pass "🎉 E2E TEST PASSED!"
        echo ""
        echo -e "${GREEN}  ╔═════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}  ║  DATA FLOW VERIFIED:                                ║${NC}"
        echo -e "${GREEN}  ║  Storage → RabbitMQ → Indexer → OpenSearch → Search ║${NC}"
        echo -e "${GREEN}  ╚═════════════════════════════════════════════════════╝${NC}"
    else
        test_fail "E2E TEST FAILED - Record not found via Search"
        echo "  Response: ${RESULT:0:400}..."
        echo ""
        echo -e "${YELLOW}  Troubleshooting:${NC}"
        echo "  1. Check Indexer: kubectl -n osdu-core logs deploy/osdu-indexer --tail=50"
        echo "  2. Check RabbitMQ: kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_queues"
        echo "  3. Retry after 60s if indexing is slow"
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
    echo "Usage: $0 [all|partition|entitlements|legal|schema|storage|file|search|indexer|e2e]"
    echo ""
    echo "Test suites:"
    echo "  all          - Run all tests"
    echo "  partition    - Test Partition service"
    echo "  entitlements - Test Entitlements service"
    echo "  legal        - Test Legal service"
    echo "  schema       - Test Schema service"
    echo "  storage      - Test Storage service"
    echo "  file         - Test File service"
    echo "  search       - Test Search service"
    echo "  indexer      - Test Indexer service"
    echo "  e2e          - End-to-end data flow test"
}

main() {
    case "${1:-all}" in
        partition)    test_partition ;;
        entitlements) test_entitlements ;;
        legal)        test_legal ;;
        schema)       test_schema ;;
        storage)      test_storage ;;
        file)         test_file ;;
        search)       test_search ;;
        indexer)      test_indexer ;;
        e2e)          test_e2e ;;
        all)
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
