#!/bin/bash
# Script: 05-fix-domain-mismatch.sh
# Purpose: Fix domain mismatch between user email and group domain
# Usage: ./05-fix-domain-mismatch.sh

TOOLBOX="kubectl -n osdu-core exec deploy/osdu-toolbox --"

echo "=== 1. Update partition domain to osdu.osdu.local ==="
$TOOLBOX curl -s -X PATCH \
  "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "Content-Type: application/json" \
  -H "data-partition-id: osdu" \
  -d '{"properties": {"domain": {"sensitive": false, "value": "osdu.osdu.local"}}}'

echo ""
echo "=== 2. Verify domain updated ==="
$TOOLBOX curl -s \
  "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "data-partition-id: osdu" | jq '.domain'

echo ""
echo "=== 3. Flush Redis cache ==="
kubectl run redis-flush-$(date +%s) --rm -it --restart=Never --image=redis:alpine -n osdu-data -- \
  redis-cli -h osdu-redis FLUSHALL

echo ""
echo "=== 4. Restart core services ==="
kubectl -n osdu-core rollout restart deploy/osdu-entitlements
kubectl -n osdu-core rollout restart deploy/osdu-storage
kubectl -n osdu-core rollout restart deploy/osdu-schema
kubectl -n osdu-core rollout restart deploy/osdu-legal
kubectl -n osdu-core rollout restart deploy/osdu-file

echo ""
echo "=== 5. Wait for rollout ==="
kubectl -n osdu-core rollout status deploy/osdu-entitlements --timeout=180s
kubectl -n osdu-core rollout status deploy/osdu-storage --timeout=180s

echo ""
echo "Done! Domain mismatch fixed."
