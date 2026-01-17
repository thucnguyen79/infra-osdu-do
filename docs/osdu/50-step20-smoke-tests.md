# Step 20 - Smoke Tests & POC Validation

## Mục tiêu
Thực hiện smoke tests để validate POC hoạt động end-to-end.

## Prerequisites
- Step 18: OSDU Core Services deployed
- Step 19: Basic connectivity verified
- Keycloak user `test` with password `Test@12345`

## Thay đổi trong Step 20

### A. RabbitMQ Deployment

**Lý do:** OSDU Core Plus Storage image hardcode yêu cầu RabbitMQ để messaging giữa services (legaltags-changed events).

**Files:**
- `k8s/osdu/deps/rabbitmq/rabbitmq-deploy.yaml`

### B. Storage Service - RabbitMQ Retry Bypass

**Lý do:** Storage cần `x-delayed-message` exchange type (RabbitMQ plugin), nhưng ta không cài plugin. Set `rabbitmqRetryDelay=0` để bypass validation.

**Files:**
- `k8s/osdu/core/overlays/do-private/patches/patch-storage-rabbitmq.yaml`

**Env vars:**
```yaml
OQM_RABBITMQ_RABBITMQRETRYDELAY: "0"
RABBITMQ_RETRY_DELAY: "0"
OQM_RABBITMQ_RETRY_DELAY: "0"
OQM_RABBITMQ_RETRY_ENABLED: "false"
RABBITMQ_RETRY_ENABLED: "false"
```

### C. File Service - Entitlements Config

**Lý do:** File service cần biết Entitlements endpoint để authorize requests.

**Files:**
- `k8s/osdu/core/overlays/do-private/patches/patch-file-entitlements.yaml`

**Env vars:**
```yaml
ENTITLEMENTS_HOST: http://osdu-entitlements:8080
ENTITLEMENTS_PATH: /api/entitlements/v2/
AUTHORIZE_API: http://osdu-entitlements:8080/api/entitlements/v2/
```

### D. Bootstrap Data (via Script)

**Lý do:** Seed partition properties và entitlements groups cho smoke tests.

**Script:** `scripts/bootstrap/bootstrap-step20.sh`

**Seeded data:**
1. **Partition properties:**
   - RabbitMQ connection (amqp.host, amqp.port, etc.)
   - RabbitMQ admin (admin.host, admin.port, etc.)
   - Retry bypass (rabbitmqRetryDelay=0)

2. **Entitlements groups:**
   - service.search.admin
   - service.search.user
   - service.search.viewer
   - service.search.editor

3. **S3 Buckets:**
   - osdu-storage
   - osdu-file

### E. Manual DB Fix (documented only)

**Lý do:** Search groups được tạo với domain sai (`@osdu.group` thay vì `@osdu.osdu.local`).

**SQL đã chạy:**
```sql
UPDATE "group" 
SET email = REPLACE(email, '@osdu.group', '@osdu.osdu.local')
WHERE name LIKE 'service.search.%';

INSERT INTO member_to_group (member_id, group_id, role, created_at)
SELECT 1, id, 'MEMBER', NOW()
FROM "group" WHERE name LIKE 'service.search.%'
ON CONFLICT DO NOTHING;
```

## Deployment Order

1. Deploy RabbitMQ:
   ```bash
   kubectl apply -f k8s/osdu/deps/rabbitmq/rabbitmq-deploy.yaml
   kubectl -n osdu-data rollout status deploy/osdu-rabbitmq
   ```

2. Apply core patches:
   ```bash
   kubectl apply -k k8s/osdu/core/overlays/do-private
   ```

3. Run bootstrap script:
   ```bash
   ./scripts/bootstrap/bootstrap-step20.sh
   ```

4. Restart services:
   ```bash
   kubectl -n osdu-core rollout restart deploy osdu-storage osdu-file
   ```

## Services Status (sau Step 20)

| Service | Status | Notes |
|---------|--------|-------|
| Partition | ✅ 200 | OK |
| Entitlements | ✅ 200 | OK |
| Legal | ✅ 200 | OK |
| Schema | ✅ 200 | OK |
| Storage | ✅ 200 | Fixed (RabbitMQ retry=0) |
| File | ⚠️ 401 | Needs Search service |
| Search | ❌ | Not deployed |

## Known Issues

### File Service 401 Error
- **Symptom:** `required search service roles are missing for user`
- **Cause:** File service requires Search service for authorization
- **Solution:** Deploy Search service (Option A) or skip File for POC (Option B)

## Next Steps

- **Option A:** Deploy Search service để hoàn thiện POC
- **Option B:** Proceed với 5/6 services cho basic smoke tests
