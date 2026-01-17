# Step 21 - Fix OutOfSync & Integrate RabbitMQ into GitOps

## Mục tiêu
1. Fix osdu-file và osdu-storage bị OutOfSync trong ArgoCD
2. Tích hợp RabbitMQ vào ArgoCD app `osdu-deps` (GitOps)

## Ngày thực hiện
2026-01-17 / 2026-01-18

---

## Phần 1: Fix OutOfSync (osdu-core)

### 1.1 Root Cause Analysis

**Error từ ArgoCD:**
```
Deployment.apps "osdu-storage" is invalid: spec.template.spec.containers[0].image: Required value
Deployment.apps "osdu-file" is invalid: spec.template.spec.containers[0].image: Required value
```

**Nguyên nhân:** Strategic Merge Patches trong Step 20 dùng **sai container name**:

| File | Patch dùng | Base thực tế |
|------|------------|--------------|
| `patch-storage-rabbitmq.yaml` | `name: osdu-storage` | `name: storage` |
| `patch-file-entitlements.yaml` | `name: osdu-file` | `name: file` |

Khi Kustomize không tìm thấy container cùng tên → tạo **container mới** thay vì merge → container mới thiếu `image` field → Kubernetes reject.

### 1.2 Solution

Sửa container name trong patches để match với base deployment:

**patch-storage-rabbitmq.yaml:**
```yaml
spec:
  template:
    spec:
      containers:
        - name: storage  # Changed from osdu-storage
          env:
            - name: OQM_RABBITMQ_RABBITMQRETRYDELAY
              value: "0"
            # ... other env vars
```

**patch-file-entitlements.yaml:**
```yaml
spec:
  template:
    spec:
      containers:
        - name: file  # Changed from osdu-file
          env:
            - name: ENTITLEMENTS_HOST
              value: "http://osdu-entitlements:8080"
            # ... other env vars
```

### 1.3 Verification

```bash
# Validate kustomize build
kubectl kustomize k8s/osdu/core/overlays/do-private > /tmp/core-test.yaml

# Verify image field exists
grep -A 30 "name: osdu-storage" /tmp/core-test.yaml | grep "image:"
grep -A 30 "name: osdu-file" /tmp/core-test.yaml | grep "image:"
```

### 1.4 Result

- osdu-core: **Synced & Healthy**
- osdu-storage: Running 1/1
- osdu-file: Running 1/1

---

## Phần 2: Integrate RabbitMQ into GitOps

### 2.1 Problem

RabbitMQ được deploy thủ công bằng `kubectl apply -f` trong Step 20, không qua ArgoCD → không được quản lý lifecycle.

### 2.2 Solution - Restructure to GitOps

**Cấu trúc mới:**
```
k8s/osdu/deps/
├── base/
│   ├── kustomization.yaml          # Base chính (postgres, opensearch, redis...)
│   └── rabbitmq/
│       ├── kustomization.yaml      # Module rabbitmq
│       └── rabbitmq-deploy.yaml
└── overlays/do-private/
    └── kustomization.yaml          # Include: ../../base + ../../base/rabbitmq
```

**Changes:**

1. **Di chuyển RabbitMQ:**
   ```bash
   mkdir -p k8s/osdu/deps/base/rabbitmq
   mv k8s/osdu/deps/rabbitmq/rabbitmq-deploy.yaml k8s/osdu/deps/base/rabbitmq/
   ```

2. **Tạo kustomization cho rabbitmq:**
   ```yaml
   # k8s/osdu/deps/base/rabbitmq/kustomization.yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - rabbitmq-deploy.yaml
   ```

3. **Cập nhật deps overlay:**
   ```yaml
   # k8s/osdu/deps/overlays/do-private/kustomization.yaml
   resources:
     - ../../base
     - ../../base/rabbitmq  # Added
     - marker-configmap.yaml
   ```

### 2.3 Fix RabbitMQ Probe Timeouts

**Problem:** Pod mới bị CrashLoopBackOff do liveness probe timeout (default 1s quá ngắn).

**Solution:** Thêm `timeoutSeconds` và tăng `initialDelaySeconds`:

```yaml
readinessProbe:
  exec:
    command: ["rabbitmq-diagnostics", "check_running"]
  initialDelaySeconds: 30
  periodSeconds: 15
  timeoutSeconds: 10      # Added (default was 1s)
  failureThreshold: 3
livenessProbe:
  exec:
    command: ["rabbitmq-diagnostics", "ping"]
  initialDelaySeconds: 60  # Increased from 30
  periodSeconds: 30
  timeoutSeconds: 10      # Added (default was 1s)
  failureThreshold: 3
```

### 2.4 Cleanup Old ReplicaSets

Sau khi ArgoCD sync, có thể xuất hiện nhiều ReplicaSets do rollout history:

```bash
# Scale down old RS nếu cần
kubectl -n osdu-data scale rs <old-rs-name> --replicas=0
```

### 2.5 Result

- osdu-deps: **Synced & Healthy**
- RabbitMQ: Running 1/1, managed by ArgoCD
- Probe config: `timeoutSeconds: 10` applied

---

## Final Verification

### ArgoCD Apps Status
```
NAME                        SYNC     HEALTH
app-of-apps-observability   Synced   Healthy
app-of-apps-osdu            Synced   Healthy
obs-ingress                 Synced   Healthy
obs-kube-prometheus-stack   Synced   Healthy
obs-loki                    Synced   Healthy
osdu-ceph                   Synced   Healthy
osdu-core                   Synced   Healthy
osdu-deps                   Synced   Healthy
osdu-identity               Synced   Healthy
```

### OSDU Core Services Health

| Service | Pod Status | Health Check | Notes |
|---------|------------|--------------|-------|
| Partition | 1/1 Running | 200 | ✅ OK |
| Entitlements | 1/1 Running | 401 | ✅ OK (requires auth) |
| Legal | 1/1 Running | 401 | ✅ OK (requires auth) |
| Schema | 1/1 Running | 200 | ✅ OK |
| Storage | 1/1 Running | 404 | ✅ OK (different endpoint) |
| File | 1/1 Running | 404 | ✅ OK (different endpoint) |

### Dependencies Health

| Component | Namespace | Status |
|-----------|-----------|--------|
| PostgreSQL | osdu-data | 1/1 Running |
| OpenSearch | osdu-data | 1/1 Running |
| Redis | osdu-data | 1/1 Running |
| Redpanda | osdu-data | 1/1 Running |
| RabbitMQ | osdu-data | 1/1 Running |
| Keycloak | osdu-identity | 1/1 Running |
| Ceph (RGW) | rook-ceph | Running |

---

## Git Commits

1. **Fix strategic merge patch container names:**
   ```
   Step 21: Fix strategic merge patch container names
   - Storage patch: change container name osdu-storage -> storage
   - File patch: change container name osdu-file -> file
   ```

2. **Integrate RabbitMQ into GitOps:**
   ```
   Step 21: Integrate RabbitMQ into osdu-deps GitOps
   - Move rabbitmq-deploy.yaml to deps/base/rabbitmq/
   - Add kustomization for rabbitmq base
   - Include rabbitmq in deps overlay resources
   ```

3. **Fix RabbitMQ probe timeouts:**
   ```
   Step 21: Fix RabbitMQ probe timeouts
   - Add timeoutSeconds: 10 for both probes
   - Increase initialDelaySeconds for liveness: 30 -> 60
   - Add failureThreshold: 3 explicitly
   ```

---

## Lessons Learned

1. **Kustomize Strategic Merge Patch** yêu cầu container name phải **exact match** với base để merge đúng. Nếu không khớp → tạo container mới.

2. **RabbitMQ diagnostics commands** cần thời gian > 1 giây để hoàn thành. Default `timeoutSeconds: 1` là quá ngắn.

3. **GitOps discipline**: Tất cả resources phải được quản lý qua ArgoCD. Manual `kubectl apply` chỉ dùng cho debugging/emergency.

---

## Files Changed

```
k8s/osdu/core/overlays/do-private/patches/
├── patch-storage-rabbitmq.yaml     # Fixed container name
└── patch-file-entitlements.yaml    # Fixed container name

k8s/osdu/deps/
├── base/rabbitmq/
│   ├── kustomization.yaml          # New
│   └── rabbitmq-deploy.yaml        # Moved + probe fix
└── overlays/do-private/
    └── kustomization.yaml          # Added rabbitmq resource
```

---

## Next Steps

- **Step 22**: Deploy Search service và fix File service 401 error
