# Step 25-26: Search & Schema Service Fix

## Tổng Quan

| Service | Issue | Root Cause | Solution |
|---------|-------|------------|----------|
| Search | HTTP 500, ES client error | ES 8.x client incompatible với OpenSearch 2.x | Nginx proxy rewrite headers |
| Schema | HTTP 500, Entitlements error | Missing ENTITLEMENTS_* env vars | Add env vars |
| Schema | HTTP 500, Database error | `osm.postgres.datasource.url` trỏ sai DB | Update partition property |

---

## Part 1: Search Service Fix (Step 25)

### Problem
OSDU Search service (version 0.28.2) sử dụng Elasticsearch 8.x Java client:
- `elasticsearch-java-8.13.4.jar`
- `elasticsearch-rest-client-8.13.4.jar`

ES 8.x client behaviors không compatible với OpenSearch 2.x:
1. Gửi `Content-Type: application/vnd.elasticsearch+json; compatible-with=8`
2. Yêu cầu `X-Elastic-Product: Elasticsearch` header trong response

### Solution: Nginx Proxy

**Architecture:**
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

**Files:**
- `k8s/osdu/deps/base/opensearch-proxy/configmap.yaml`
- `k8s/osdu/deps/base/opensearch-proxy/deployment.yaml`
- `k8s/osdu/deps/base/opensearch-proxy/service.yaml`
- `k8s/argocd/applications/osdu-opensearch-proxy.yaml`

**Partition Property:**
```json
"elasticsearch.8.host": "opensearch-proxy.osdu-data.svc.cluster.local"
```

### Attempted Solutions (Failed)
1. OpenSearch compatibility mode - không fix Content-Type validation
2. Java system properties `-Des.client.apiversioning=false` - ES 8.x client không respect
3. Partition properties `elasticsearch.8.api.versioning=false` - không được đọc

---

## Part 2: Schema Service Fix (Step 26)

### Problem 1: Entitlements Connection
**Error:**
```
java.net.UnknownHostException: entitlements: Name or service not known
URL: http://entitlements/api/entitlements/v2/groups
```

**Root Cause:** Missing env vars cho Entitlements URL

**Solution:** Add env vars to Schema deployment:
```bash
kubectl -n osdu-core set env deploy/osdu-schema \
  ENTITLEMENTS_HOST="http://osdu-entitlements:8080" \
  ENTITLEMENTS_URL="http://osdu-entitlements:8080/api/entitlements/v2" \
  ENTITLEMENTS_API="http://osdu-entitlements:8080/api/entitlements/v2" \
  AUTHORIZE_API="http://osdu-entitlements:8080/api/entitlements/v2"
```

### Problem 2: Database Connection
**Error:**
```
PSQLException: ERROR: relation "dataecosystem.system_schema_osm" does not exist
```

**Root Cause:** 
Schema service đọc `osm.postgres.datasource.url` từ partition properties.
Property này trỏ đến `storage` database thay vì `schema` database.

**Evidence from logs:**
```
Resolving property value for partition osdu and property osm.postgres.datasource.url
osm.postgres.datasource.url is not sensitive, the value: jdbc:postgresql://...5432/storage
```

**Solution:** Update partition property:
```bash
curl -X PATCH "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -d '{
    "properties": {
      "osm.postgres.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/schema"}
    }
  }'
```

**Note:** Tried `osm.schema.postgres.*` prefix but Schema service doesn't read it - only reads generic `osm.postgres.*`

---

## Runtime Configurations (Need Bootstrap/Init)

### 1. Partition Properties

**File:** `k8s/osdu/core/base/partition-init/osm-properties-payload.json`
```json
{
  "properties": {
    "osm.postgres.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/schema"},
    "osm.postgres.datasource.username": {"sensitive": false, "value": "osduadmin"},
    "osm.postgres.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
    "osm.postgres.datasource.schema": {"sensitive": false, "value": "dataecosystem"},
    "elasticsearch.8.host": {"sensitive": false, "value": "opensearch-proxy.osdu-data.svc.cluster.local"},
    "elasticsearch.8.port": {"sensitive": false, "value": "9200"},
    "elasticsearch.8.https": {"sensitive": false, "value": "false"},
    "elasticsearch.8.tls": {"sensitive": false, "value": "false"}
  }
}
```

### 2. Schema Deployment ENV Vars (Need to add to YAML)
```yaml
env:
  - name: ENTITLEMENTS_HOST
    value: "http://osdu-entitlements:8080"
  - name: ENTITLEMENTS_URL
    value: "http://osdu-entitlements:8080/api/entitlements/v2"
  - name: ENTITLEMENTS_API
    value: "http://osdu-entitlements:8080/api/entitlements/v2"
  - name: AUTHORIZE_API
    value: "http://osdu-entitlements:8080/api/entitlements/v2"
```

---

## Git Commits
- `b7945c3` - feat(osdu-deps): add opensearch-proxy to rewrite ES8 Content-Type header
- `04f671c` - fix(opensearch-proxy): add X-Elastic-Product header for ES 8.x client compatibility
- `7ba2c58` - docs: add step25 search service fix detailed documentation
- `3e8012f` - feat: add opensearch-proxy ArgoCD app and partition properties documentation

---

## Lessons Learned

1. **ES 8.x client hardcodes protocol behaviors** - Cannot disable via config
2. **Proxy pattern effective** - Solves incompatibility without code changes
3. **OSDU services read partition properties dynamically** - Not just env vars
4. **Different services use different property prefixes** - Legal uses `osm.legal.postgres.*`, Schema uses generic `osm.postgres.*`
5. **Incremental debugging essential** - Each fix reveals next issue
