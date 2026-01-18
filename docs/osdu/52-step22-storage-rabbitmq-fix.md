# Step 22 — Storage Service RabbitMQ Fix

**Date:** 2026-01-18  
**Status:** ✅ Completed

## Mục tiêu

Fix Storage service không khởi động được do yêu cầu RabbitMQ dead-lettering subscription.

---

## Vấn đề gặp phải

### 1. Lỗi ban đầu: `vhost not found`
```
NOT_ALLOWED - vhost  not found
```
Storage kết nối RabbitMQ với vhost rỗng thay vì `/`.

### 2. Lỗi tiếp theo: `Required subscription not exists`
```
Required subscription not exists. Create subscription: dead-lettering-replay-subscription for tenant: osdu
```
Storage image (GCP Core Plus) có class `OqmDeadLetteringSubscriberManager` kiểm tra subscription khi khởi động.

---

## Root Cause Analysis

1. **Storage image** (`core-plus-storage-core-plus-release:dcc4c072`) là GCP-specific với hardcoded RabbitMQ requirements
2. **OqmDeadLetteringSubscriberManager** kiểm tra subscription `dead-lettering-replay-subscription` qua RabbitMQ Admin API
3. Dù RabbitMQ đã có queue/exchange, code GCP vẫn fail do cách check đặc thù
4. **Giải pháp**: Disable replay feature (`FEATURE_REPLAY_ENABLED=false`)

---

## Giải pháp đã triển khai

### 1. Cập nhật RabbitMQ definitions (Repo)

**File:** `k8s/osdu/deps/base/rabbitmq/rabbitmq-deploy.yaml`

Thêm đầy đủ exchanges, queues, bindings:
- `dead-lettering-replay` exchange
- `dead-lettering-replay-subscription` exchange + queue
- `replaytopic`, `replaytopicsubscription-exchange`
- Cả prefix `osdu.` và không prefix

### 2. Cập nhật Storage patch (Repo)

**File:** `k8s/osdu/core/overlays/do-private/patches/patch-storage-rabbitmq.yaml`

Thêm env vars:
```yaml
# Disable replay feature for POC (bypass dead-lettering check)
- name: FEATURE_REPLAY_ENABLED
  value: "false"
- name: DEAD_LETTERING_REQUIRED
  value: "false"
```

### 3. Cập nhật Partition Properties (Runtime/DB)

Thêm RabbitMQ replay/dead-lettering properties vào partition `osdu`:
```json
{
  "oqm.rabbitmq.replay.topic": "replaytopic",
  "oqm.rabbitmq.replay.subscription": "replaytopicsubscription",
  "oqm.rabbitmq.dead-lettering.topic": "dead-lettering-replay",
  "oqm.rabbitmq.dead-lettering.subscription": "dead-lettering-replay-subscription"
}
```

---

## Ảnh hưởng khi disable Replay feature

| Tính năng | Sau khi disable | Ghi chú |
|-----------|-----------------|---------|
| CRUD Records (create/read/update/delete) | ✅ Hoạt động | Core functionality |
| Search integration | ✅ Hoạt động | `records-changed` vẫn publish |
| Legal tags compliance | ✅ Hoạt động | `legaltags-changed` vẫn hoạt động |
| **Replay API** | ❌ Không hoạt động | Tính năng re-index/replay records |
| **Dead-lettering** | ❌ Không hoạt động | Xử lý message lỗi |

**Kết luận**: Chấp nhận được cho POC. Production cần dùng image phù hợp (baremetal/community).

---

## Files Changed (Git)

```
k8s/osdu/deps/base/rabbitmq/
└── rabbitmq-deploy.yaml              # Updated definitions.json

k8s/osdu/core/overlays/do-private/patches/
└── patch-storage-rabbitmq.yaml       # Added FEATURE_REPLAY_ENABLED=false

scripts/bootstrap/
└── init-partition-osdu.sh            # Bootstrap script (NEW)
```

---

## Runtime Changes (NOT in Git - need bootstrap script)

| Thay đổi | Vị trí | Cách reproduce |
|----------|--------|----------------|
| Partition properties (oqm.rabbitmq.*) | Postgres DB `partition` | Run `init-partition-osdu.sh` |
| Redis flush | Memory | `redis-cli -h osdu-redis FLUSHALL` |

---

## Bootstrap Script

**File:** `scripts/bootstrap/init-partition-osdu.sh`

Script này cần chạy sau khi deploy OSDU core services lần đầu để seed partition properties.

**Usage:**
```bash
# Copy script vào toolbox và chạy
kubectl -n osdu-core cp scripts/bootstrap/init-partition-osdu.sh osdu-toolbox-xxx:/tmp/
kubectl -n osdu-core exec deploy/osdu-toolbox -- bash /tmp/init-partition-osdu.sh

# Hoặc chạy trực tiếp
kubectl -n osdu-core exec deploy/osdu-toolbox -- bash < scripts/bootstrap/init-partition-osdu.sh

# Sau đó flush Redis
kubectl run redis-flush --rm -it --restart=Never --image=redis:alpine -n osdu-data -- redis-cli -h osdu-redis FLUSHALL
```

---

## Kết quả

```
Started StorageCorePlusApplication in 3.034 seconds
Tomcat started on port 8080 (http) with context path '/api/storage/v2'
Pod: 1/1 Running
```

---

## Lessons Learned

1. **GCP-specific images** có hardcoded requirements khác với baremetal/community images
2. **Feature flags** (`FEATURE_REPLAY_ENABLED`) có thể bypass các checks không cần thiết cho POC
3. **Partition properties** được đọc từ DB, cần bootstrap script để reproducible
4. **Repo-first** quan trọng: mọi config cần lưu vào Git hoặc có script bootstrap

---

## Next Steps

- [ ] Step 23: Deploy Search service
- [ ] Step 24: Deploy Indexer service  
- [ ] Step 25: End-to-end test (ingest → search)
