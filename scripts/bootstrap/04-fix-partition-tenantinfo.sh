#!/bin/bash
# Script: 04-fix-partition-tenantinfo.sh
# Purpose: Add missing TenantInfo properties required by Entitlements service
# Usage: ./04-fix-partition-tenantinfo.sh [partition-name]

PARTITION=${1:-osdu}
TOOLBOX="kubectl -n osdu-core exec deploy/osdu-toolbox --"

echo "=== Adding TenantInfo properties to partition: $PARTITION ==="

$TOOLBOX curl -s -X PATCH \
  "http://osdu-partition:8080/api/partition/v1/partitions/$PARTITION" \
  -H "Content-Type: application/json" \
  -H "data-partition-id: $PARTITION" \
  -d '{
    "properties": {
      "dataPartitionId": {"sensitive": false, "value": "'"$PARTITION"'"},
      "projectId": {"sensitive": false, "value": "osdu-poc"},
      "gcpProjectId": {"sensitive": false, "value": "osdu-poc"},
      "domain": {"sensitive": false, "value": "osdu.internal"},
      "crmAccountID": {"sensitive": false, "value": "[\"'"$PARTITION"'\"]"},
      "complianceRuleSet": {"sensitive": false, "value": "shared"}
    }
  }'

echo ""
echo "=== Verifying properties ==="
$TOOLBOX curl -s \
  "http://osdu-partition:8080/api/partition/v1/partitions/$PARTITION" \
  -H "data-partition-id: $PARTITION" | jq '{dataPartitionId, projectId, domain, crmAccountID, complianceRuleSet}'

echo ""
echo "=== Flushing Redis cache ==="
kubectl run redis-flush-$(date +%s) --rm -it --restart=Never --image=redis:alpine -n osdu-data -- \
  redis-cli -h osdu-redis FLUSHALL

echo ""
echo "Done! TenantInfo properties added to partition: $PARTITION"
