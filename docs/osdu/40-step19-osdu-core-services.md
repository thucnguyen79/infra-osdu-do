# Step 19: OSDU Core Services Deployment

## Mục tiêu

Triển khai và cấu hình 6 OSDU Core Services:
- Partition Service
- Entitlements Service
- Legal Service
- Schema Service
- File Service
- Storage Service

## Kết quả

| Service | Status | HTTP Code | Pod |
|---------|--------|-----------|-----|
| Partition | ✅ Running | 200 | osdu-partition-* |
| Entitlements | ✅ Running | 200 | osdu-entitlements-* |
| Legal | ✅ Running | 200 | osdu-legal-* |
| Schema | ✅ Running | 200 | osdu-schema-* |
| File | ✅ Running | 200 | osdu-file-* |
| Storage | ✅ Running | 200 | osdu-storage-* |

**Tổng: 6/6 services hoạt động**

## Các vấn đề và giải pháp

### 1. Kustomize Patch Conflicts (Entitlements/Legal)

**Vấn đề:**
```
spec.template.spec.containers[0].env[4].valueFrom: Invalid value: "": 
may not be specified when `value` is not empty
```

Nhiều patch files cho cùng một deployment gây xung đột khi merge:
- `patch-entitlements.yaml`
- `patch-entitlements-db.yaml`
- `patch-entitlements-redis.yaml`

**Giải pháp:**
Hợp nhất tất cả patches vào một file duy nhất:
- `patch-entitlements-all.yaml` (thay thế 3 files)
- `patch-legal-all.yaml` (thay thế patch-legal-env.yaml)

### 2. Legal Pod - Missing Secret

**Vấn đề:**
```
Error: secret "rook-ceph-object-user-osdu-store-osdu-s3-user" not found
```

**Giải pháp:**
Copy secret từ rook-ceph namespace sang osdu-core:
```bash
kubectl get secret rook-ceph-object-user-osdu-store-osdu-s3-user \
  -n rook-ceph -o yaml | grep -v "namespace:" | \
  kubectl apply -n osdu-core -f -
```

### 3. Storage CrashLoopBackOff - RabbitMQ Retry Mechanism

**Vấn đề:**
```
AppException: RabbitMQ Retry Mechanism has a wrong configuration.
at org.opengroup.osdu.core.oqm.rabbitmq.MqOqmDriver.validateQueueConfiguration
```

Storage Core Plus image có hardcoded RabbitMQ driver với validation rất strict về DLQ/retry configuration.

**Các attempts không thành công:**
1. Cấu hình RabbitMQ với DLX/DLQ - vẫn fail validation
2. Thêm env vars để disable retry - không có hiệu lực
3. Thử nhiều naming conventions khác nhau - vẫn fail

**Giải pháp thành công:**
Chuyển sang sử dụng Kafka/Redpanda thay vì RabbitMQ:

1. **Xóa partition và tạo lại chỉ với Kafka properties:**
```bash
# Delete partition
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s -X DELETE \
  "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "data-partition-id: osdu"

# Recreate với Kafka only
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s -X POST \
  "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "Content-Type: application/json" \
  -d '{
    "properties": {
      "id": {"sensitive": false, "value": "osdu"},
      "oqm.kafka.bootstrap-servers": {"sensitive": false, "value": "osdu-redpanda.osdu-data.svc.cluster.local:9092"},
      "oqm.kafka.partition-count": {"sensitive": false, "value": "1"},
      "oqm.kafka.replication-factor": {"sensitive": false, "value": "1"},
      "oqm.kafka.security.protocol": {"sensitive": false, "value": "PLAINTEXT"}
      // ... other properties
    }
  }'
```

2. **Flush Redis cache:**
```bash
kubectl run redis-flush --rm -it --restart=Never --image=redis:alpine -n osdu-data -- \
  redis-cli -h osdu-redis FLUSHALL
```

3. **Tạo patch cho Storage với OQM_DRIVER=kafka:**
```yaml
# patch-storage-kafka.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: osdu-storage
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: storage
          env:
            - name: OQM_DRIVER
              value: "kafka"
            - name: KAFKA_BOOTSTRAP_SERVERS
              value: "osdu-redpanda.osdu-data.svc.cluster.local:9092"
```

## Cấu hình cuối cùng

### Partition Properties (OQM)
```json
{
  "oqm.kafka.bootstrap-servers": "osdu-redpanda.osdu-data.svc.cluster.local:9092",
  "oqm.kafka.partition-count": "1",
  "oqm.kafka.replication-factor": "1",
  "oqm.kafka.security.protocol": "PLAINTEXT"
}
```

**Lưu ý:** Không còn `oqm.rabbitmq.*` properties.

### Kustomization Structure
```
k8s/osdu/core/overlays/do-private/
├── kustomization.yaml
├── marker-configmap.yaml
├── extra/
│   └── 00-keycloak-internal-dns-alias.yaml
└── patches/
    ├── patch-partition-env.yaml
    ├── patch-entitlements-all.yaml    # Consolidated
    ├── patch-legal-all.yaml           # Consolidated
    ├── patch-storage-kafka.yaml       # NEW - Kafka driver
    └── revision-history/
        ├── patch-partition.yaml
        ├── patch-entitlements.yaml
        ├── patch-storage.yaml
        ├── patch-legal.yaml
        ├── patch-schema.yaml
        ├── patch-file.yaml
        └── patch-toolbox.yaml
```

### Files đã xóa
```
patches/patch-entitlements.yaml         # Replaced by patch-entitlements-all.yaml
patches/patch-entitlements-db.yaml      # Replaced by patch-entitlements-all.yaml
patches/patch-entitlements-redis.yaml   # Replaced by patch-entitlements-all.yaml
patches/patch-legal-env.yaml            # Replaced by patch-legal-all.yaml
patches/patch-storage-openid.yaml       # Replaced by patch-storage-kafka.yaml
```

## Kiểm tra services

### Script test tất cả services
```bash
kubectl -n osdu-core exec deploy/osdu-toolbox -- bash -c '
TOKEN=$(curl -s -X POST "http://keycloak:80/realms/osdu/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=osdu-cli&username=test&password=Test@12345" | \
  grep -o "\"access_token\":\"[^\"]*" | cut -d"\"" -f4)

echo "1. Partition:    $(curl -s -w "%{http_code}" -o /dev/null http://osdu-partition:8080/api/partition/v1/partitions/osdu -H "data-partition-id: osdu")"
echo "2. Entitlements: $(curl -s -w "%{http_code}" -o /dev/null http://osdu-entitlements:8080/api/entitlements/v2/groups -H "data-partition-id: osdu" -H "Authorization: Bearer $TOKEN")"
echo "3. Legal:        $(curl -s -w "%{http_code}" -o /dev/null http://osdu-legal:8080/api/legal/v1/legaltags -H "data-partition-id: osdu" -H "X-Forwarded-Proto: https" -H "Authorization: Bearer $TOKEN")"
echo "4. Schema:       $(curl -s -w "%{http_code}" -o /dev/null http://osdu-schema:8080/api/schema-service/v1/info -H "data-partition-id: osdu" -H "Authorization: Bearer $TOKEN")"
echo "5. File:         $(curl -s -w "%{http_code}" -o /dev/null http://osdu-file:8080/api/file/v2/info -H "data-partition-id: osdu" -H "Authorization: Bearer $TOKEN")"
echo "6. Storage:      $(curl -s -w "%{http_code}" -o /dev/null http://osdu-storage:8080/api/storage/v2/info -H "data-partition-id: osdu" -H "Authorization: Bearer $TOKEN")"
'
```

### Kiểm tra OQM configuration
```bash
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s \
  "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "data-partition-id: osdu" | jq '[to_entries[] | select(.key | startswith("oqm"))]'
```

## Kiến trúc Messaging
```
┌─────────────────────────────────────────────────────┐
│                 OSDU Core Services                   │
│     (Storage, Legal, Indexer, Notification)         │
└─────────────────────┬───────────────────────────────┘
                      │ OQM API
┌─────────────────────▼───────────────────────────────┐
│              OQM Kafka Driver                        │
│              (OQM_DRIVER=kafka)                      │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│                 Redpanda                             │
│     osdu-redpanda.osdu-data.svc.cluster.local:9092  │
│                                                      │
│     - 1 broker (POC)                                │
│     - partition-count: 1                            │
│     - replication-factor: 1                         │
└─────────────────────────────────────────────────────┘
```

## Production Readiness

### Hiện tại (POC/UAT)

| Component | Cấu hình |
|-----------|----------|
| Redpanda nodes | 1 |
| Replication factor | 1 |
| Partitions | 1 |
| Storage | Ephemeral |
| Monitoring | Không có |

### Khuyến nghị Production

| Component | Cấu hình |
|-----------|----------|
| Redpanda nodes | 3+ |
| Replication factor | 3 |
| Partitions | 3-6 per topic |
| Storage | Persistent (DO Volumes) |
| Monitoring | Prometheus + Grafana |
| Security | TLS + SASL/SCRAM |

## Git Commits

| Commit | Message |
|--------|---------|
| `9be3bb0` | Step 19: Initial patches for Redis/Legal |
| `e51ccf1` | Step 19: OSDU Core Services POC complete (5/6) |
| `65d3334` | Cleanup: Remove old patch files |
| `efa7f61` | Step 19 COMPLETE: All 6 OSDU Core Services operational |

## Lessons Learned

1. **Kustomize patch strategy**: Nên hợp nhất tất cả patches cho cùng một resource vào một file duy nhất để tránh merge conflicts.

2. **OSDU Core Plus images**: Có hardcoded messaging driver. Cần kiểm tra image variant trước khi chọn messaging backend.

3. **Partition properties**: Là runtime configuration - thay đổi cần flush cache (Redis) và restart services.

4. **OQM abstraction**: OSDU hỗ trợ multiple messaging backends (Kafka, RabbitMQ, GCP Pub/Sub). Kafka/Redpanda là lựa chọn tốt cho scalability.

5. **Secret management**: Cross-namespace secrets cần được copy manually hoặc sử dụng External Secrets Operator.

## Troubleshooting Commands
```bash
# Check pod logs
kubectl -n osdu-core logs -l app=osdu-storage --tail=50

# Check deployment events
kubectl -n osdu-core describe deploy osdu-storage

# Check partition properties
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s \
  "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "data-partition-id: osdu" | jq .

# Verify Kustomize output
kubectl kustomize k8s/osdu/core/overlays/do-private | kubectl apply --dry-run=client -f -

# Test Redpanda connectivity
kubectl -n osdu-data exec sts/osdu-redpanda -- rpk cluster info
```

## Liên kết

- [Step 17: OSDU Core Scaffold](35-step17-osdu-core.md)
- [Step 18: OSDU Dependencies](36-step18-osdu-deps.md)
- [OSDU M25 Documentation](osdu/30-osdu-poc-core.md)
