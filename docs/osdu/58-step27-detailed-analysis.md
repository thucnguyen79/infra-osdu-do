# Step 27: OSDU E2E Pipeline - Phân Tích Chi Tiết

## Mục Lục
1. [Tổng Quan](#1-tổng-quan)
2. [Timeline Thực Hiện](#2-timeline-thực-hiện)
3. [Các Vấn Đề Gặp Phải và Cách Xử Lý](#3-các-vấn-đề-gặp-phải-và-cách-xử-lý)
4. [Lessons Learned](#4-lessons-learned)
5. [Cấu Hình Cuối Cùng](#5-cấu-hình-cuối-cùng)

---

## 1. Tổng Quan

### Mục tiêu
Hoàn thiện pipeline E2E cho OSDU: **Create Record → Storage → RabbitMQ → Indexer → OpenSearch → Search API**

### Kết quả cuối cùng
- ✅ **THÀNH CÔNG** - Pipeline hoạt động hoàn chỉnh
- 16 Well records + 2 Wellbore records được index và search thành công

### Thời gian thực hiện
- Bắt đầu: Step 27 Part 18-19
- Kết thúc: Step 27 Complete
- Số lần debug/fix: ~15+ iterations

---

## 2. Timeline Thực Hiện

### Phase 1: Initial Testing
| Step | Action | Result |
|------|--------|--------|
| 1 | Create test record | ✅ Record created |
| 2 | Check Indexer logs | ❌ Schema fetch failed |
| 3 | Check Search API | ❌ 0 results |

**Vấn đề phát hiện:** Indexer không thể fetch schema từ Schema Service

---

### Phase 2: Schema Service Debugging

#### Issue 2.1: SCHEMA_HOST URL Sai
```
Indexer gọi: http://osdu-schema:8080/osdu:wks:master-data--Well:1.0.0
Đúng phải là: http://osdu-schema:8080/api/schema-service/v1/schema/osdu:wks:master-data--Well:1.0.0
```

**Root Cause:** Indexer deployment có inline env var:
```yaml
- name: SCHEMA_HOST
  value: "http://osdu-schema:8080"  # Thiếu path
```

**Fix:**
```bash
# Update Git repo (repo-first)
sed -i 's|value: "http://osdu-schema:8080"$|value: "http://osdu-schema:8080/api/schema-service/v1/schema"|' \
  k8s/osdu/core/base/services/indexer/indexer-deploy.yaml

git commit -m "fix(indexer): SCHEMA_HOST URL include full path"
git push
# ArgoCD sync → Indexer restart
```

**Kết quả:** ✅ Fixed, committed to repo

---

#### Issue 2.2: S3 Credentials với sensitive=true
```
Error: "HNKMSNYU1OWFA4TH3QWT not configured correctly for partition osdu"
```

**Root Cause:** Partition config có `sensitive: true` cho S3 credentials
```json
"obm.minio.accessKey": {"sensitive": true, "value": "HNKMSNYU1OWFA4TH3QWT"}
```
Khi `sensitive=true`, OSDU service tìm environment variable tên `HNKMSNYU1OWFA4TH3QWT` thay vì dùng giá trị đó.

**Fix:**
```bash
# Update partition via API
curl -X PATCH "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "obm.minio.accessKey": {"sensitive": false, "value": "HNKMSNYU1OWFA4TH3QWT"},
    "obm.minio.secretKey": {"sensitive": false, "value": "zPPZGaCsDytP84Dqw3bIl0QEd8pwboDUryAMErlg"},
    "storage.s3.accessKeyId": {"sensitive": false, "value": "HNKMSNYU1OWFA4TH3QWT"},
    "storage.s3.secretAccessKey": {"sensitive": false, "value": "zPPZGaCsDytP84Dqw3bIl0QEd8pwboDUryAMErlg"},
    "oqm.s3.accessKeyId": {"sensitive": false, "value": "HNKMSNYU1OWFA4TH3QWT"},
    "oqm.s3.secretAccessKey": {"sensitive": false, "value": "zPPZGaCsDytP84Dqw3bIl0QEd8pwboDUryAMErlg"}
  }'

# Restart Schema service để reload partition config
kubectl -n osdu-core rollout restart deploy/osdu-schema
```

**Kết quả:** ✅ Fixed (runtime config, documented in partition-properties.json)

---

#### Issue 2.3: S3 Bucket Không Tồn Tại
```
Error: ErrorResponse(code = NoSuchBucket, bucketName = osdu-poc-osdu-schema)
```

**Root Cause:** Schema Service cần bucket `osdu-poc-osdu-schema` để lưu schema JSON files, nhưng bucket chưa được tạo.

**Fix Attempt 1 - ObjectBucketClaim:**
```yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: osdu-schema-bucket
  namespace: rook-ceph
spec:
  bucketName: osdu-poc-osdu-schema
  storageClassName: rook-ceph-bucket
```
**Kết quả:** ❌ OBC created nhưng bucket không được provision (StorageClass không tồn tại)

**Fix Attempt 2 - Manual với boto3:**
```python
import boto3
s3 = boto3.client('s3',
    endpoint_url='http://localhost:8080',  # port-forward từ RGW
    aws_access_key_id='HNKMSNYU1OWFA4TH3QWT',
    aws_secret_access_key='zPPZGaCsDytP84Dqw3bIl0QEd8pwboDUryAMErlg',
    config=Config(signature_version='s3v4'))
s3.create_bucket(Bucket='osdu-poc-osdu-schema')
```
**Kết quả:** ✅ Bucket created successfully

**Partition properties cần thêm:**
```json
"system.schema.bucket.name": {"sensitive": false, "value": "osdu-poc-osdu-schema"},
"obm.minio.schema.bucket": {"sensitive": false, "value": "osdu-poc-osdu-schema"}
```

---

### Phase 3: Schema Creation Issues

#### Issue 3.1: Schema GET by ID trả về 404
```
List schemas → Total: 1, osdu:wks:master-data--Well:1.0.0 ✅
GET schema by ID → 404 "Schema is not present" ❌
```

**Root Cause:** Schema metadata tồn tại trong DB nhưng content không được lưu do S3 lỗi khi tạo.

**Fix:** Delete schema và tạo lại sau khi fix S3:
```sql
DELETE FROM osdu.schema_osm WHERE id LIKE '%master-data--Well%';
```

---

#### Issue 3.2: Xóa Nhầm Reference Data
```sql
-- Vô tình xóa reference data
DELETE FROM osdu.authority;
DELETE FROM osdu.source;
DELETE FROM osdu."entityType";
```

**Triệu chứng:** Schema creation failed với 500 error

**Fix - Restore reference data:**
```sql
INSERT INTO osdu.authority (id, data) VALUES ('osdu', '{"name": "osdu"}');
INSERT INTO osdu.source (id, data) VALUES ('wks', '{"name": "wks"}');
INSERT INTO osdu."entityType" (id, data) VALUES ('master-data--Well', '{"name": "master-data--Well"}');
```

**Kết quả:** ✅ Reference data restored, schema creation successful

---

### Phase 4: OpenSearch Indexing Issues

#### Issue 4.1: flattened Type Không Được Hỗ Trợ
```
[es/indices.create] failed: [mapper_parsing_exception] 
Failed to parse mapping [_doc]: No handler for type [flattened] declared on field [tags]
```

**Root Cause:** 
- OSDU Indexer được build cho **Elasticsearch**
- OpenSearch 7.10.2 **không có** `flattened` type (đây là Elasticsearch feature)
- Mỗi khi tạo record với kind mới, Indexer cố tạo index với mapping chứa `flattened` → FAIL

**Fix Attempt 1 - Index Template:**
```bash
curl -X PUT "http://opensearch:9200/_index_template/osdu-template" \
  -d '{
    "index_patterns": ["osdu-*"],
    "template": {
      "mappings": {
        "properties": {
          "tags": {"type": "object", "enabled": false}
        }
      }
    }
  }'
```
**Kết quả:** ❌ Index Template không apply vì Indexer gửi explicit mapping trong request

**Giải thích:** Index Template chỉ apply khi:
- Index được auto-create (khi index document vào index không tồn tại)
- Index được tạo KHÔNG có explicit mapping

Indexer LUÔN gửi mapping với `flattened` → Template bị ignore

**Fix Attempt 2 - Pre-create Index:**
```bash
# Tạo index TRƯỚC khi có record đầu tiên
curl -X PUT "http://opensearch:9200/osdu-wks-master-data--well-1.0.0" \
  -d '{
    "mappings": {
      "properties": {
        "tags": {"type": "object", "enabled": false},
        "data": {"type": "object", "dynamic": true},
        ...
      }
    }
  }'
```
**Kết quả:** ✅ SUCCESS! Index tồn tại → Indexer không cần tạo mới → Indexing hoạt động

---

#### Issue 4.2: Schema Structure Không Đúng OSDU Format
```
Error: Schema doesn't have properties section, kind: osdu:wks:master-data--Well:1.0.0
```

**Root Cause:** Schema ban đầu quá đơn giản:
```json
{
  "type": "object",
  "properties": {
    "FacilityName": {"type": "string"}
  }
}
```

OSDU Indexer cần schema có cấu trúc cụ thể với `data.properties`.

**Fix - OSDU-compliant schema:**
```json
{
  "schema": {
    "type": "object",
    "properties": {
      "id": {"type": "string"},
      "kind": {"type": "string"},
      "data": {
        "type": "object",
        "properties": {
          "FacilityName": {"type": "string"},
          "FacilityID": {"type": "string"}
        }
      }
    }
  }
}
```

**Kết quả:** ✅ Fixed

---

### Phase 5: E2E Verification

#### Test Flow
```
1. Create Record → Storage Service ✅
2. Storage publish message → RabbitMQ ✅
3. Indexer consume message → Fetch schema ✅
4. Indexer index to OpenSearch ✅
5. Search API query → Return results ✅
```

#### Final Results
```
Total Well records: 16
Total Wellbore records: 2
OpenSearch indices: 7 pre-created
RabbitMQ queues: 0 pending messages
```

---

## 3. Các Vấn Đề Gặp Phải và Cách Xử Lý

### Bảng Tổng Hợp

| # | Vấn Đề | Root Cause | Fix | Rollback? | Repo-first? |
|---|--------|------------|-----|-----------|-------------|
| 1 | SCHEMA_HOST URL sai | Inline env thiếu path | Update Git repo | No | ✅ Yes |
| 2 | S3 credentials sensitive=true | Partition config sai | PATCH partition API | No | ⚠️ Runtime |
| 3 | Schema bucket không tồn tại | Chưa tạo bucket | boto3 create_bucket | No | ⚠️ OBC added |
| 4 | Schema GET 404 | S3 lỗi khi create | Delete + recreate | No | N/A |
| 5 | Reference data bị xóa | Human error | Restore SQL | Yes | N/A |
| 6 | flattened type lỗi | OpenSearch incompatible | Pre-create index | No | ✅ Job added |
| 7 | Schema structure sai | Thiếu data.properties | Recreate với đúng format | No | N/A |

---

## 4. Lessons Learned

### 4.1. Kubernetes Env Priority
```yaml
# Inline env CÓ priority cao hơn envFrom
spec:
  containers:
  - env:                    # Priority 1 (highest)
    - name: VAR
      value: "inline"
    envFrom:                # Priority 2
    - configMapRef:
        name: my-config
```
**Lesson:** Khi patch ConfigMap, phải check xem deployment có inline env không.

### 4.2. OSDU Partition sensitive Flag
```json
// sensitive: true → Service tìm ENV VAR có tên = value
"key": {"sensitive": true, "value": "MY_SECRET"}
// → Service tìm: process.env["MY_SECRET"]

// sensitive: false → Service dùng value trực tiếp
"key": {"sensitive": false, "value": "actual-value"}
// → Service dùng: "actual-value"
```
**Lesson:** S3 credentials cho Schema Service PHẢI có sensitive=false

### 4.3. OpenSearch vs Elasticsearch Incompatibility
| Feature | Elasticsearch | OpenSearch 7.x | OpenSearch 2.x |
|---------|---------------|----------------|----------------|
| flattened type | ✅ | ❌ | ✅ (flat_object) |
| Index Template | ✅ | ✅ | ✅ |

**Lesson:** OSDU reference implementation built for Elasticsearch. Dùng OpenSearch cần workaround.

### 4.4. Index Template Limitation
```
Index Template KHÔNG apply khi request có explicit mapping.
OSDU Indexer LUÔN gửi explicit mapping.
→ Index Template không giải quyết được vấn đề flattened.
→ Phải pre-create index TRƯỚC khi dùng kind mới.
```

### 4.5. ArgoCD và GitOps
```
Manual kubectl changes → Temporary (ArgoCD sẽ revert)
Git repo changes → Persistent (ArgoCD sync)
```
**Lesson:** Luôn update Git repo trước, không chỉ kubectl apply.

### 4.6. SQL Escaping trong Multi-shell
```bash
# Khi pass JSON qua: bash → kubectl → bash → psql
# Dùng heredoc để tránh escaping issues:
kubectl exec -i pod -- bash -c "psql" << 'EOF'
INSERT INTO table VALUES ('{"key": "value"}');
EOF
```

---

## 5. Cấu Hình Cuối Cùng

### 5.1. Indexer Environment (Git Repo)
File: `k8s/osdu/core/base/services/indexer/indexer-deploy.yaml`
```yaml
- name: SCHEMA_HOST
  value: "http://osdu-schema:8080/api/schema-service/v1/schema"
- name: SCHEMA_API
  value: "http://osdu-schema:8080/api/schema-service/v1"
```

### 5.2. Partition Properties (Runtime)
```json
{
  "obm.minio.accessKey": {"sensitive": false, "value": "HNKMSNYU1OWFA4TH3QWT"},
  "obm.minio.secretKey": {"sensitive": false, "value": "zPPZGaCsDytP84Dqw3bIl0QEd8pwboDUryAMErlg"},
  "obm.minio.schema.bucket": {"sensitive": false, "value": "osdu-poc-osdu-schema"},
  "system.schema.bucket.name": {"sensitive": false, "value": "osdu-poc-osdu-schema"},
  "storage.s3.accessKeyId": {"sensitive": false, "value": "HNKMSNYU1OWFA4TH3QWT"},
  "storage.s3.secretAccessKey": {"sensitive": false, "value": "zPPZGaCsDytP84Dqw3bIl0QEd8pwboDUryAMErlg"},
  "oqm.s3.accessKeyId": {"sensitive": false, "value": "HNKMSNYU1OWFA4TH3QWT"},
  "oqm.s3.secretAccessKey": {"sensitive": false, "value": "zPPZGaCsDytP84Dqw3bIl0QEd8pwboDUryAMErlg"}
}
```

### 5.3. S3 Buckets
```
osdu-file
osdu-legal
osdu-poc-osdu-records
osdu-poc-osdu-schema  ← Created for Schema Service
osdu-storage
```

### 5.4. OpenSearch Indices (Pre-created)
```
osdu-wks-master-data--well-1.0.0
osdu-wks-master-data--wellbore-1.0.0
osdu-wks-master-data--organisation-1.0.0
osdu-wks-master-data--field-1.0.0
osdu-wks-master-data--basin-1.0.0
osdu-wks-work-product--document-1.0.0
osdu-wks-work-product-component--welllog-1.0.0
```

### 5.5. Index Mapping (Compatible với OpenSearch)
```json
{
  "mappings": {
    "properties": {
      "id": {"type": "keyword"},
      "kind": {"type": "keyword"},
      "tags": {"type": "object", "enabled": false},  // Thay vì flattened
      "data": {"type": "object", "dynamic": true},
      "acl": {"properties": {"viewers": {"type": "keyword"}, "owners": {"type": "keyword"}}},
      "legal": {"properties": {"legaltags": {"type": "keyword"}, "otherRelevantDataCountries": {"type": "keyword"}}},
      "index": {"properties": {"statusCode": {"type": "integer"}, "lastUpdateTime": {"type": "date"}}},
      ...
    }
  }
}
```

### 5.6. Scripts và Jobs (Git Repo)
```
scripts/create-osdu-index.sh          # Manual pre-create index
k8s/osdu/core/base/jobs/opensearch-init-job.yaml  # Auto pre-create indices
k8s/osdu/storage/base/schema-bucket-obc.yaml      # Schema bucket definition
```

---

## 6. Quy Trình Khi Thêm Kind Mới

### Step-by-step
1. **Tạo Schema:**
```bash
   curl -X POST "http://osdu-schema:8080/api/schema-service/v1/schema" \
     -H "Authorization: Bearer $TOKEN" \
     -H "data-partition-id: osdu" \
     -d '{"schemaInfo": {...}, "schema": {...}}'
```

2. **Pre-create Index:**
```bash
   ./scripts/create-osdu-index.sh osdu:wks:master-data--NewEntity:1.0.0
```

3. **Create Record:**
```bash
   curl -X PUT "http://osdu-storage:8080/api/storage/v2/records" \
     -H "Authorization: Bearer $TOKEN" \
     -d '[{"kind": "osdu:wks:master-data--NewEntity:1.0.0", ...}]'
```

4. **Verify:**
```bash
   curl -X POST "http://osdu-search:8080/api/search/v2/query" \
     -d '{"kind": "osdu:wks:master-data--NewEntity:1.0.0"}'
```

---

## 7. Restore Procedure (Nếu Cần Rollback)

### 7.1. Restore Partition Properties
```bash
curl -X PUT "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @artifacts/step27-backup/YYYYMMDD-HHMMSS/partition-properties.json
```

### 7.2. Recreate S3 Bucket
```python
import boto3
s3 = boto3.client('s3', endpoint_url='...', ...)
s3.create_bucket(Bucket='osdu-poc-osdu-schema')
```

### 7.3. Recreate OpenSearch Indices
```bash
./scripts/create-osdu-index.sh osdu:wks:master-data--Well:1.0.0
./scripts/create-osdu-index.sh osdu:wks:master-data--Wellbore:1.0.0
# ... các kind khác
```

---

## 8. Files Reference

### Git Repo
```
k8s/osdu/core/base/services/indexer/indexer-deploy.yaml  # SCHEMA_HOST fix
k8s/osdu/core/base/jobs/opensearch-init-job.yaml         # Pre-create indices
k8s/osdu/storage/base/schema-bucket-obc.yaml             # Schema bucket
k8s/osdu/core/overlays/do-private/configs/partition-properties.json  # Template
scripts/create-osdu-index.sh                              # Manual script
docs/osdu/38-step27-known-issues.md                       # Known issues
```

### Backup
```
artifacts/step27-backup/YYYYMMDD-HHMMSS/
├── partition-properties.json    # 172 keys
├── env-indexer.txt              # 71 vars
├── env-schema.txt               # 12 vars
├── env-storage.txt              # 93 vars
├── opensearch-indices.txt       # 7 indices
├── opensearch-template.json     # Index template
├── mapping-*.json               # Index mappings
├── s3-buckets.txt               # 5 buckets
├── rabbitmq-queues.txt          # Queue list
└── SUMMARY.md                   # Backup summary
```

---

## 9. Kết Luận

Step 27 đã hoàn thành với nhiều challenges:
1. **OSDU Reference Implementation** được build cho GCP/Azure, cần adapt cho self-hosted
2. **OpenSearch vs Elasticsearch** có incompatibility cần workaround
3. **Partition Properties** có nhiều properties cần configure đúng
4. **Repo-first** là best practice nhưng một số config chỉ có thể runtime

**Recommendation cho Production:**
- Upgrade OpenSearch 2.x (có flat_object type)
- Hoặc chuyển sang Elasticsearch
- Implement External Secrets cho sensitive values
- Automate index pre-creation trong CI/CD pipeline

