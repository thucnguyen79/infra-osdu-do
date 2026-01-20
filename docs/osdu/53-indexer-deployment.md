# Indexer Deployment Checklist

**Project:** OSDU on DigitalOcean Kubernetes  
**Date:** 2026-01-20  
**Status:** ✅ Completed

---

## Phase 1: Pre-deployment Verification

### 1.1 Infrastructure Dependencies
- [x] OpenSearch pod Running (1/1)
- [x] RabbitMQ pod Running (1/1)
- [x] Redis pod Running (1/1)
- [x] PostgreSQL pod Running (1/1)

### 1.2 OSDU Services Dependencies
- [x] Partition service healthy (200 OK)
- [x] Entitlements service healthy (200 OK)
- [x] Storage service healthy (200 OK)
- [x] Schema service healthy (200 OK)
- [x] Search service healthy (200 OK)

---

## Phase 2: RabbitMQ Topology Setup

### 2.1 Exchanges
- [x] `records-changed` exchange exists (type: topic, durable: true)
- [x] `schema-changed` exchange exists (type: topic, durable: true)
- [x] `reprocess` exchange exists (type: topic, durable: true)
- [x] `reindex` exchange exists (type: topic, durable: true) — **Created during deployment**

### 2.2 Queues
- [x] `indexer-records-changed` queue exists
- [x] `indexer-schema-changed` queue exists
- [x] `indexer-reprocess` queue exists — **Created during deployment**
- [x] `indexer-reindex` queue exists — **Created during deployment**

### 2.3 Bindings
- [x] `records-changed` → `indexer-records-changed` (routing_key: #)
- [x] `schema-changed` → `indexer-schema-changed` (routing_key: #)
- [x] `reprocess` → `indexer-reprocess` (routing_key: #) — **Created during deployment**
- [x] `reindex` → `indexer-reindex` (routing_key: #) — **Created during deployment**

### 2.4 Verification Commands
```bash
# Exchanges
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_exchanges name type | grep -E "records|schema|reprocess|reindex"

# Queues
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_queues name messages | grep indexer

# Bindings
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_bindings source_name destination_name | grep -E "reindex|reprocess"
```

---

## Phase 3: Indexer Configuration
# Tài liệu Triển khai OSDU Indexer Service

**Version:** 1.0  
**Date:** 2026-01-20  
**Author:** DevOps Team  
**Status:** ✅ Completed

---

## 1. Tổng quan

### 1.1 Mục đích
Triển khai Indexer service cho OSDU platform trên Kubernetes cluster (DigitalOcean). Indexer chịu trách nhiệm:
- Subscribe các events từ Storage service (qua RabbitMQ)
- Index dữ liệu vào OpenSearch
- Hỗ trợ Search service truy vấn dữ liệu

### 1.2 Data Flow
```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌─────────────┐
│   Storage   │───►│   RabbitMQ   │───►│   Indexer   │───►│ OpenSearch  │
│  (publish)  │    │   (events)   │    │ (subscribe) │    │  (index)    │
└─────────────┘    └──────────────┘    └─────────────┘    └─────────────┘
```

### 1.3 Dependencies
| Dependency | Status | Vai trò |
|------------|--------|---------|
| Storage Service | ✅ Required | Publish events khi record thay đổi |
| OpenSearch | ✅ Required | Lưu trữ search indices |
| RabbitMQ | ✅ Required | Message queue cho events |
| Redis | ✅ Required | Cache cho schema, configuration |
| Partition Service | ✅ Required | Runtime configuration |
| Keycloak | ✅ Required | Authentication/Authorization |

---

## 2. Prerequisites

### 2.1 RabbitMQ Topology
Indexer yêu cầu các exchanges và queues sau:

**Exchanges (type: topic, durable: true):**
| Exchange | Purpose |
|----------|---------|
| `records-changed` | Storage record change events |
| `schema-changed` | Schema change events |
| `reprocess` | Reprocess requests |
| `reindex` | Reindex requests |

**Queues (durable: true):**
| Queue | Bound to Exchange |
|-------|-------------------|
| `indexer-records-changed` | `records-changed` |
| `indexer-schema-changed` | `schema-changed` |
| `indexer-reprocess` | `reprocess` |
| `indexer-reindex` | `reindex` |

### 2.2 Redis Configuration
| Env Variable | Value | Purpose |
|--------------|-------|---------|
| `REDIS_HOST` | `osdu-redis.osdu-data.svc.cluster.local` | General Redis |
| `REDIS_SEARCH_HOST` | `osdu-redis.osdu-data.svc.cluster.local` | Search cache |
| `REDIS_CACHE_HOST` | `osdu-redis.osdu-data.svc.cluster.local` | Application cache |
| `SPRING_DATA_REDIS_HOST` | `osdu-redis.osdu-data.svc.cluster.local` | Spring Boot Redis |

---

## 3. Các Lỗi Phát Sinh và Cách Fix

### 3.1 Lỗi #1: Exchange `reindex` không tồn tại

**Triệu chứng:**
```
HTTP GET http://osdu-rabbitmq.osdu-data.svc.cluster.local:15672/api/exchanges/%2F/reindex
Response 404 NOT_FOUND
```

**Nguyên nhân:**
- RabbitMQ chưa có exchange `reindex`
- Indexer cần 4 exchanges nhưng chỉ có 3

**Cách fix:**
```bash
# Tạo exchange reindex qua HTTP API (từ toolbox)
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s -u osdu:osdu123 -X PUT \
  -H "Content-Type: application/json" \
  -d '{"type":"topic","durable":true}' \
  "http://osdu-rabbitmq.osdu-data:15672/api/exchanges/%2F/reindex"
```

**Verify:**
```bash
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_exchanges name type | grep reindex
# Expected: reindex topic
```

---

### 3.2 Lỗi #2: Queue `indexer-reprocess` không tồn tại

**Triệu chứng:**
```
NOT_FOUND - no queue 'indexer-reprocess' in vhost ''
```

**Nguyên nhân:**
- Queue chưa được tạo
- Binding từ exchange chưa có

**Cách fix:**
```bash
# Tạo queue qua rabbitmqctl
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl eval '
rabbit_amqqueue:declare(
  rabbit_misc:r(<<"/">>, queue, <<"indexer-reprocess">>),
  true, false, [], none, <<"guest">>
).
'

# Tạo binding qua HTTP API
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s -u osdu:osdu123 -X POST \
  -H "Content-Type: application/json" \
  -d '{"routing_key":"#"}' \
  "http://osdu-rabbitmq.osdu-data:15672/api/bindings/%2F/e/reprocess/q/indexer-reprocess"
```

---

### 3.3 Lỗi #3: Spring 6.x Incompatibility với OQM RabbitMQ Plugin

**Triệu chứng:**
```java
NoSuchMethodError: 'org.springframework.http.HttpStatus 
  org.springframework.web.client.HttpClientErrorException.getStatusCode()'
```

**Nguyên nhân:**
- Indexer image dùng Spring Boot 3.3.7 (Spring 6.x)
- OQM RabbitMQ plugin được build với Spring 5.x
- Method `getStatusCode()` trả về `HttpStatusCode` trong Spring 6.x thay vì `HttpStatus`

**Cách fix:**
- **Option C (Recommended):** Tạo đầy đủ RabbitMQ topology trước khi start Indexer
- Khi tất cả exchanges/queues/bindings tồn tại → không có 404 → không trigger lỗi

**Lưu ý:** Đây là workaround, không phải fix gốc. Fix gốc cần rebuild OQM plugin cho Spring 6.x.

---

### 3.4 Lỗi #4: Redis Host không tìm thấy

**Triệu chứng:**
```
java.net.UnknownHostException: redis-cache-search: Name or service not known
Unable to connect to redis-cache-search/<unresolved>:6379
```

**Nguyên nhân:**
- Indexer hardcode tìm hostname `redis-cache-search`
- Thực tế Redis service là `osdu-redis`
- Thiếu env var `REDIS_SEARCH_HOST`

**Cách fix:**
```bash
# Thêm REDIS_SEARCH_HOST (giống Search service)
kubectl -n osdu-core set env deploy/osdu-indexer \
  REDIS_SEARCH_HOST=osdu-redis.osdu-data.svc.cluster.local \
  REDIS_SEARCH_PORT=6379
```

**So sánh với Search service (working):**
```
# Search service có:
REDIS_SEARCH_HOST=osdu-redis.osdu-data.svc.cluster.local
REDIS_SEARCH_PORT=6379

# Indexer ban đầu thiếu → fallback to default "redis-cache-search"
```

---

### 3.5 Lỗi #5: Erlang syntax error khi dùng rabbitmqctl eval

**Triệu chứng:**
```
Error: {:undef, [{:rabbit_exchange, :declare, ...}]}
Error: {{:undefined_record, :binding}, ...}
```

**Nguyên nhân:**
- RabbitMQ container dùng Erlang syntax khác
- Không thể dùng record syntax trực tiếp

**Cách fix:**
- Dùng HTTP Management API thay vì rabbitmqctl eval
- Gọi từ toolbox (có curl) thay vì RabbitMQ container

```bash
# ĐÚNG: Dùng HTTP API từ toolbox
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s -u osdu:osdu123 -X PUT \
  -H "Content-Type: application/json" \
  -d '{"type":"topic","durable":true}' \
  "http://osdu-rabbitmq.osdu-data:15672/api/exchanges/%2F/reindex"

# SAI: Dùng rabbitmqctl eval với Erlang syntax
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl eval '...'
```

---

## 4. Các bước Triển khai (Repo-first)

### 4.1 Chuẩn bị RabbitMQ Topology

```bash
# 1. Tạo exchange reindex
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s -u osdu:osdu123 -X PUT \
  -H "Content-Type: application/json" \
  -d '{"type":"topic","durable":true}' \
  "http://osdu-rabbitmq.osdu-data:15672/api/exchanges/%2F/reindex"

# 2. Tạo tất cả queues cần thiết
for queue in indexer-records-changed indexer-schema-changed indexer-reprocess indexer-reindex; do
  kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl eval "
    rabbit_amqqueue:declare(
      rabbit_misc:r(<<\"/\">>, queue, <<\"$queue\">>),
      true, false, [], none, <<\"guest\">>
    ).
  "
done

# 3. Tạo bindings
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s -u osdu:osdu123 -X POST \
  -H "Content-Type: application/json" -d '{"routing_key":"#"}' \
  "http://osdu-rabbitmq.osdu-data:15672/api/bindings/%2F/e/reindex/q/indexer-reindex"

kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s -u osdu:osdu123 -X POST \
  -H "Content-Type: application/json" -d '{"routing_key":"#"}' \
  "http://osdu-rabbitmq.osdu-data:15672/api/bindings/%2F/e/reprocess/q/indexer-reprocess"

# 4. Verify
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_exchanges name type | grep -E "records|schema|reprocess|reindex"
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_bindings source_name destination_name | grep -E "reindex|reprocess"
```

### 4.2 Cập nhật Indexer Deployment YAML

File: `k8s/osdu/core/base/services/indexer/indexer-deploy.yaml`

```yaml
spec:
  template:
    spec:
      containers:
      - name: osdu-indexer
        env:
        # Redis Configuration (CRITICAL)
        - name: REDIS_HOST
          value: "osdu-redis.osdu-data.svc.cluster.local"
        - name: REDIS_PORT
          value: "6379"
        - name: REDIS_SEARCH_HOST
          value: "osdu-redis.osdu-data.svc.cluster.local"
        - name: REDIS_SEARCH_PORT
          value: "6379"
        - name: REDIS_CACHE_HOST
          value: "osdu-redis.osdu-data.svc.cluster.local"
        - name: SPRING_REDIS_HOST
          value: "osdu-redis.osdu-data.svc.cluster.local"
        - name: SPRING_DATA_REDIS_HOST
          value: "osdu-redis.osdu-data.svc.cluster.local"
        - name: SPRING_DATA_REDIS_PORT
          value: "6379"
        
        # RabbitMQ Configuration
        - name: RABBITMQ_HOST
          value: "osdu-rabbitmq.osdu-data.svc.cluster.local"
        - name: RABBITMQ_PORT
          value: "5672"
        
        # Other env vars...
```

### 4.3 Export RabbitMQ Definitions (Repo-first)

```bash
# Export definitions
mkdir -p k8s/osdu/deps/base/rabbitmq
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s -u osdu:osdu123 \
  "http://osdu-rabbitmq.osdu-data:15672/api/definitions" > k8s/osdu/deps/base/rabbitmq/definitions.json

# Commit
git add k8s/osdu/deps/base/rabbitmq/definitions.json
git commit -m "Export RabbitMQ definitions for Indexer"
git push
```

### 4.4 Deploy Indexer

```bash
# Apply via ArgoCD hoặc kubectl
kubectl -n argocd patch app osdu-core --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Hoặc manual apply
kubectl apply -k k8s/osdu/core/overlays/do-private/

# Verify
kubectl -n osdu-core get pods -l app=osdu-indexer
kubectl -n osdu-core logs deploy/osdu-indexer --tail=50
```

---

## 5. Checklist Triển khai

### 5.1 Pre-deployment Checklist

| # | Task | Command | Expected |
|---|------|---------|----------|
| 1 | OpenSearch healthy | `kubectl -n osdu-data get pods -l app=osdu-opensearch` | `1/1 Running` |
| 2 | RabbitMQ healthy | `kubectl -n osdu-data get pods -l app=osdu-rabbitmq` | `1/1 Running` |
| 3 | Redis healthy | `kubectl -n osdu-data get pods -l app=osdu-redis` | `1/1 Running` |
| 4 | Storage service running | `kubectl -n osdu-core get pods -l app=osdu-storage` | `1/1 Running` |
| 5 | Search service running | `kubectl -n osdu-core get pods -l app=osdu-search` | `1/1 Running` |

### 5.2 RabbitMQ Topology Checklist

| # | Task | Command | Expected |
|---|------|---------|----------|
| 1 | Exchange records-changed exists | `rabbitmqctl list_exchanges \| grep records-changed` | `records-changed topic` |
| 2 | Exchange schema-changed exists | `rabbitmqctl list_exchanges \| grep schema-changed` | `schema-changed topic` |
| 3 | Exchange reprocess exists | `rabbitmqctl list_exchanges \| grep reprocess` | `reprocess topic` |
| 4 | Exchange reindex exists | `rabbitmqctl list_exchanges \| grep reindex` | `reindex topic` |
| 5 | Queue indexer-records-changed | `rabbitmqctl list_queues \| grep indexer-records` | `indexer-records-changed 0` |
| 6 | Queue indexer-schema-changed | `rabbitmqctl list_queues \| grep indexer-schema` | `indexer-schema-changed 0` |
| 7 | Queue indexer-reprocess | `rabbitmqctl list_queues \| grep indexer-reprocess` | `indexer-reprocess 0` |
| 8 | Queue indexer-reindex | `rabbitmqctl list_queues \| grep indexer-reindex` | `indexer-reindex 0` |
| 9 | Binding reindex→queue | `rabbitmqctl list_bindings \| grep reindex` | `reindex indexer-reindex` |
| 10 | Binding reprocess→queue | `rabbitmqctl list_bindings \| grep reprocess` | `reprocess indexer-reprocess` |

### 5.3 Indexer Deployment Checklist

| # | Task | Command | Expected |
|---|------|---------|----------|
| 1 | Indexer pod running | `kubectl -n osdu-core get pods -l app=osdu-indexer` | `1/1 Running` |
| 2 | No CrashLoopBackOff | Check RESTARTS column | `0` or low number |
| 3 | Startup success log | `kubectl logs deploy/osdu-indexer \| grep Started` | `Started IndexerCorePlusApplication` |
| 4 | Subscribers registered | `kubectl logs deploy/osdu-indexer \| grep REGISTERED` | 4x `REGISTERED` messages |
| 5 | No Redis errors | `kubectl logs deploy/osdu-indexer \| grep -i redis` | No `UnknownHostException` |
| 6 | No RabbitMQ 404 | `kubectl logs deploy/osdu-indexer \| grep "404"` | No results |

### 5.4 Post-deployment Verification

| # | Task | Command | Expected |
|---|------|---------|----------|
| 1 | Health endpoint | `curl http://osdu-indexer:8080/actuator/health` | `{"status":"UP"}` |
| 2 | Info endpoint | `curl http://osdu-indexer:8080/api/indexer/v2/info` | Version info JSON |
| 3 | Consumers listening | Check logs for "Listening for messages" | 4 subscriptions active |

---

## 6. Repo-first Compliance

### 6.1 Items có thể Repo-first

| Item | File/Location | Notes |
|------|---------------|-------|
| Indexer Deployment | `k8s/osdu/core/base/services/indexer/indexer-deploy.yaml` | Env vars, image, resources |
| RabbitMQ Definitions | `k8s/osdu/deps/base/rabbitmq/definitions.json` | Exchanges, queues, bindings |
| ConfigMaps | `k8s/osdu/core/base/configmaps/` | osdu-core-env |
| Kustomize overlays | `k8s/osdu/core/overlays/do-private/` | Environment-specific patches |

### 6.2 Items KHÔNG thể Repo-first

| Item | Reason | Workaround |
|------|--------|------------|
| Partition Properties | Stored in PostgreSQL | Document trong `docs/runtime-config/` |
| Secrets | Sensitive data | Lưu trong `artifacts-private/` (gitignored) |
| Runtime tokens | Generated at runtime | N/A |

### 6.3 Cách xử lý Partition Properties

```bash
# Export (masked sensitive data)
kubectl -n osdu-core exec deploy/osdu-toolbox -- bash -c '
PGPASSWORD=osdu psql -h osdu-postgres.osdu-data -U osdu -d partition -t -c "
SELECT key, 
  CASE WHEN key LIKE '\''%password%'\'' OR key LIKE '\''%secret%'\'' 
    THEN '\''***MASKED***'\'' 
    ELSE value 
  END as value
FROM partition_properties WHERE partition_id = '\''osdu'\''
ORDER BY key;
"' > docs/runtime-config/osdu-partition-properties.txt

# Lưu payload để recreate
cat > docs/runtime-config/osdu-partition-payload.json << 'EOF'
{
  "properties": {
    "elasticsearch.8.protocol": {"sensitive": false, "value": "http"},
    "elasticsearch.8.host": {"sensitive": false, "value": "osdu-opensearch.osdu-data.svc.cluster.local"},
    ...
  }
}
EOF
```

---

## 7. Troubleshooting Guide

### 7.1 Indexer không start được

**Check:**
1. RabbitMQ topology đầy đủ chưa?
2. Redis env vars đúng chưa?
3. OpenSearch accessible không?

**Commands:**
```bash
# Full logs
kubectl -n osdu-core logs deploy/osdu-indexer --tail=200

# Describe pod
kubectl -n osdu-core describe pod -l app=osdu-indexer

# Events
kubectl -n osdu-core get events --sort-by='.lastTimestamp' | grep indexer
```

### 7.2 Indexer crash sau khi start

**Check:**
1. Memory/CPU limits đủ chưa?
2. Có lỗi OOM không?
3. Dependency services healthy không?

**Commands:**
```bash
# Resource usage
kubectl -n osdu-core top pod -l app=osdu-indexer

# Previous container logs
kubectl -n osdu-core logs deploy/osdu-indexer --previous
```

### 7.3 Messages không được consume

**Check:**
1. Bindings đúng chưa?
2. Consumer connected chưa?
3. Queue có messages không?

**Commands:**
```bash
# Check queue status
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_queues name messages consumers

# Check connections
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_connections
```

---

## 8. Appendix

### 8.1 Full Indexer env vars

```yaml
env:
  # Application
  - name: SPRING_PROFILES_ACTIVE
    value: "default"
  - name: SERVER_PORT
    value: "8080"
  
  # Redis
  - name: REDIS_HOST
    value: "osdu-redis.osdu-data.svc.cluster.local"
  - name: REDIS_PORT
    value: "6379"
  - name: REDIS_SEARCH_HOST
    value: "osdu-redis.osdu-data.svc.cluster.local"
  - name: REDIS_SEARCH_PORT
    value: "6379"
  - name: REDIS_CACHE_HOST
    value: "osdu-redis.osdu-data.svc.cluster.local"
  - name: SPRING_REDIS_HOST
    value: "osdu-redis.osdu-data.svc.cluster.local"
  - name: SPRING_DATA_REDIS_HOST
    value: "osdu-redis.osdu-data.svc.cluster.local"
  - name: SPRING_DATA_REDIS_PORT
    value: "6379"
  
  # OpenSearch
  - name: ELASTIC_HOST
    value: "osdu-opensearch.osdu-data.svc.cluster.local"
  - name: ELASTIC_PORT
    value: "9200"
  - name: ELASTIC_SCHEME
    value: "http"
  
  # RabbitMQ
  - name: RABBITMQ_HOST
    value: "osdu-rabbitmq.osdu-data.svc.cluster.local"
  - name: RABBITMQ_PORT
    value: "5672"
  
  # Services
  - name: PARTITION_API
    value: "http://osdu-partition:8080/api/partition/v1"
  - name: ENTITLEMENTS_API
    value: "http://osdu-entitlements:8080/api/entitlements/v2"
  - name: STORAGE_API
    value: "http://osdu-storage:8080/api/storage/v2"
  - name: SCHEMA_API
    value: "http://osdu-schema:8080/api/schema-service/v1"
```

### 8.2 RabbitMQ definitions.json structure

```json
{
  "rabbit_version": "3.x.x",
  "exchanges": [
    {"name": "records-changed", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false},
    {"name": "schema-changed", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false},
    {"name": "reprocess", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false},
    {"name": "reindex", "vhost": "/", "type": "topic", "durable": true, "auto_delete": false}
  ],
  "queues": [
    {"name": "indexer-records-changed", "vhost": "/", "durable": true, "auto_delete": false},
    {"name": "indexer-schema-changed", "vhost": "/", "durable": true, "auto_delete": false},
    {"name": "indexer-reprocess", "vhost": "/", "durable": true, "auto_delete": false},
    {"name": "indexer-reindex", "vhost": "/", "durable": true, "auto_delete": false}
  ],
  "bindings": [
    {"source": "records-changed", "vhost": "/", "destination": "indexer-records-changed", "destination_type": "queue", "routing_key": "#"},
    {"source": "schema-changed", "vhost": "/", "destination": "indexer-schema-changed", "destination_type": "queue", "routing_key": "#"},
    {"source": "reprocess", "vhost": "/", "destination": "indexer-reprocess", "destination_type": "queue", "routing_key": "#"},
    {"source": "reindex", "vhost": "/", "destination": "indexer-reindex", "destination_type": "queue", "routing_key": "#"}
  ]
}
```

---

## 9. Change Log

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2026-01-20 | 1.0 | DevOps Team | Initial deployment, fixed RabbitMQ topology, fixed Redis config |

### 3.1 Redis Environment Variables
- [x] `REDIS_HOST` = `osdu-redis.osdu-data.svc.cluster.local`
- [x] `REDIS_PORT` = `6379`
- [x] `REDIS_SEARCH_HOST` = `osdu-redis.osdu-data.svc.cluster.local` — **Critical fix**
- [x] `REDIS_SEARCH_PORT` = `6379` — **Critical fix**
- [x] `REDIS_CACHE_HOST` = `osdu-redis.osdu-data.svc.cluster.local`
- [x] `SPRING_REDIS_HOST` = `osdu-redis.osdu-data.svc.cluster.local`
- [x] `SPRING_DATA_REDIS_HOST` = `osdu-redis.osdu-data.svc.cluster.local`
- [x] `SPRING_DATA_REDIS_PORT` = `6379`

### 3.2 Other Critical Env Vars
- [x] `ELASTIC_HOST` configured
- [x] `ELASTIC_PORT` = `9200`
- [x] `ELASTIC_SCHEME` = `http`
- [x] `PARTITION_API` configured
- [x] `ENTITLEMENTS_API` configured
- [x] `STORAGE_API` configured
- [x] `SCHEMA_API` configured

---

## Phase 4: Deployment

### 4.1 Deploy Indexer
- [x] ArgoCD sync or kubectl apply
- [x] Pod created successfully
- [x] Pod status: Running
- [x] Ready: 1/1

### 4.2 Startup Logs Verification
- [x] `Started IndexerCorePlusApplication` in logs
- [x] No `UnknownHostException` errors
- [x] No `404 NOT_FOUND` errors
- [x] 4x `Subscriber REGISTERED` messages

---

## Phase 5: Post-deployment Verification

### 5.1 Health Checks
- [x] Indexer pod Running 1/1
- [x] No restarts (or minimal)
- [x] Health endpoint responds

### 5.2 Functional Verification
- [x] Consumers listening on all 4 queues
- [x] Can receive messages from RabbitMQ
- [x] Can connect to OpenSearch
- [x] Can connect to Redis

---

## Phase 6: Repo-first Compliance

### 6.1 Update Repository
- [ ] Update `indexer-deploy.yaml` with Redis env vars
- [ ] Export RabbitMQ definitions to `definitions.json`
- [ ] Commit and push changes
- [ ] ArgoCD synced with repo

### 6.2 Documentation
- [ ] Deployment document created
- [ ] Checklist completed
- [ ] Issues documented
- [ ] Runtime config documented

---

## Issues Encountered & Resolutions

### Issue #1: Exchange `reindex` missing
| Field | Value |
|-------|-------|
| Symptom | `404 NOT_FOUND` for `/api/exchanges/%2F/reindex` |
| Root Cause | Exchange not created in RabbitMQ |
| Resolution | Created via HTTP API |
| Command | `curl -X PUT ... "http://osdu-rabbitmq:15672/api/exchanges/%2F/reindex"` |

### Issue #2: Queue `indexer-reprocess` missing
| Field | Value |
|-------|-------|
| Symptom | `NOT_FOUND - no queue 'indexer-reprocess'` |
| Root Cause | Queue not created, binding missing |
| Resolution | Created queue via rabbitmqctl, binding via HTTP API |

### Issue #3: Redis host `redis-cache-search` not found
| Field | Value |
|-------|-------|
| Symptom | `UnknownHostException: redis-cache-search` |
| Root Cause | Missing `REDIS_SEARCH_HOST` env var |
| Resolution | Added `REDIS_SEARCH_HOST=osdu-redis.osdu-data.svc.cluster.local` |

### Issue #4: Spring 6.x incompatibility with OQM plugin
| Field | Value |
|-------|-------|
| Symptom | `NoSuchMethodError: getStatusCode()` |
| Root Cause | OQM plugin built with Spring 5.x, Indexer uses Spring 6.x |
| Resolution | Workaround: Create all RabbitMQ topology before startup to avoid 404 |

### Issue #5: Erlang syntax error in rabbitmqctl eval
| Field | Value |
|-------|-------|
| Symptom | `{:undef, [{:rabbit_exchange, :declare, ...}]}` |
| Root Cause | Different Erlang syntax required |
| Resolution | Use HTTP Management API instead of rabbitmqctl eval |

---

## Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Deployer | DevOps Team | 2026-01-20 | ✅ |
| Reviewer | | | |
| Approver | | | |

---

## Notes

1. **CRITICAL**: Always create RabbitMQ topology BEFORE starting Indexer to avoid Spring 6.x incompatibility issue
2. **CRITICAL**: `REDIS_SEARCH_HOST` is required - Indexer uses different env var than expected
3. RabbitMQ definitions should be exported and stored in repo for reproducibility
4. Consider upgrading OQM plugin to Spring 6.x compatible version in future
