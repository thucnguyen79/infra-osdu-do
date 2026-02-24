#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Step 32 — Dataset Service: Evidence Collection + Repo Commit
# Run on ToolServer01: bash /tmp/step32-evidence.sh
# ============================================================

REPO="/opt/infra-osdu-do"
TS=$(date +%Y%m%d-%H%M%S)
EVID="$REPO/artifacts/step32-dataset/$TS"
mkdir -p "$EVID"

echo "=== [1/7] Pod status ==="
kubectl -n osdu-core get pod -l app=osdu-dataset -o wide | tee "$EVID/dataset-pod.txt"
kubectl -n osdu-core get pod -l app=osdu-file -o wide | tee "$EVID/file-pod.txt"

echo ""
echo "=== [2/7] Dataset info endpoint ==="
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s http://osdu-dataset:8080/api/dataset/v1/info | tee "$EVID/dataset-info.txt"

echo ""
echo "=== [3/7] Entitlements groups (dataset) ==="
kubectl -n osdu-core exec deploy/osdu-toolbox -- sh -c '
TOKEN=$(curl -s -X POST \
  "http://keycloak.osdu-identity.svc.cluster.local/realms/osdu/protocol/openid-connect/token" \
  -d "grant_type=password" -d "client_id=osdu-cli" \
  -d "username=test" -d "password=Test@12345" -d "scope=openid" | jq -r ".access_token")
curl -s "http://osdu-entitlements:8080/api/entitlements/v2/groups" \
  -H "Authorization: Bearer $TOKEN" -H "data-partition-id: osdu" | jq "[.groups[].email | select(test(\"dataset|delivery\"))]"
' | tee "$EVID/entitlements-dataset-groups.txt"

echo ""
echo "=== [4/7] DMS handlers in DB ==="
PGPASS=$(kubectl -n osdu-data get secret osdu-postgres-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
kubectl -n osdu-data exec sts/osdu-postgres -c postgres -- bash -c "
PGPASSWORD='$PGPASS' psql -U osduadmin -d schema -c \"SELECT id, data FROM public.\\\"DmsServiceProperties\\\" ORDER BY id;\"
" | tee "$EVID/dms-handlers.txt"

echo ""
echo "=== [5/7] S3 buckets ==="
kubectl -n osdu-core exec deploy/osdu-toolbox -- sh -c '
export AWS_ACCESS_KEY_ID=HNKMSNYU1OWFA4TH3QWT
export AWS_SECRET_ACCESS_KEY=zPPZGaCsDytP84Dqw3bIl0QEd8pwboDUryAMErlg
export AWS_EC2_METADATA_DISABLED=true
aws s3 ls --endpoint-url http://rook-ceph-rgw-osdu-store.rook-ceph.svc.cluster.local:80 2>&1
' | tee "$EVID/s3-buckets.txt"

echo ""
echo "=== [6/7] API smoke tests ==="
kubectl -n osdu-core exec deploy/osdu-toolbox -- sh -c '
TOKEN=$(curl -s -X POST \
  "http://keycloak.osdu-identity.svc.cluster.local/realms/osdu/protocol/openid-connect/token" \
  -d "grant_type=password" -d "client_id=osdu-cli" \
  -d "username=test" -d "password=Test@12345" -d "scope=openid" | jq -r ".access_token")

echo "--- File storageInstructions ---"
curl -s -w "\nHTTP: %{http_code}\n" -X POST \
  "http://osdu-file:8080/api/file/v2/files/storageInstructions" \
  -H "Authorization: Bearer $TOKEN" -H "data-partition-id: osdu"

echo ""
echo "--- Dataset storageInstructions ---"
curl -s -w "\nHTTP: %{http_code}\n" -X POST \
  "http://osdu-dataset:8080/api/dataset/v1/storageInstructions?kindSubType=dataset--File.Generic" \
  -H "Authorization: Bearer $TOKEN" -H "data-partition-id: osdu"
' | tee "$EVID/smoke-test-storage-instructions.txt"

echo ""
echo "=== [7/7] Copy docs ==="
# Copy doc into repo
mkdir -p "$REPO/docs/osdu"
cp /tmp/step32-doc.md "$REPO/docs/osdu/38-step32-dataset-service.md"

# Append checklist
cat /tmp/step32-checklist-append.md >> "$REPO/04-deploy-checklist.md"

echo ""
echo "=== Evidence saved to: $EVID ==="
ls -la "$EVID/"

echo ""
echo "=== Git commit ==="
cd "$REPO"
git add -A
git status
git commit -m "docs(step32): Dataset service deployment + DMS integration

- Dataset service deployed (core-plus-dataset-release:4cae824d)
- DMS handler registration (DmsServiceProperties table + seed data)
- Entitlements plural groups fix (editors/viewers)
- S3 buckets created (staging + persistent)
- File service authorization fixed (401 → 200)
- Full smoke test passing (storageInstructions HTTP 200)
- Evidence collected in artifacts/step32-dataset/"

echo ""
echo "=== Ready to push: git push ==="
