#!/bin/bash
# Script: 04-fix-partition-tenantinfo.sh
# Purpose: Add ALL required partition properties for OSDU services
# Usage: ./04-fix-partition-tenantinfo.sh [partition-name]

PARTITION=${1:-osdu}
TOOLBOX="kubectl -n osdu-core exec deploy/osdu-toolbox --"

echo "=== Adding ALL required properties to partition: $PARTITION ==="

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
      "complianceRuleSet": {"sensitive": false, "value": "shared"},
      "serviceAccount": {"sensitive": false, "value": "osdu-service@osdu-poc.iam.gserviceaccount.com"},
      "entitlements.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/osdu"},
      "entitlements.datasource.username": {"sensitive": false, "value": "osdu"},
      "entitlements.datasource.password": {"sensitive": true, "value": "osdu123"},
      "entitlements.datasource.schema": {"sensitive": false, "value": "entitlements"},
      "legal.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/osdu"},
      "legal.datasource.username": {"sensitive": false, "value": "osdu"},
      "legal.datasource.password": {"sensitive": true, "value": "osdu123"},
      "legal.datasource.schema": {"sensitive": false, "value": "legal"},
      "storage.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/osdu"},
      "storage.datasource.username": {"sensitive": false, "value": "osdu"},
      "storage.datasource.password": {"sensitive": true, "value": "osdu123"},
      "storage.datasource.schema": {"sensitive": false, "value": "storage"},
      "schema.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/osdu"},
      "schema.datasource.username": {"sensitive": false, "value": "osdu"},
      "schema.datasource.password": {"sensitive": true, "value": "osdu123"},
      "schema.datasource.schema": {"sensitive": false, "value": "schema_service"},
      "file.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/osdu"},
      "file.datasource.username": {"sensitive": false, "value": "osdu"},
      "file.datasource.password": {"sensitive": true, "value": "osdu123"},
      "file.datasource.schema": {"sensitive": false, "value": "file"}
    }
  }'

echo ""
echo "=== Verifying key properties ==="
$TOOLBOX curl -s \
  "http://osdu-partition:8080/api/partition/v1/partitions/$PARTITION" \
  -H "data-partition-id: $PARTITION" | jq 'to_entries | length' | xargs -I {} echo "Total properties: {}"

echo ""
echo "=== Flushing Redis cache ==="
kubectl run redis-flush-$(date +%s) --rm -it --restart=Never --image=redis:alpine -n osdu-data -- \
  redis-cli -h osdu-redis FLUSHALL

echo ""
echo "Done! All properties added to partition: $PARTITION"
