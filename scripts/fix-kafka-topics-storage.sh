#!/bin/bash
set -e

echo "============================================================"
echo "Step 22 Fix: Create Kafka topics in Redpanda for OSDU Storage"
echo "============================================================"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Variables
NAMESPACE_DATA="osdu-data"
NAMESPACE_CORE="osdu-core"
REDPANDA_POD="osdu-redpanda-0"
TENANT="osdu"

# Topics required by OSDU Storage service
TOPICS=(
  # With tenant prefix (osdu.)
  "${TENANT}.legaltags-changed"
  "${TENANT}.records-changed"
  "${TENANT}.dead-lettering-replay"
  "${TENANT}.dead-lettering-replay-subscription"
  "${TENANT}.replaytopic"
  "${TENANT}.storage-records-changed"
  # Without tenant prefix (fallback)
  "legaltags-changed"
  "records-changed"
  "dead-lettering-replay"
  "dead-lettering-replay-subscription"
  "replaytopic"
  "storage-records-changed"
)

# ============================================================
# Step 1: Check Redpanda is running
# ============================================================
echo "=== 1. Check Redpanda pod status ==="
kubectl -n ${NAMESPACE_DATA} get pod ${REDPANDA_POD} -o wide
if [ $? -ne 0 ]; then
  echo "ERROR: Redpanda pod not found!"
  exit 1
fi
echo "OK: Redpanda is running"
echo ""

# ============================================================
# Step 2: List existing topics
# ============================================================
echo "=== 2. List existing Kafka topics ==="
kubectl -n ${NAMESPACE_DATA} exec ${REDPANDA_POD} -- rpk topic list
echo ""

# ============================================================
# Step 3: Create required topics
# ============================================================
echo "=== 3. Create required topics for OSDU ==="
for topic in "${TOPICS[@]}"; do
  echo -n "  Creating topic: ${topic} ... "
  result=$(kubectl -n ${NAMESPACE_DATA} exec ${REDPANDA_POD} -- rpk topic create "${topic}" --partitions 1 --replicas 1 2>&1) || true
  if echo "$result" | grep -q "TOPIC_ALREADY_EXISTS"; then
    echo "already exists"
  elif echo "$result" | grep -q "Created topic"; then
    echo "created"
  else
    echo "result: $result"
  fi
done
echo ""

# ============================================================
# Step 4: Verify all topics
# ============================================================
echo "=== 4. Verify all topics created ==="
kubectl -n ${NAMESPACE_DATA} exec ${REDPANDA_POD} -- rpk topic list
echo ""

# ============================================================
# Step 5: Restart Storage deployment
# ============================================================
echo "=== 5. Restart Storage deployment ==="
kubectl -n ${NAMESPACE_CORE} rollout restart deploy/osdu-storage
echo ""

# ============================================================
# Step 6: Wait for rollout
# ============================================================
echo "=== 6. Wait for Storage rollout (timeout 180s) ==="
kubectl -n ${NAMESPACE_CORE} rollout status deploy/osdu-storage --timeout=180s
echo ""

# ============================================================
# Step 7: Check Storage pod status
# ============================================================
echo "=== 7. Check Storage pod status ==="
kubectl -n ${NAMESPACE_CORE} get pod -l app=osdu-storage -o wide
echo ""

# ============================================================
# Step 8: Check Storage logs
# ============================================================
echo "=== 8. Storage logs (last 50 lines) ==="
sleep 10
kubectl -n ${NAMESPACE_CORE} logs -l app=osdu-storage --tail=50
echo ""

# ============================================================
# Step 9: Health check
# ============================================================
echo "=== 9. Storage health check ==="
STORAGE_POD=$(kubectl -n ${NAMESPACE_CORE} get pod -l app=osdu-storage -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$STORAGE_POD" ]; then
  echo "Checking readiness of pod: ${STORAGE_POD}"
  kubectl -n ${NAMESPACE_CORE} get pod ${STORAGE_POD} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  echo ""
else
  echo "WARNING: No Storage pod found"
fi
echo ""

echo "============================================================"
echo "DONE - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================================"
echo ""
echo "CHECKLIST:"
echo "  [x] Redpanda running"
echo "  [x] Kafka topics created"
echo "  [x] Storage deployment restarted"
echo "  [ ] Storage pod Ready 1/1 (check above)"
echo "  [ ] No errors in Storage logs (check above)"
echo ""
echo "If Storage still fails, check:"
echo "  1. kubectl -n osdu-core logs -l app=osdu-storage --tail=100"
echo "  2. kubectl -n osdu-core describe pod -l app=osdu-storage"
echo "  3. Verify OQM_DRIVER env: kubectl -n osdu-core get deploy osdu-storage -o yaml | grep OQM_DRIVER"
