#!/bin/bash
# ============================================
# OSDU S3 Buckets Bootstrap Script
# Step 24: Storage Service Fix
# Created: 2026-01-25
# ============================================

set -e

# Configuration
S3_ENDPOINT="http://rook-ceph-rgw-osdu-store.rook-ceph.svc.cluster.local:80"
TOOLBOX="kubectl -n osdu-core exec deploy/osdu-toolbox --"

# Get S3 credentials from Ceph secret
S3_ACCESS=$(kubectl -n rook-ceph get secret rook-ceph-object-user-osdu-store-osdu-s3-user -o jsonpath='{.data.AccessKey}' | base64 -d)
S3_SECRET=$(kubectl -n rook-ceph get secret rook-ceph-object-user-osdu-store-osdu-s3-user -o jsonpath='{.data.SecretKey}' | base64 -d)

echo "=== Creating OSDU S3 Buckets ==="

# Required buckets for OSDU
BUCKETS=(
    "osdu-legal"
    "osdu-storage"
    "osdu-file"
    "osdu-poc-osdu-records"      # Storage service records bucket
    "osdu-poc-osdu-legal-config" # Legal service config bucket (optional)
)

# Install mc (minio client) if not present
$TOOLBOX sh -c "
if [ ! -f /tmp/mc ]; then
    curl -sLo /tmp/mc https://dl.min.io/client/mc/release/linux-amd64/mc
    chmod +x /tmp/mc
fi

/tmp/mc alias set ceph $S3_ENDPOINT '$S3_ACCESS' '$S3_SECRET'

for bucket in ${BUCKETS[*]}; do
    echo \"Creating bucket: \$bucket\"
    /tmp/mc mb ceph/\$bucket --ignore-existing 2>/dev/null || true
done

echo ''
echo '=== Current buckets ==='
/tmp/mc ls ceph/
"

echo "=== S3 Buckets Bootstrap Complete ==="
