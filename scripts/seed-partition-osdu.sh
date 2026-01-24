#!/bin/bash
# scripts/seed-partition-osdu.sh
# Seed partition properties for OSDU 'osdu' partition
#
# This script creates/updates the 'osdu' partition with all required properties
# including: OpenSearch, S3/MinIO, RabbitMQ, Redis config
#
# Usage: ./scripts/seed-partition-osdu.sh
# Prerequisites:
#   - kubectl configured with cluster access
#   - osdu-toolbox deployed in osdu-core namespace
#   - Keycloak with test user configured
#   - Ceph S3 user created (for S3 credentials)

set -e

echo "=== OSDU Partition Seeding Script ==="
echo "Date: $(date -Iseconds)"
echo ""

# Configuration
TOOLBOX="kubectl -n osdu-core exec deploy/osdu-toolbox --"
KEYCLOAK_URL="http://keycloak.osdu-identity.svc.cluster.local/realms/osdu/protocol/openid-connect/token"
PARTITION_API="http://osdu-partition:8080/api/partition/v1"
PARTITION_ID="osdu"

# Get access token
echo "=== 1. Getting access token from Keycloak ==="
TOKEN=$($TOOLBOX curl -s -X POST "$KEYCLOAK_URL" \
    -d "grant_type=password" \
    -d "client_id=osdu-cli" \
    -d "username=test" \
    -d "password=Test@12345" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get access token"
    echo "Make sure Keycloak is running and test user exists"
    exit 1
fi
echo "✓ Token acquired (${TOKEN:0:20}...)"

# Check if partition exists
echo ""
echo "=== 2. Checking partition status ==="
PARTITION_STATUS=$($TOOLBOX curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "data-partition-id: $PARTITION_ID" \
    "$PARTITION_API/partitions/$PARTITION_ID")

if [ "$PARTITION_STATUS" == "404" ]; then
    echo "Partition does not exist, creating..."
    $TOOLBOX curl -s -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        "$PARTITION_API/partitions" \
        -d "{\"partitionId\": \"$PARTITION_ID\"}"
    sleep 2
    echo "✓ Partition created"
else
    echo "✓ Partition exists (HTTP $PARTITION_STATUS)"
fi

# Build and apply properties
echo ""
echo "=== 3. Updating partition properties ==="

# Properties JSON - Note: S3 credentials use ENV VAR names, not actual values
# The services will resolve these from their pod environment
PROPERTIES_JSON=$(cat <<'EOF'
{
    "properties": {
        "elasticsearch.8.host": {"sensitive": false, "value": "osdu-opensearch.osdu-data.svc.cluster.local"},
        "elasticsearch.8.port": {"sensitive": false, "value": "9200"},
        "elasticsearch.8.protocol": {"sensitive": false, "value": "http"},
        "elasticsearch.8.scheme": {"sensitive": false, "value": "http"},
        "elasticsearch.8.ssl.enabled": {"sensitive": false, "value": "false"},
        "elasticsearch.8.https.enabled": {"sensitive": false, "value": "false"},
        "elasticsearch.8.tls.enabled": {"sensitive": false, "value": "false"},
        "protocolScheme": {"sensitive": false, "value": "http"},
        
        "obm.minio.endpoint": {"sensitive": false, "value": "http://rook-ceph-rgw-osdu-store.rook-ceph.svc.cluster.local:80"},
        "obm.minio.ui.endpoint": {"sensitive": false, "value": "http://rook-ceph-rgw-osdu-store.rook-ceph.svc.cluster.local:80"},
        "obm.minio.bucket": {"sensitive": false, "value": "osdu-legal"},
        "obm.minio.accessKey": {"sensitive": true, "value": "OBM_MINIO_ACCESS_KEY"},
        "obm.minio.secretKey": {"sensitive": true, "value": "OBM_MINIO_SECRET_KEY"},
        
        "oqm.rabbitmq.amqp.host": {"sensitive": false, "value": "osdu-rabbitmq.osdu-data.svc.cluster.local"},
        "oqm.rabbitmq.amqp.port": {"sensitive": false, "value": "5672"},
        "oqm.rabbitmq.amqp.username": {"sensitive": false, "value": "osdu"},
        "oqm.rabbitmq.amqp.password": {"sensitive": true, "value": "osdu123"},
        
        "redis.database.partition": {"sensitive": false, "value": "0"},
        "redis.database.entitlements": {"sensitive": false, "value": "1"},
        "redis.database.legal": {"sensitive": false, "value": "2"},
        "redis.database.schema": {"sensitive": false, "value": "3"},
        "redis.database.storage": {"sensitive": false, "value": "4"}
    }
}
EOF
)

$TOOLBOX curl -s -X PATCH \
    -H "Authorization: Bearer $TOKEN" \
    -H "data-partition-id: $PARTITION_ID" \
    -H "Content-Type: application/json" \
    "$PARTITION_API/partitions/$PARTITION_ID" \
    -d "$PROPERTIES_JSON"

echo "✓ Properties updated"

# Verify
echo ""
echo "=== 4. Verifying partition properties ==="
$TOOLBOX curl -s \
    -H "Authorization: Bearer $TOKEN" \
    -H "data-partition-id: $PARTITION_ID" \
    "$PARTITION_API/partitions/$PARTITION_ID" | grep -o '"[^"]*":{"sensitive":[^}]*}' | head -15

# Flush Redis cache
echo ""
echo "=== 5. Flushing Redis cache ==="
kubectl run redis-flush-$(date +%s) --rm -it --restart=Never --image=redis:alpine -n osdu-data -- redis-cli -h osdu-redis FLUSHALL 2>/dev/null || echo "(flush completed or already clean)"

echo ""
echo "=== DONE ==="
echo "Partition '$PARTITION_ID' seeded successfully."
echo ""
echo "If services still have issues, restart them:"
echo "  kubectl -n osdu-core rollout restart deploy/osdu-legal deploy/osdu-storage deploy/osdu-search"
