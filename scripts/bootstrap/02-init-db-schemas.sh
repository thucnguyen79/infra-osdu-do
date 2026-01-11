#!/bin/bash
# 02-init-db-schemas.sh - Initialize OSDU database schemas
set -e

NAMESPACE="osdu-core"
PG_HOST="osdu-postgres.osdu-data.svc.cluster.local"
PG_USER="osduadmin"
PG_PASS="CHANGE_ME_STRONG"

echo "=== Initializing Entitlements Database Schema ==="
kubectl -n $NAMESPACE exec -it deploy/osdu-toolbox -- bash -c "
PGPASSWORD=$PG_PASS psql -h $PG_HOST -U $PG_USER -d entitlements -f - << 'EOSQL'
$(cat /opt/infra-osdu-do/k8s/osdu/deps/base/initdb/01-entitlements-schema.sql)
EOSQL
"

echo "=== Initializing Legal Database Schema ==="
kubectl -n $NAMESPACE exec -it deploy/osdu-toolbox -- bash -c "
PGPASSWORD=$PG_PASS psql -h $PG_HOST -U $PG_USER -d legal -f - << 'EOSQL'
$(cat /opt/infra-osdu-do/k8s/osdu/deps/base/initdb/02-legal-schema.sql)
EOSQL
"

echo "=== All database schemas initialized ==="
