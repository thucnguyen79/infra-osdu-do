#!/bin/bash
set -e

echo "=== Step 22 Fix: RabbitMQ definitions with tenant prefix ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

TENANT="osdu"

# 1. Delete existing ConfigMap and recreate with full definitions
echo ""
echo "=== 1. Recreating ConfigMap with full definitions ==="

kubectl -n osdu-data delete cm osdu-rabbitmq-config --ignore-not-found

kubectl -n osdu-data create configmap osdu-rabbitmq-config \
  --from-literal=enabled_plugins='[rabbitmq_management,rabbitmq_prometheus].' \
  --from-literal=rabbitmq.conf='default_user = osdu
default_pass = osdu123
default_vhost = /
loopback_users.guest = false
load_definitions = /etc/rabbitmq/definitions.json' \
  --from-literal=definitions.json='{
  "rabbit_version": "3.12.14",
  "vhosts": [{"name": "/"}],
  "users": [
    {"name": "osdu", "password": "osdu123", "tags": "administrator"}
  ],
  "permissions": [
    {"user": "osdu", "vhost": "/", "configure": ".*", "write": ".*", "read": ".*"}
  ],
  "exchanges": [
    {"name": "legaltags-changed", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false, "internal": false, "arguments": {}},
    {"name": "legaltags-changed.dlx", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false, "internal": false, "arguments": {}},
    {"name": "replaytopic", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false, "internal": false, "arguments": {}},
    {"name": "replaytopic.dlx", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false, "internal": false, "arguments": {}},
    {"name": "records-changed", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false, "internal": false, "arguments": {}},
    {"name": "dead-lettering-replay", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false, "internal": false, "arguments": {}},
    {"name": "dead-lettering-replay-subscription", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false, "internal": false, "arguments": {}},
    {"name": "osdu.legaltags-changed", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false, "internal": false, "arguments": {}},
    {"name": "osdu.records-changed", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false, "internal": false, "arguments": {}},
    {"name": "osdu.dead-lettering-replay", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false, "internal": false, "arguments": {}},
    {"name": "osdu.dead-lettering-replay-subscription", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false, "internal": false, "arguments": {}}
  ],
  "queues": [
    {"name": "dead-lettering-replay-subscription", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "osdu.dead-lettering-replay-subscription", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "storage-oqm-legaltags-changed", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "storage-oqm-legaltags-changed.dlq", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "storage-oqm-replaytopic", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "storage-oqm-replaytopic.dlq", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "replaytopicsubscription", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "records-changed-subscription", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "osdu.storage-oqm-legaltags-changed", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "osdu.storage-oqm-replaytopic", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "osdu.records-changed-subscription", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}}
  ],
  "bindings": [
    {"source": "dead-lettering-replay", "vhost": "/", "destination": "dead-lettering-replay-subscription", "destination_type": "queue", "routing_key": "#", "arguments": {}},
    {"source": "dead-lettering-replay-subscription", "vhost": "/", "destination": "dead-lettering-replay-subscription", "destination_type": "queue", "routing_key": "#", "arguments": {}},
    {"source": "osdu.dead-lettering-replay", "vhost": "/", "destination": "osdu.dead-lettering-replay-subscription", "destination_type": "queue", "routing_key": "#", "arguments": {}},
    {"source": "osdu.dead-lettering-replay-subscription", "vhost": "/", "destination": "osdu.dead-lettering-replay-subscription", "destination_type": "queue", "routing_key": "#", "arguments": {}},
    {"source": "legaltags-changed", "vhost": "/", "destination": "storage-oqm-legaltags-changed", "destination_type": "queue", "routing_key": "#", "arguments": {}},
    {"source": "replaytopic", "vhost": "/", "destination": "storage-oqm-replaytopic", "destination_type": "queue", "routing_key": "#", "arguments": {}},
    {"source": "replaytopic", "vhost": "/", "destination": "replaytopicsubscription", "destination_type": "queue", "routing_key": "#", "arguments": {}},
    {"source": "records-changed", "vhost": "/", "destination": "records-changed-subscription", "destination_type": "queue", "routing_key": "#", "arguments": {}},
    {"source": "osdu.legaltags-changed", "vhost": "/", "destination": "osdu.storage-oqm-legaltags-changed", "destination_type": "queue", "routing_key": "#", "arguments": {}},
    {"source": "osdu.records-changed", "vhost": "/", "destination": "osdu.records-changed-subscription", "destination_type": "queue", "routing_key": "#", "arguments": {}}
  ]
}'

echo "ConfigMap created."

# 2. Force delete pod to reload ConfigMap
echo ""
echo "=== 2. Deleting RabbitMQ pod to reload ConfigMap ==="
kubectl -n osdu-data delete pod -l app=osdu-rabbitmq --force --grace-period=0

# 3. Wait for new pod
echo ""
echo "=== 3. Waiting for RabbitMQ pod to be ready ==="
sleep 5
kubectl -n osdu-data wait --for=condition=ready pod -l app=osdu-rabbitmq --timeout=120s

# 4. Verify queues and exchanges created
echo ""
echo "=== 4. Verify exchanges ==="
sleep 5
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_exchanges name type | grep -v "^$"

echo ""
echo "=== 5. Verify queues ==="
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_queues name

echo ""
echo "=== 6. Verify bindings ==="
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_bindings source_name destination_name routing_key

# 5. Restart Storage service
echo ""
echo "=== 7. Restarting Storage service ==="
kubectl -n osdu-core rollout restart deploy/osdu-storage

echo ""
echo "=== 8. Waiting for Storage rollout ==="
kubectl -n osdu-core rollout status deploy/osdu-storage --timeout=180s

echo ""
echo "=== 9. Check Storage pods ==="
kubectl -n osdu-core get pod -l app=osdu-storage -o wide

echo ""
echo "=== 10. Storage logs (last 30 lines) ==="
sleep 10
kubectl -n osdu-core logs -l app=osdu-storage --tail=30

echo ""
echo "=== DONE ==="
