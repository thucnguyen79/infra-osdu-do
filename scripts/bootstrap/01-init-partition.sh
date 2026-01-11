#!/bin/bash
# 01-init-partition.sh - Initialize OSDU Partition with required properties
# Usage: ./01-init-partition.sh [PARTITION_NAME]
set -e

PARTITION_NAME="${1:-osdu}"
NAMESPACE="osdu-core"

echo "=== Initializing partition: $PARTITION_NAME ==="

kubectl -n $NAMESPACE exec -it deploy/osdu-toolbox -- curl -s -X PATCH \
  "http://osdu-partition:8080/api/partition/v1/partitions/$PARTITION_NAME" \
  -H "Content-Type: application/json" \
  -H "data-partition-id: $PARTITION_NAME" \
  -d '{
    "properties": {
      "dataPartitionId": {"sensitive": false, "value": "'$PARTITION_NAME'"},
      "name": {"sensitive": false, "value": "'$PARTITION_NAME'"},
      "projectId": {"sensitive": false, "value": "'$PARTITION_NAME'-project"},
      "crmAccountID": {"sensitive": false, "value": "[\"'$PARTITION_NAME'-crm\"]"},
      "complianceRuleSet": {"sensitive": false, "value": "shared"},
      "serviceAccount": {"sensitive": false, "value": "'$PARTITION_NAME'-service"},
      "storageAccountName": {"sensitive": false, "value": "'$PARTITION_NAME'"},
      "domain": {"sensitive": false, "value": "'$PARTITION_NAME'.local"},
      "gcpProjectId": {"sensitive": false, "value": "'$PARTITION_NAME'-project"},
      "elastic-endpoint": {"sensitive": false, "value": "http://osdu-opensearch.osdu-data:9200"},
      "elastic-username": {"sensitive": false, "value": "admin"},
      "elastic-password": {"sensitive": false, "value": "admin"},
      "redis-database": {"sensitive": false, "value": "4"},
      "osm.postgres.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/legal"},
      "osm.postgres.datasource.username": {"sensitive": false, "value": "osduadmin"},
      "osm.postgres.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
      "osm.postgres.datasource.schema": {"sensitive": false, "value": "public"},
      "obm.minio.endpoint": {"sensitive": false, "value": "http://rook-ceph-rgw-osdu-store.rook-ceph:80"},
      "obm.minio.accessKey": {"sensitive": false, "value": "osdu-s3-user"},
      "obm.minio.secretKey": {"sensitive": true, "value": "OBM_MINIO_SECRET_KEY"},
      "obm.minio.bucket": {"sensitive": false, "value": "osdu-legal"},
      "legal-tag-allowed-data-types": {"sensitive": false, "value": "[\"Public Domain Data\",\"Third Party Data\",\"Transferred Data\"]"},
      "legal-tag-allowed-security-classifications": {"sensitive": false, "value": "[\"Public\",\"Private\",\"Confidential\"]"},
      "compliance-ruleset-id": {"sensitive": false, "value": "shared"},
      "entitlements.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/entitlements"},
      "entitlements.datasource.username": {"sensitive": false, "value": "osduadmin"},
      "entitlements.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
      "entitlements.datasource.schema": {"sensitive": false, "value": "public"},
      "legal.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/legal"},
      "legal.datasource.username": {"sensitive": false, "value": "osduadmin"},
      "legal.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
      "legal.datasource.schema": {"sensitive": false, "value": "public"},
      "storage.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/storage"},
      "storage.datasource.username": {"sensitive": false, "value": "osduadmin"},
      "storage.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
      "storage.datasource.schema": {"sensitive": false, "value": "public"},
      "schema.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/schema"},
      "schema.datasource.username": {"sensitive": false, "value": "osduadmin"},
      "schema.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
      "schema.datasource.schema": {"sensitive": false, "value": "public"},
      "file.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/file"},
      "file.datasource.username": {"sensitive": false, "value": "osduadmin"},
      "file.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
      "file.datasource.schema": {"sensitive": false, "value": "public"}
    }
  }'

echo ""
echo "=== Partition $PARTITION_NAME initialized ==="
