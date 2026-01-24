# Step 23: Fix Legal & Storage OBM Configuration

**Mục tiêu:** Ghi nhận config OBM (Object Blob Management) vào repo để persist qua ArgoCD sync.

---

## 1. Background

### 1.1 Vấn đề

Legal Service đã hoạt động sau khi apply runtime config:
```bash
kubectl -n osdu-core set env deploy/osdu-legal \
  OBM_DRIVER=minio \
  OBM_MINIO_ENDPOINT="http://rook-ceph-rgw-osdu-store.rook-ceph.svc.cluster.local:80" \
  ...
```

Tuy nhiên, config này **không được ghi vào repo**, dẫn đến:
- ArgoCD sync sẽ **revert** về state cũ
- Hard reset cluster sẽ **mất** config
- Không reproducible

### 1.2 Root Cause trong patches hiện có

File `patch-legal-all.yaml` có 2 vấn đề:

1. **Cross-namespace secret** - Không hoạt động:
```yaml
# SAI - Kubernetes không cho phép
secretKeyRef:
  name: rook-ceph-object-user-osdu-store-osdu-s3-user  # namespace: rook-ceph
```

2. **Thiếu env vars**:
- `OBM_DRIVER` - Không có
- `OBM_MINIO_ENDPOINT` - Không có
- `OBM_MINIO_BUCKET` - Không có
- `OBM_MINIO_ACCESS_KEY` - Không có

---

## 2. Solution Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         osdu-core namespace                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐      ┌──────────────────────────────┐     │
│  │ osdu-s3-credentials │◄────│ create-s3-secret.sh          │     │
│  │ (Secret)          │      │ (copies from rook-ceph)      │     │
│  │ - accessKey       │      └──────────────────────────────┘     │
│  │ - secretKey       │                                           │
│  └────────┬─────────┘                                           │
│           │                                                      │
│           │ valueFrom.secretKeyRef                              │
│           ▼                                                      │
│  ┌──────────────────┐      ┌──────────────────┐                 │
│  │ osdu-legal        │      │ osdu-storage      │                 │
│  │ (Deployment)      │      │ (Deployment)      │                 │
│  │ env:              │      │ env:              │                 │
│  │ - OBM_DRIVER      │      │ - OBM_DRIVER      │                 │
│  │ - OBM_MINIO_*     │      │ - OBM_MINIO_*     │                 │
│  └──────────────────┘      └──────────────────┘                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
          │
          │ S3 API calls
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                         rook-ceph namespace                      │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────┐                   │
│  │ rook-ceph-rgw-osdu-store                  │                   │
│  │ (Ceph Object Gateway - S3 compatible)     │                   │
│  │ Endpoint: :80                             │                   │
│  └──────────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Files Changed

### 3.1 `patches/patch-legal-all.yaml` (REPLACE)

**Changes:**
- Added `OBM_DRIVER=minio`
- Added `OBM_MINIO_ENDPOINT`
- Added `OBM_MINIO_BUCKET`
- Added `OBM_MINIO_ACCESS_KEY` (from local secret)
- Fixed `OBM_MINIO_SECRET_KEY` (from local secret, not cross-namespace)

### 3.2 `patches/patch-storage-openid.yaml` (UPDATE)

**Changes:**
- Added OBM section at the end with same 5 env vars

### 3.3 `scripts/create-s3-secret.sh` (NEW)

Script to copy S3 credentials from `rook-ceph` namespace to `osdu-core` namespace.

### 3.4 `scripts/seed-partition-osdu.sh` (NEW)

Script to seed partition properties (reproducible).

### 3.5 `secrets/osdu-s3-credentials.yaml.template` (NEW)

Template for documentation. **DO NOT commit actual values.**

---

## 4. OBM Environment Variables Reference

| Env Var | Value | Description |
|---------|-------|-------------|
| `OBM_DRIVER` | `minio` | Enable MinIO/S3 driver |
| `OBM_MINIO_ENDPOINT` | `http://rook-ceph-rgw-osdu-store.rook-ceph.svc.cluster.local:80` | Ceph RGW endpoint |
| `OBM_MINIO_BUCKET` | `osdu-legal` / `osdu-storage` | Bucket name per service |
| `OBM_MINIO_ACCESS_KEY` | (from secret) | S3 access key |
| `OBM_MINIO_SECRET_KEY` | (from secret) | S3 secret key |

---

## 5. Partition Properties (for reference)

Partition cũng cần các properties này (seed bằng script hoặc API):

```json
{
  "obm.minio.endpoint": "http://rook-ceph-rgw-osdu-store.rook-ceph.svc.cluster.local:80",
  "obm.minio.bucket": "osdu-legal",
  "obm.minio.accessKey": "OBM_MINIO_ACCESS_KEY",
  "obm.minio.secretKey": "OBM_MINIO_SECRET_KEY"
}
```

**Note:** Partition lưu **ENV VAR names**, không phải values. Services sẽ resolve từ pod env.

---

## 6. Testing

### 6.1 Verify env vars

```bash
# Legal
kubectl -n osdu-core exec deploy/osdu-legal -- env | grep -i OBM

# Expected:
# OBM_DRIVER=minio
# OBM_MINIO_ENDPOINT=http://rook-ceph-rgw-osdu-store.rook-ceph.svc.cluster.local:80
# OBM_MINIO_BUCKET=osdu-legal
# OBM_MINIO_ACCESS_KEY=<value>
# OBM_MINIO_SECRET_KEY=<value>

# Storage
kubectl -n osdu-core exec deploy/osdu-storage -- env | grep -i OBM
```

### 6.2 Test Legal API

```bash
TOOLBOX="kubectl -n osdu-core exec deploy/osdu-toolbox --"
TOKEN=$($TOOLBOX curl -s -X POST \
    "http://keycloak.osdu-identity.svc.cluster.local/realms/osdu/protocol/openid-connect/token" \
    -d "grant_type=password" \
    -d "client_id=osdu-cli" \
    -d "username=test" \
    -d "password=Test@12345" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

# Test GET
$TOOLBOX curl -s \
    -H "Authorization: Bearer $TOKEN" \
    -H "data-partition-id: osdu" \
    -H "X-Forwarded-Proto: https" \
    "http://osdu-legal:8080/api/legal/v1/legaltags:properties" | head -100

# Test POST
$TOOLBOX curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "data-partition-id: osdu" \
    -H "Content-Type: application/json" \
    -H "X-Forwarded-Proto: https" \
    "http://osdu-legal:8080/api/legal/v1/legaltags" \
    -d '{"name":"test-step23-'$(date +%s)'","description":"test","properties":{"countryOfOrigin":["US"],"contractId":"TEST","dataType":"Public Domain Data","exportClassification":"EAR99","originator":"Test","personalData":"No Personal Data","securityClassification":"Public","expirationDate":"2030-12-31"}}'
```

---

## 7. Troubleshooting

### 7.1 Pod không start - Secret not found

```bash
# Check secret exists
kubectl -n osdu-core get secret osdu-s3-credentials

# If not exists, create:
./scripts/create-s3-secret.sh
```

### 7.2 Legal API returns 500

Check logs:
```bash
kubectl -n osdu-core logs deploy/osdu-legal --tail=100 | grep -i "error\|exception"
```

Common issues:
- S3 bucket không tồn tại → Tạo bucket trong Ceph
- Credentials sai → Verify secret values
- Partition properties thiếu → Run seed script

### 7.3 ArgoCD shows OutOfSync

```bash
# Force sync với prune
argocd app sync osdu-core --prune

# Hoặc qua UI: Settings > Sync > Prune
```
