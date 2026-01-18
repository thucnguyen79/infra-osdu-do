#!/bin/bash
set -e

echo "=== Step 22 Fix: RabbitMQ password_hash -> password ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 1. Kiểm tra ConfigMap hiện tại
echo ""
echo "=== 1. Checking current ConfigMap definitions.json ==="
kubectl -n osdu-data get cm osdu-rabbitmq-config -o jsonpath='{.data.definitions\.json}' | head -20

# 2. Patch ConfigMap trực tiếp với definitions.json đúng format
echo ""
echo "=== 2. Patching ConfigMap with correct password field ==="

kubectl -n osdu-data create configmap osdu-rabbitmq-config \
  --from-literal=enabled_plugins='[rabbitmq_management,rabbitmq_prometheus].' \
  --from-literal=rabbitmq.conf='default_user = osdu
default_pass = osdu123
default_vhost = /
loopback_users.guest = false
load_definitions = /etc/rabbitmq/definitions.json' \
  --from-literal=definitions.json='{
  "vhosts": [{"name": "/"}],
  "users": [
    {"name": "osdu", "password": "osdu123", "tags": "administrator"}
  ],
  "permissions": [
    {"user": "osdu", "vhost": "/", "configure": ".*", "write": ".*", "read": ".*"}
  ],
  "exchanges": [
    {"name": "legaltags-changed", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false},
    {"name": "legaltags-changed.dlx", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false},
    {"name": "replaytopic", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false},
    {"name": "replaytopic.dlx", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false},
    {"name": "records-changed", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false},
    {"name": "dead-lettering-replay", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false},
    {"name": "dead-lettering-replay-subscription", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false},
    {"name": "replaytopicsubscription-exchange", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false}
  ],
  "queues": [
    {"name": "storage-oqm-legaltags-changed", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {"x-dead-letter-exchange": "legaltags-changed.dlx", "x-dead-letter-routing-key": "dlq"}},
    {"name": "storage-oqm-legaltags-changed.dlq", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "storage-oqm-replaytopic", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "storage-oqm-replaytopic.dlq", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "replaytopicsubscription", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "records-changed-subscription", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "dead-lettering-replay-subscription", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
    {"name": "replaytopicsubscription-exchange", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}}
  ],
  "bindings": [
    {"source": "legaltags-changed", "vhost": "/", "destination": "storage-oqm-legaltags-changed", "destination_type": "queue", "routing_key": "#"},
    {"source": "legaltags-changed.dlx", "vhost": "/", "destination": "storage-oqm-legaltags-changed.dlq", "destination_type": "queue", "routing_key": "#"},
    {"source": "replaytopic", "vhost": "/", "destination": "storage-oqm-replaytopic", "destination_type": "queue", "routing_key": "#"},
    {"source": "replaytopic", "vhost": "/", "destination": "replaytopicsubscription", "destination_type": "queue", "routing_key": "#"},
    {"source": "replaytopic.dlx", "vhost": "/", "destination": "storage-oqm-replaytopic.dlq", "destination_type": "queue", "routing_key": "#"},
    {"source": "records-changed", "vhost": "/", "destination": "records-changed-subscription", "destination_type": "queue", "routing_key": "#"},
    {"source": "dead-lettering-replay", "vhost": "/", "destination": "dead-lettering-replay-subscription", "destination_type": "queue", "routing_key": "#"},
    {"source": "dead-lettering-replay-subscription", "vhost": "/", "destination": "dead-lettering-replay-subscription", "destination_type": "queue", "routing_key": "#"},
    {"source": "replaytopicsubscription-exchange", "vhost": "/", "destination": "replaytopicsubscription-exchange", "destination_type": "queue", "routing_key": "#"}
  ]
}' \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Verify ConfigMap updated
echo ""
echo "=== 3. Verify ConfigMap updated (should show 'password', NOT 'password_hash') ==="
kubectl -n osdu-data get cm osdu-rabbitmq-config -o jsonpath='{.data.definitions\.json}' | grep -o '"password[^"]*"' | head -5

# 4. Delete all RabbitMQ pods and old ReplicaSets
echo ""
echo "=== 4. Cleaning up old pods and ReplicaSets ==="
kubectl -n osdu-data delete pod -l app=osdu-rabbitmq --force --grace-period=0 2>/dev/null || true
kubectl -n osdu-data get rs -l app=osdu-rabbitmq --no-headers | awk '{if ($2==0 && $3==0) print $1}' | xargs -r kubectl -n osdu-data delete rs 2>/dev/null || true

# 5. Restart deployment
echo ""
echo "=== 5. Restarting deployment ==="
kubectl -n osdu-data rollout restart deploy/osdu-rabbitmq

# 6. Wait for rollout
echo ""
echo "=== 6. Waiting for rollout (timeout 120s) ==="
kubectl -n osdu-data rollout status deploy/osdu-rabbitmq --timeout=120s

# 7. Verify pod running
echo ""
echo "=== 7. Verify pod status ==="
kubectl -n osdu-data get pod -l app=osdu-rabbitmq -o wide

# 8. Check logs
echo ""
echo "=== 8. RabbitMQ logs (last 30 lines) ==="
sleep 5
kubectl -n osdu-data logs -l app=osdu-rabbitmq --tail=30

# 9. Test connectivity
echo ""
echo "=== 9. Test RabbitMQ management API ==="
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl status | head -20

echo ""
echo "=== DONE ==="
