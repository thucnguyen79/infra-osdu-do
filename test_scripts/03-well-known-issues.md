# OSDU Well-Known Issues & Troubleshooting Guide

## Mục lục
1. [Search Service Issues](#1-search-service-issues)
2. [Indexer Service Issues](#2-indexer-service-issues)
3. [Storage Service Issues](#3-storage-service-issues)
4. [Authentication/Authorization Issues](#4-authenticationauthorization-issues)
5. [RabbitMQ Issues](#5-rabbitmq-issues)
6. [OpenSearch Issues](#6-opensearch-issues)
7. [Redis Cache Issues](#7-redis-cache-issues)
8. [Partition Configuration Issues](#8-partition-configuration-issues)
9. [General Debugging Commands](#9-general-debugging-commands)

---

## 1. Search Service Issues

### 1.1 SSL/TLS Mismatch với OpenSearch

**Triệu chứng:**
```
javax.net.ssl.SSLException: Received fatal alert: protocol_version
ConnectException: Connection refused (Connection refused)
```

**Nguyên nhân:**
Search service mặc định kết nối OpenSearch qua HTTPS, nhưng OpenSearch chạy HTTP.

**Giải pháp:**

1. **Thêm partition properties:**
```bash
# Thêm các properties sau vào partition
elasticsearch.8.protocol = http
elasticsearch.8.scheme = http
elasticsearch.8.ssl.enabled = false
```

2. **Thêm env vars vào Search deployment:**
```yaml
- name: ELASTIC_SCHEME
  value: "http"
- name: ELASTICSEARCH_HTTPS_ENABLED
  value: "false"
- name: OPENSEARCH_SECURITY_DISABLED
  value: "true"
```

3. **Quan trọng: Flush Redis cache sau khi thay đổi:**
```bash
kubectl run redis-flush --rm -it --restart=Never --image=redis:alpine -n osdu-data \
  -- redis-cli -h osdu-redis FLUSHALL
```

4. **Restart Search pod:**
```bash
kubectl -n osdu-core rollout restart deploy/osdu-search
```

---

### 1.2 Search Returns Empty Results

**Triệu chứng:**
- API trả về `{"totalCount":0,"results":[]}`
- Record đã tạo nhưng không tìm thấy

**Nguyên nhân:**
- Indexer chưa xử lý record
- Record chưa được index vào OpenSearch
- Query sai format

**Giải pháp:**

1. **Kiểm tra Indexer logs:**
```bash
kubectl -n osdu-core logs deploy/osdu-indexer --tail=100 | grep -i "record\|index\|error"
```

2. **Kiểm tra trực tiếp OpenSearch:**
```bash
kubectl -n osdu-core exec deploy/osdu-toolbox -- \
  curl -s "http://osdu-opensearch.osdu-data:9200/_cat/indices?v"

# Search trực tiếp trong OpenSearch
kubectl -n osdu-core exec deploy/osdu-toolbox -- \
  curl -s "http://osdu-opensearch.osdu-data:9200/_search?q=*&size=5"
```

3. **Chờ indexing (thường 10-30 giây):**
```bash
sleep 30
# Thử search lại
```

---

## 2. Indexer Service Issues

### 2.1 RabbitMQ VHost Not Found (404)

**Triệu chứng:**
```
NOT_FOUND - no queue 'xxx' in vhost '/'
404 NOT_FOUND for exchange/queue
```

**Nguyên nhân:**
OQM RabbitMQ plugin có bug, luôn kết nối vào vhost rỗng "" thay vì vhost được cấu hình.

**Giải pháp:**

1. **Tạo topology trong vhost rỗng:**
```bash
RABBITMQ_POD=$(kubectl -n osdu-data get pods -l app=osdu-rabbitmq -o jsonpath='{.items[0].metadata.name}')

# Tạo exchanges
for ex in records-changed schema-changed legaltags-changed reprocess reindex; do
  kubectl -n osdu-data exec $RABBITMQ_POD -- \
    rabbitmqctl eval "rabbit_exchange:declare(rabbit_misc:r(<<\"/\">>, exchange, <<\"$ex\">>), topic, true, false, false, [])."
done

# Tạo queues
for q in indexer-records-changed indexer-schema-changed indexer-legaltags-changed indexer-reprocess indexer-reindex; do
  kubectl -n osdu-data exec $RABBITMQ_POD -- \
    rabbitmqctl eval "rabbit_amqqueue:declare(rabbit_misc:r(<<\"/\">>, queue, <<\"$q\">>), true, false, [], none, <<\"guest\">>)."
done
```

2. **Thêm nhiều VHOST env vars vào Indexer (workaround):**
```yaml
- name: OQM_RABBITMQ_AMQP_VHOST
  value: ""
- name: SPRING_RABBITMQ_VIRTUAL_HOST
  value: ""
- name: OQM_SPRING_RABBITMQ_VHOST
  value: ""
# ... thêm nhiều variants
```

---

### 2.2 Redis Host Not Found

**Triệu chứng:**
```
UnknownHostException: redis-cache-search: Name or service not known
```

**Nguyên nhân:**
Indexer tìm host `redis-cache-search` nhưng service tên `osdu-redis`.

**Giải pháp:**

Thêm env var vào Indexer deployment:
```yaml
- name: REDIS_SEARCH_HOST
  value: "osdu-redis.osdu-data.svc.cluster.local"
- name: REDIS_HOST
  value: "osdu-redis.osdu-data.svc.cluster.local"
```

---

### 2.3 Spring 6.x Incompatibility (OQM Plugin)

**Triệu chứng:**
```
NoSuchMethodError: 'org.springframework.http.HttpStatus 
  org.springframework.web.client.HttpClientErrorException.getStatusCode()'
```

**Nguyên nhân:**
OQM RabbitMQ plugin được build với Spring 5.x, nhưng Indexer image mới dùng Spring 6.x.

**Giải pháp:**
- Sử dụng image version cũ hơn của Indexer
- Hoặc chờ OQM plugin update
- Workaround: Scale indexer về 0 nếu không cần indexing

---

## 3. Storage Service Issues

### 3.1 Missing RabbitMQ Properties

**Triệu chứng:**
```
Missing property: oqm.rabbitmq.amqp.host
CrashLoopBackOff
```

**Nguyên nhân:**
Partition properties cho RabbitMQ chưa được seed.

**Giải pháp:**

```bash
TOKEN=$(get_access_token)

curl -X PATCH "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "Authorization: Bearer $TOKEN" \
  -H "data-partition-id: osdu" \
  -H "Content-Type: application/json" \
  -d '{
    "properties": {
      "oqm.rabbitmq.amqp.host": {"value": "osdu-rabbitmq.osdu-data"},
      "oqm.rabbitmq.amqp.port": {"value": "5672"},
      "oqm.rabbitmq.amqp.username": {"value": "osdu"},
      "oqm.rabbitmq.amqp.password": {"value": "osdu123", "sensitive": true},
      "oqm.rabbitmq.admin.host": {"value": "osdu-rabbitmq.osdu-data"},
      "oqm.rabbitmq.admin.port": {"value": "15672"},
      "oqm.rabbitmq.admin.schema": {"value": "http"},
      "oqm.rabbitmq.exchanges.recordsChangedTopic.name": {"value": "records-changed"},
      "oqm.rabbitmq.exchanges.schemaChangedTopic.name": {"value": "schema-changed"},
      "oqm.rabbitmq.exchanges.legalTagsChangedTopic.name": {"value": "legaltags-changed"},
      "oqm.rabbitmq.exchanges.recordsChangedTopicV2.name": {"value": "records-changed-v2"}
    }
  }'
```

---

### 3.2 S3/OBM Connection Failed

**Triệu chứng:**
```
S3Exception: Access Denied
Unable to connect to S3 endpoint
```

**Giải pháp:**

1. **Kiểm tra S3 credentials:**
```bash
kubectl -n rook-ceph get secret rook-ceph-object-user-osdu-store-osdu-s3-user -o jsonpath='{.data.AccessKey}' | base64 -d
```

2. **Verify partition properties:**
```bash
# Đảm bảo có các properties:
# obm.minio.endpoint = http://rook-ceph-rgw-osdu-store.rook-ceph:80
# obm.minio.accessKey = <access_key>
# obm.minio.secretKey = <secret_key>
```

3. **Test S3 connectivity:**
```bash
kubectl -n osdu-core exec deploy/osdu-toolbox -- \
  curl -s "http://rook-ceph-rgw-osdu-store.rook-ceph:80"
```

---

## 4. Authentication/Authorization Issues

### 4.1 Token Acquisition Failed

**Triệu chứng:**
```
{"error":"invalid_grant","error_description":"Invalid user credentials"}
```

**Giải pháp:**

1. **Kiểm tra user trong Keycloak:**
```bash
# Access Keycloak admin console
kubectl -n osdu-identity port-forward svc/keycloak 8080:80

# Verify user: test / Test@12345
# Ensure directAccessGrantsEnabled = true for osdu-cli client
```

2. **Tạo/fix user:**
```bash
# Trong Keycloak Admin Console:
# Users > Add user > Username: test
# Credentials > Set password: Test@12345 (Temporary: OFF)
```

---

### 4.2 403 Forbidden - Entitlements

**Triệu chứng:**
```
403 Forbidden
User not authorized
```

**Nguyên nhân:**
User chưa được add vào required groups.

**Giải pháp:**

```bash
TOKEN=$(get_access_token)

# Add user to groups
GROUPS=("users" "data.default.owners" "data.default.viewers")
for grp in "${GROUPS[@]}"; do
  curl -X POST "http://osdu-entitlements:8080/api/entitlements/v2/groups/$grp@osdu.osdu.local/members" \
    -H "Authorization: Bearer $TOKEN" \
    -H "data-partition-id: osdu" \
    -H "Content-Type: application/json" \
    -d '{"email":"test@osdu.osdu.local","role":"MEMBER"}'
done
```

---

## 5. RabbitMQ Issues

### 5.1 Queues/Exchanges Missing

**Triệu chứng:**
```
NOT_FOUND - no exchange 'records-changed' in vhost '/'
```

**Giải pháp:**

Export và import definitions:
```bash
# Export current definitions
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- \
  rabbitmqctl export_definitions /tmp/definitions.json

# View definitions
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- cat /tmp/definitions.json

# Import definitions (nếu cần restore)
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- \
  rabbitmqctl import_definitions /tmp/definitions.json
```

---

### 5.2 Connection Refused to RabbitMQ

**Giải pháp:**

```bash
# Check RabbitMQ status
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl status

# Check listeners
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl listeners

# Check connections
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_connections
```

---

## 6. OpenSearch Issues

### 6.1 Cluster Yellow/Red Status

**Triệu chứng:**
```
"status":"yellow" or "status":"red"
```

**Giải pháp:**

```bash
# Check cluster health
kubectl -n osdu-core exec deploy/osdu-toolbox -- \
  curl -s "http://osdu-opensearch.osdu-data:9200/_cluster/health?pretty"

# Check unassigned shards
kubectl -n osdu-core exec deploy/osdu-toolbox -- \
  curl -s "http://osdu-opensearch.osdu-data:9200/_cat/shards?v&h=index,shard,prirep,state,unassigned.reason"

# Yellow with single node is NORMAL (no replicas)
```

---

### 6.2 Index Not Created

**Giải pháp:**

```bash
# List all indices
kubectl -n osdu-core exec deploy/osdu-toolbox -- \
  curl -s "http://osdu-opensearch.osdu-data:9200/_cat/indices?v"

# Check index template
kubectl -n osdu-core exec deploy/osdu-toolbox -- \
  curl -s "http://osdu-opensearch.osdu-data:9200/_index_template"
```

---

## 7. Redis Cache Issues

### 7.1 Stale Cache Data

**Triệu chứng:**
- Thay đổi config nhưng service vẫn dùng config cũ
- Partition properties không được update

**Giải pháp:**

```bash
# Flush all Redis cache
kubectl run redis-flush-$(date +%s) --rm -it --restart=Never \
  --image=redis:alpine -n osdu-data \
  -- redis-cli -h osdu-redis FLUSHALL

# Or flush specific database
kubectl run redis-flush --rm -it --restart=Never \
  --image=redis:alpine -n osdu-data \
  -- redis-cli -h osdu-redis -n 4 FLUSHDB
```

---

## 8. Partition Configuration Issues

### 8.1 Missing Partition Properties

**Kiểm tra:**
```bash
TOKEN=$(get_access_token)

# Get all properties
kubectl -n osdu-core exec deploy/osdu-toolbox -- \
  curl -s "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "Authorization: Bearer $TOKEN" \
  -H "data-partition-id: osdu" | jq .
```

**Required Properties Checklist:**
- [ ] `elasticsearch.host`
- [ ] `elasticsearch.port`
- [ ] `elasticsearch.8.host`
- [ ] `elasticsearch.8.protocol` = http
- [ ] `elasticsearch.8.ssl.enabled` = false
- [ ] `redis-host`
- [ ] `redis-port`
- [ ] `oqm.rabbitmq.amqp.host`
- [ ] `oqm.rabbitmq.amqp.port`
- [ ] `obm.minio.endpoint`
- [ ] `obm.minio.accessKey`
- [ ] `obm.minio.secretKey`
- [ ] All datasource URLs for services

---

## 9. General Debugging Commands

### 9.1 Pod Status & Logs

```bash
# All OSDU pods
kubectl -n osdu-core get pods -o wide

# Specific service logs
kubectl -n osdu-core logs deploy/osdu-<service> --tail=100

# Previous container logs (if crashed)
kubectl -n osdu-core logs deploy/osdu-<service> --previous

# Follow logs
kubectl -n osdu-core logs -f deploy/osdu-<service>
```

### 9.2 Service Connectivity from Toolbox

```bash
TOOLBOX="kubectl -n osdu-core exec deploy/osdu-toolbox --"

# DNS check
$TOOLBOX nslookup osdu-storage.osdu-core.svc.cluster.local

# HTTP check
$TOOLBOX curl -v http://osdu-storage:8080/api/storage/v2/info

# TCP check
$TOOLBOX nc -zv osdu-postgres.osdu-data 5432
```

### 9.3 Events & Describe

```bash
# Recent events
kubectl -n osdu-core get events --sort-by='.lastTimestamp' | tail -20

# Describe pod for details
kubectl -n osdu-core describe pod <pod-name>

# Describe deployment
kubectl -n osdu-core describe deploy/osdu-<service>
```

### 9.4 Resource Usage

```bash
# Pod resource usage
kubectl -n osdu-core top pods

# Node resource usage
kubectl top nodes
```

---

## Quick Reference Card

| Issue | First Check | Quick Fix |
|-------|-------------|-----------|
| Service won't start | `kubectl logs deploy/osdu-X` | Check env vars, partition props |
| 401/403 errors | Token valid? User in groups? | Re-acquire token, add to groups |
| Search empty | Indexer running? | Wait 30s, check OpenSearch |
| SSL errors | Protocol mismatch | Set `elasticsearch.8.protocol=http` |
| RabbitMQ 404 | Vhost issue | Create topology in vhost "" |
| Stale config | Redis cache | `FLUSHALL` Redis |
| Connection refused | Service running? DNS? | Check pod status, DNS |

---

## Contact & Support

Khi gặp vấn đề không giải quyết được:
1. Collect logs: `kubectl -n osdu-core logs deploy/osdu-<service> > service.log`
2. Collect events: `kubectl -n osdu-core get events > events.log`
3. Document steps to reproduce
4. Check OSDU community forums
