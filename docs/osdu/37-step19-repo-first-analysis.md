# Step 19 - Repo-first Analysis

## Tóm tắt

| Thao tác | Repo-first? | Lý do | Action |
|----------|-------------|-------|--------|
| Partition properties | ❌ | Runtime config qua API | Document trong runbook |
| DB schemas | ⚠️ Partial | One-time nhưng nên có SQL files | Tạo SQL files + K8s Job |
| Service env vars | ✅ YES | Cần cập nhật deployment YAML | Update Kustomize overlays |
| Entitlements bootstrap | ❌ | Operational, có thể thay đổi | Document trong runbook |

## Chi tiết

### 1. Partition Properties - KHÔNG Repo-first

**Lý do:**
- Partition service quản lý config động qua REST API
- Properties có thể thay đổi tùy môi trường (dev/staging/prod)
- Sensitive values cần quản lý riêng

**Recommendation:**
- Tạo script bootstrap (`scripts/bootstrap/01-init-partition.sh`)
- Document trong runbook
- Có thể tạo ConfigMap chứa template JSON cho reference

### 2. Database Schemas - PARTIAL Repo-first

**Lý do:**
- SQL schemas nên được version control
- Nhưng việc apply cần chạy manually hoặc qua Job

**Recommendation:**
- Tạo SQL files trong `k8s/osdu/deps/base/initdb/`
- Sử dụng ConfigMap mount vào postgres initdb
- Hoặc tạo K8s Job để apply migrations

**Files cần tạo:**
```
k8s/osdu/deps/base/initdb/
├── 01-entitlements-schema.sql
├── 02-legal-schema.sql
├── 03-storage-schema.sql (nếu cần)
└── 04-schema-service-schema.sql (nếu cần)
```

### 3. Service Environment Variables - CẦN Repo-first

**Lý do:**
- Env vars là phần cố định của deployment
- Cần consistent across environments
- Nên track trong Git

**Action Required:**
```yaml
# k8s/osdu/core/base/entitlements.yaml - thêm env
env:
  - name: REDIS_USER_INFO_HOST
    value: "osdu-redis.osdu-data.svc.cluster.local"
  - name: REDIS_USER_GROUPS_HOST
    value: "osdu-redis.osdu-data.svc.cluster.local"
  # ... other vars
```
```yaml
# k8s/osdu/core/base/legal.yaml - thêm env
env:
  - name: PARTITION_HOST
    value: "http://osdu-partition:8080"
  - name: ENTITLEMENTS_HOST
    value: "http://osdu-entitlements:8080"
  # ... other vars
```

### 4. Entitlements Bootstrap Data - KHÔNG Repo-first

**Lý do:**
- User/group data là operational config
- Có thể thay đổi theo từng môi trường
- Sensitive (user emails, permissions)

**Recommendation:**
- Tạo script bootstrap (`scripts/bootstrap/03-init-entitlements.sh`)
- Document trong runbook
- Có thể tạo "seed data" JSON cho reference

## Action Items

### Immediate (Blocking)
1. [ ] Update `k8s/osdu/core/base/entitlements.yaml` với env vars
2. [ ] Update `k8s/osdu/core/base/legal.yaml` với env vars
3. [ ] Commit và push changes
4. [ ] Sync ArgoCD

### Soon (Before Production)
1. [ ] Tạo SQL migration files trong repo
2. [ ] Tạo K8s Job để apply DB migrations
3. [ ] Tạo runbooks cho operational tasks

### Nice to Have
1. [ ] Helm chart với configurable values
2. [ ] Automated bootstrap pipeline
3. [ ] Integration tests
