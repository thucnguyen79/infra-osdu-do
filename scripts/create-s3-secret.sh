#!/bin/bash
# scripts/create-s3-secret.sh
# Copy S3 credentials from rook-ceph namespace to osdu-core namespace
#
# This script creates secret 'osdu-s3-credentials' in osdu-core namespace
# by reading values from Ceph user secret in rook-ceph namespace.
#
# Usage: ./scripts/create-s3-secret.sh
# Prerequisites: kubectl configured with cluster access

set -e

echo "=== Create S3 Secret for OSDU Core ==="
echo "Date: $(date -Iseconds)"
echo ""

# Configuration
SOURCE_NS="rook-ceph"
SOURCE_SECRET="rook-ceph-object-user-osdu-store-osdu-s3-user"
TARGET_NS="osdu-core"
TARGET_SECRET="osdu-s3-credentials"

# Check source secret exists
echo "Checking source secret..."
if ! kubectl -n $SOURCE_NS get secret $SOURCE_SECRET &>/dev/null; then
    echo "ERROR: Source secret '$SOURCE_SECRET' not found in namespace '$SOURCE_NS'"
    echo "Make sure Ceph Object Store user is created."
    exit 1
fi
echo "✓ Source secret found"

# Extract credentials
echo "Extracting credentials..."
ACCESS_KEY=$(kubectl -n $SOURCE_NS get secret $SOURCE_SECRET -o jsonpath='{.data.AccessKey}' | base64 -d)
SECRET_KEY=$(kubectl -n $SOURCE_NS get secret $SOURCE_SECRET -o jsonpath='{.data.SecretKey}' | base64 -d)

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    echo "ERROR: Failed to extract credentials from source secret"
    exit 1
fi
echo "✓ Credentials extracted (AccessKey: ${ACCESS_KEY:0:8}...)"

# Check target namespace exists
echo "Checking target namespace..."
if ! kubectl get ns $TARGET_NS &>/dev/null; then
    echo "ERROR: Target namespace '$TARGET_NS' not found"
    exit 1
fi
echo "✓ Target namespace exists"

# Create or update secret
echo "Creating/updating secret in $TARGET_NS..."
kubectl -n $TARGET_NS create secret generic $TARGET_SECRET \
    --from-literal=accessKey="$ACCESS_KEY" \
    --from-literal=secretKey="$SECRET_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "=== Verification ==="
kubectl -n $TARGET_NS get secret $TARGET_SECRET

echo ""
echo "=== Done ==="
echo "Secret '$TARGET_SECRET' is ready in namespace '$TARGET_NS'"
echo ""
echo "Services can now reference this secret with:"
echo "  valueFrom:"
echo "    secretKeyRef:"
echo "      name: $TARGET_SECRET"
echo "      key: accessKey  # or secretKey"
