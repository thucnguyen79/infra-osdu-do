#!/bin/bash
# =============================================================================
# Script: init-partition-osdu.sh
# Purpose: Bootstrap partition "osdu" với đầy đủ properties cho RabbitMQ
# Usage: kubectl -n osdu-core exec deploy/osdu-toolbox -- bash < scripts/bootstrap/init-partition-osdu.sh
# =============================================================================
set -e

echo "============================================="
echo "Bootstrap Partition 'osdu' Properties"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================="

# Get token
TOKEN=$(curl -s -X POST "http://keycloak:80/realms/osdu/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=osdu-cli&username=test&password=Test@12345" | \
  grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
  echo "ERROR: Failed to get token"
  exit 1
fi
echo "Token acquired"

# Check partition
PARTITIONS=$(curl -s "http://osdu-partition:8080/api/partition/v1/partitions" -H "Authorization: Bearer $TOKEN")
if echo "$PARTITIONS" | grep -q '"osdu"'; then
  METHOD="PATCH"
else
  METHOD="POST"
fi
echo "Method: $METHOD"

# Payload
PAYLOAD='{
  "properties": {
    "id": {"sensitive": false, "value": "osdu"},
    "name": {"sensitive": false, "value": "osdu"},
    "dataPartitionId": {"sensitive": false, "value": "osdu"},
    "oqm.driver": {"sensitive": false, "value": "rabbitmq"},
    "oqm.rabbitmq.amqp.host": {"sensitive": false, "value": "osdu-rabbitmq.osdu-data.svc.cluster.local"},
    "oqm.rabbitmq.amqp.port": {"sensitive": false, "value": "5672"},
    "oqm.rabbitmq.amqp.username": {"sensitive": false, "value": "osdu"},
    "oqm.rabbitmq.amqp.password": {"sensitive": false, "value": "osdu123"},
    "oqm.rabbitmq.amqp.vhost": {"sensitive": false, "value": "/"},
    "oqm.rabbitmq.amqp.virtual-host": {"sensitive": false, "value": "/"},
    "oqm.rabbitmq.amqp.path": {"sensitive": false, "value": "/"},
    "oqm.rabbitmq.admin.host": {"sensitive": false, "value": "osdu-rabbitmq.osdu-data.svc.cluster.local"},
    "oqm.rabbitmq.admin.port": {"sensitive": false, "value": "15672"},
    "oqm.rabbitmq.admin.schema": {"sensitive": false, "value": "http"},
    "oqm.rabbitmq.admin.username": {"sensitive": false, "value": "osdu"},
    "oqm.rabbitmq.admin.password": {"sensitive": false, "value": "osdu123"},
    "oqm.rabbitmq.admin.path": {"sensitive": false, "value": "/api"},
    "oqm.rabbitmq.vhost": {"sensitive": false, "value": "/"},
    "oqm.rabbitmq.virtualHost": {"sensitive": false, "value": "/"},
    "oqm.rabbitmq.virtual-host": {"sensitive": false, "value": "/"},
    "oqm.rabbitmq.retry.enabled": {"sensitive": false, "value": "false"},
    "oqm.rabbitmq.retryEnabled": {"sensitive": false, "value": "false"},
    "oqm.rabbitmq.retry-delay": {"sensitive": false, "value": "0"},
    "oqm.rabbitmq.retryDelay": {"sensitive": false, "value": "0"},
    "oqm.rabbitmq.rabbitmqRetryDelay": {"sensitive": false, "value": "0"},
    "oqm.rabbitmq.retry.max-attempts": {"sensitive": false, "value": "3"},
    "oqm.rabbitmq.maxRetries": {"sensitive": false, "value": "3"},
    "oqm.rabbitmq.retry.initial-interval-ms": {"sensitive": false, "value": "1000"},
    "oqm.rabbitmq.retryInitialInterval": {"sensitive": false, "value": "1000"},
    "oqm.rabbitmq.retry.max-interval-ms": {"sensitive": false, "value": "10000"},
    "oqm.rabbitmq.retryMaxInterval": {"sensitive": false, "value": "10000"},
    "oqm.rabbitmq.retry.multiplier": {"sensitive": false, "value": "2.0"},
    "oqm.rabbitmq.retryMultiplier": {"sensitive": false, "value": "2.0"},
    "oqm.rabbitmq.dlq.exchange": {"sensitive": false, "value": "legaltags-changed.dlx"},
    "oqm.rabbitmq.deadLetterExchange": {"sensitive": false, "value": "legaltags-changed.dlx"},
    "oqm.rabbitmq.dlq.routing-key": {"sensitive": false, "value": "dlq"},
    "oqm.rabbitmq.deadLetterRoutingKey": {"sensitive": false, "value": "dlq"},
    "oqm.rabbitmq.retryExchange": {"sensitive": false, "value": "legaltags-changed.retry"},
    "oqm.rabbitmq.replay.topic": {"sensitive": false, "value": "replaytopic"},
    "oqm.rabbitmq.replay.subscription": {"sensitive": false, "value": "replaytopicsubscription"},
    "oqm.rabbitmq.dead-lettering.topic": {"sensitive": false, "value": "dead-lettering-replay"},
    "oqm.rabbitmq.dead-lettering.subscription": {"sensitive": false, "value": "dead-lettering-replay-subscription"},
    "rabbitmq.retry.enabled": {"sensitive": false, "value": "false"},
    "oqm.retry.enabled": {"sensitive": false, "value": "false"}
  }
}'

curl -s -X $METHOD "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" | head -c 200

echo ""
echo "Done! Remember to flush Redis: redis-cli -h osdu-redis FLUSHALL"
