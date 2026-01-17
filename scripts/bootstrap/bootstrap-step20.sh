#!/bin/bash
# Step 20 Bootstrap - Seed partition RabbitMQ properties & search groups
set -e

NAMESPACE="${NAMESPACE:-osdu-core}"
DATA_NAMESPACE="${DATA_NAMESPACE:-osdu-data}"
PARTITION_ID="${PARTITION_ID:-osdu}"
TOOLBOX="kubectl -n $NAMESPACE exec deploy/osdu-toolbox --"

echo "=== Step 20 Bootstrap ==="

# 1. Get Token
echo "[1/4] Getting token..."
TOKEN=$($TOOLBOX bash -c '
curl -s -X POST "http://keycloak:80/realms/osdu/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=osdu-cli&username=test&password=Test@12345" | \
  grep -o "\"access_token\":\"[^\"]*" | cut -d"\"" -f4
')

# 2. Add RabbitMQ properties
echo "[2/4] Adding RabbitMQ partition properties..."
$TOOLBOX bash -c "
curl -s -X PATCH 'http://osdu-partition:8080/api/partition/v1/partitions/$PARTITION_ID' \
  -H 'Authorization: Bearer $TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{
    \"properties\": {
      \"oqm.rabbitmq.amqp.host\": {\"sensitive\": false, \"value\": \"osdu-rabbitmq.osdu-data.svc.cluster.local\"},
      \"oqm.rabbitmq.amqp.port\": {\"sensitive\": false, \"value\": \"5672\"},
      \"oqm.rabbitmq.amqp.path\": {\"sensitive\": false, \"value\": \"/\"},
      \"oqm.rabbitmq.amqp.username\": {\"sensitive\": false, \"value\": \"osdu\"},
      \"oqm.rabbitmq.amqp.password\": {\"sensitive\": false, \"value\": \"osdu123\"},
      \"oqm.rabbitmq.admin.schema\": {\"sensitive\": false, \"value\": \"http\"},
      \"oqm.rabbitmq.admin.host\": {\"sensitive\": false, \"value\": \"osdu-rabbitmq.osdu-data.svc.cluster.local\"},
      \"oqm.rabbitmq.admin.port\": {\"sensitive\": false, \"value\": \"15672\"},
      \"oqm.rabbitmq.admin.path\": {\"sensitive\": false, \"value\": \"/api\"},
      \"oqm.rabbitmq.admin.username\": {\"sensitive\": false, \"value\": \"osdu\"},
      \"oqm.rabbitmq.admin.password\": {\"sensitive\": false, \"value\": \"osdu123\"},
      \"oqm.rabbitmq.rabbitmqRetryDelay\": {\"sensitive\": false, \"value\": \"0\"},
      \"oqm.rabbitmq.retryDelay\": {\"sensitive\": false, \"value\": \"0\"},
      \"oqm.rabbitmq.retry.enabled\": {\"sensitive\": false, \"value\": \"false\"}
    }
  }' > /dev/null
"

# 3. Create search groups
echo "[3/4] Creating search groups..."
for role in admin user viewer editor; do
  $TOOLBOX bash -c "
    curl -s -X POST 'http://osdu-entitlements:8080/api/entitlements/v2/groups' \
      -H 'Authorization: Bearer $TOKEN' \
      -H 'Content-Type: application/json' \
      -H 'data-partition-id: $PARTITION_ID' \
      -d '{\"name\": \"service.search.$role\", \"description\": \"Search Service $role\"}' > /dev/null 2>&1
  " || true
done

# 4. Fix DB and add test user
echo "[4/4] Fixing search groups in DB..."
PGPASS=$(kubectl -n $DATA_NAMESPACE get secret osdu-postgres-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
kubectl -n $DATA_NAMESPACE exec sts/osdu-postgres -- bash -c "PGPASSWORD='$PGPASS' psql -U osduadmin -d entitlements -c \"
UPDATE \\\"group\\\" SET email = REPLACE(email, '@osdu.group', '@osdu.osdu.local') WHERE name LIKE 'service.search.%' AND email LIKE '%@osdu.group';
INSERT INTO member_to_group (member_id, group_id, role, created_at) SELECT 1, id, 'MEMBER', NOW() FROM \\\"group\\\" WHERE name LIKE 'service.search.%' ON CONFLICT DO NOTHING;
\"" > /dev/null 2>&1

# Flush Redis
kubectl run redis-flush-$(date +%s) --rm -it --restart=Never --image=redis:alpine -n $DATA_NAMESPACE -- redis-cli -h osdu-redis FLUSHALL > /dev/null 2>&1

echo "=== Done! Restart services: kubectl -n $NAMESPACE rollout restart deploy osdu-storage osdu-file ==="
