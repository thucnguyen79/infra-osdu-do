# Step 25: Search Service Fix - Chi Tiết Các Thao Tác

## Tổng Quan

**Mục tiêu:** Fix OSDU Search service HTTP 500 errors khi query OpenSearch

**Thời gian:** 2026-01-26

**Kết quả:** ✅ SUCCESS - Search service hoạt động với OpenSearch qua Nginx proxy

---

## Vấn Đề Ban Đầu

### Error Message
```
HTTP/1.1 500 Internal Server Error
{"code":500,"reason":"Search error","message":"Error processing search request"}
```

### Root Cause Analysis
OSDU Search service (version 0.28.2) sử dụng:
- `elasticsearch-java-8.13.4.jar` (ES 8.x Java client)
- `elasticsearch-rest-client-8.13.4.jar`

ES 8.x client có 2 behaviors không compatible với OpenSearch 2.x:
1. Gửi `Content-Type: application/vnd.elasticsearch+json; compatible-with=8`
2. Yêu cầu `X-Elastic-Product: Elasticsearch` header trong response

OpenSearch 2.16.0 (fork từ ES 7.x) không hiểu protocols này.

---

## Các Bước Đã Thử (Chronological)

### Bước 1: Fix SSL/HTTPS Mismatch ✅ SUCCESS
**Vấn đề:** Search service connect HTTPS trong khi OpenSearch chỉ có HTTP

**Nguyên nhân:** Thiếu partition properties `elasticsearch.8.https` và `elasticsearch.8.tls`

**Fix:**
```bash
# PATCH partition properties
curl -X PATCH "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -d '{
    "properties": {
      "elasticsearch.8.https": {"sensitive": false, "value": "false"},
      "elasticsearch.8.tls": {"sensitive": false, "value": "false"}
    }
  }'
```

**Kết quả:** SSL issue resolved, nhưng xuất hiện lỗi mới 406 Not Acceptable

---

### Bước 2: Enable OpenSearch Compatibility Mode ❌ KHÔNG ĐỦ
**Vấn đề:** `Content-Type header [application/vnd.elasticsearch+json; compatible-with=8] is not supported`

**Thử:**
```bash
# Enable compatibility mode
curl -X PUT "http://osdu-opensearch:9200/_cluster/settings" \
  -d '{"persistent": {"compatibility.override_main_response_version": true}}'
```

**Kết quả:** Setting được enable nhưng KHÔNG fix được Content-Type rejection

---

### Bước 3: Java System Properties ❌ KHÔNG WORK
**Vấn đề:** Thử disable ES client API versioning qua JVM args

**Thử:**
```bash
kubectl -n osdu-core set env deploy/osdu-search \
  JAVA_OPTS="-Xms256m -Xmx512m -Des.client.apiversioning=false -Delastic.client.apiversioning=false"
```

**Kết quả:** ES 8.x client KHÔNG respect system properties này - vẫn gửi ES8 Content-Type

---

### Bước 4: Partition Properties cho API Versioning ❌ KHÔNG WORK
**Vấn đề:** Thử hint client dùng ES7 mode qua partition

**Thử:**
```bash
curl -X PATCH "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -d '{
    "properties": {
      "elasticsearch.8.api.versioning": {"sensitive": false, "value": "false"},
      "elasticsearch.8.compatibility.mode": {"sensitive": false, "value": "7"},
      "elasticsearch.client.apiversioning": {"sensitive": false, "value": "false"}
    }
  }'
```

**Kết quả:** Properties được set nhưng Search service KHÔNG đọc chúng

---

### Bước 5: Nginx Proxy - Lần 1 ❌ CONFIG ERROR
**Vấn đề:** Deploy proxy để rewrite Content-Type header

**Lỗi:**
```
[emerg] the duplicate "content_type" variable in /etc/nginx/nginx.conf:18
```

**Nguyên nhân:** `$content_type` là Nginx built-in variable, không thể `set` lại

---

### Bước 6: Nginx Proxy - Lần 2 ✅ PARTIAL SUCCESS
**Fix:** Dùng `map` directive thay vì `set`
```nginx
map $http_content_type $proxy_content_type {
  ~*application/vnd\.elasticsearch  "application/json";
  default                           $http_content_type;
}
```

**Kết quả:** Proxy hoạt động, Content-Type được rewrite, nhưng xuất hiện lỗi mới:
```
Missing [X-Elastic-Product] header
```

---

### Bước 7: Nginx Proxy - Thêm X-Elastic-Product Header ✅ FINAL SUCCESS
**Fix:** Thêm header injection vào nginx config
```nginx
add_header X-Elastic-Product "Elasticsearch" always;
```

**Kết quả:** 
```json
{"results":[],"aggregations":[],"phraseSuggestions":[],"totalCount":0}
```

Search service hoạt động!

---

## Giải Pháp Cuối Cùng

### Architecture
```
OSDU Search Service (ES 8.x client)
         │
         │ Content-Type: application/vnd.elasticsearch+json; compatible-with=8
         ▼
┌─────────────────────────────────┐
│     opensearch-proxy (Nginx)    │
│  - Rewrite Content-Type → JSON  │
│  - Add X-Elastic-Product header │
└─────────────────────────────────┘
         │
         │ Content-Type: application/json
         │ (Response has X-Elastic-Product: Elasticsearch)
         ▼
    OpenSearch 2.16.0
```

### Files Trong Repo
```
k8s/osdu/deps/base/opensearch-proxy/
├── configmap.yaml      # Nginx config với header manipulation
├── deployment.yaml     # Nginx deployment
├── service.yaml        # ClusterIP service
└── kustomization.yaml  # Kustomize bundle
```

### Git Commits
- `b7945c3` - feat(osdu-deps): add opensearch-proxy to rewrite ES8 Content-Type header
- `04f671c` - fix(opensearch-proxy): add X-Elastic-Product header for ES 8.x client compatibility

---

## Cấu Hình Runtime (Chưa Trong Repo)

### 1. Partition Properties
Cần được set qua API hoặc init job:
```json
{
  "elasticsearch.8.host": "opensearch-proxy.osdu-data.svc.cluster.local",
  "elasticsearch.8.port": "9200",
  "elasticsearch.8.https": "false",
  "elasticsearch.8.tls": "false",
  "elasticsearch.8.ssl.enabled": "false",
  "elasticsearch.8.https.enabled": "false",
  "elasticsearch.8.scheme": "http",
  "elasticsearch.8.protocol": "http",
  "elasticsearch.8.user": "",
  "elasticsearch.8.password": ""
}
```

### 2. Search Deployment JAVA_OPTS
Đã set nhưng KHÔNG cần thiết cho fix cuối cùng:
```
JAVA_OPTS=-Xms256m -Xmx512m -Des.client.apiversioning=false ...
```

### 3. OpenSearch Cluster Settings
Đã set nhưng KHÔNG cần thiết cho fix cuối cùng:
```json
{"persistent": {"compatibility.override_main_response_version": "true"}}
```

---

## TODO: Cần Hoàn Thiện

### 1. ArgoCD Integration
opensearch-proxy cần được thêm vào ArgoCD app-of-apps

### 2. Partition Properties trong Repo
Cần tạo init job hoặc ConfigMap để persist partition properties

### 3. Cleanup
- Revert JAVA_OPTS không cần thiết trong Search deployment
- Document OpenSearch compatibility setting (có thể giữ hoặc remove)

---

## Lessons Learned

1. **ES 8.x client hardcodes protocol behaviors** - Không thể disable qua config
2. **Proxy pattern hiệu quả** - Giải quyết incompatibility mà không cần thay đổi source code
3. **Incremental debugging** - Mỗi fix reveal lỗi tiếp theo
4. **Repo-first quan trọng** - Runtime changes dễ bị mất
