# Step 19 - OSDU Core Services Smoke Tests & Configuration

## Mục tiêu
Kiểm tra và cấu hình các OSDU Core Services hoạt động end-to-end:
- Partition Service
- Entitlements Service  
- Legal Service
- Schema Service
- Storage Service

## Kết quả
✅ **TẤT CẢ 5 CORE SERVICES HOẠT ĐỘNG** (2026-01-11)

---

## 1. Các vấn đề đã gặp và cách khắc phục

### 1.1 Partition Configuration - TenantInfo Properties

**Vấn đề:** Core Plus services yêu cầu partition có đầy đủ TenantInfo properties với format chính xác.

**Root cause:** 
- `crmAccountID` phải là **JSON array string**, không phải string đơn
- Một số properties sử dụng **camelCase** (không phải hyphen)
- Các services cần properties khác nhau từ partition

**Fix - Partition properties đầy đủ:**
```json
{
  "properties": {
    "dataPartitionId": {"sensitive": false, "value": "osdu"},
    "name": {"sensitive": false, "value": "osdu"},
    "projectId": {"sensitive": false, "value": "osdu-project"},
    "crmAccountID": {"sensitive": false, "value": "[\"osdu-crm\"]"},
    "complianceRuleSet": {"sensitive": false, "value": "shared"},
    "serviceAccount": {"sensitive": false, "value": "osdu-service"},
    "storageAccountName": {"sensitive": false, "value": "osdu"},
    "domain": {"sensitive": false, "value": "osdu.local"},
    "gcpProjectId": {"sensitive": false, "value": "osdu-project"},
    
    "elastic-endpoint": {"sensitive": false, "value": "http://osdu-opensearch.osdu-data:9200"},
    "elastic-username": {"sensitive": false, "value": "admin"},
    "elastic-password": {"sensitive": false, "value": "admin"},
    "redis-database": {"sensitive": false, "value": "4"},
    
    "osm.postgres.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/legal"},
    "osm.postgres.datasource.username": {"sensitive": false, "value": "osduadmin"},
    "osm.postgres.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
    "osm.postgres.datasource.schema": {"sensitive": false, "value": "public"},
    
    "obm.minio.endpoint": {"sensitive": false, "value": "http://rook-ceph-rgw-osdu-store.rook-ceph:80"},
    "obm.minio.accessKey": {"sensitive": false, "value": "osdu-s3-user"},
    "obm.minio.secretKey": {"sensitive": true, "value": "OBM_MINIO_SECRET_KEY"},
    "obm.minio.bucket": {"sensitive": false, "value": "osdu-legal"},
    
    "legal-tag-allowed-data-types": {"sensitive": false, "value": "[\"Public Domain Data\",\"Third Party Data\",\"Transferred Data\"]"},
    "legal-tag-allowed-security-classifications": {"sensitive": false, "value": "[\"Public\",\"Private\",\"Confidential\"]"},
    "compliance-ruleset-id": {"sensitive": false, "value": "shared"},
    
    "entitlements.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/entitlements"},
    "entitlements.datasource.username": {"sensitive": false, "value": "osduadmin"},
    "entitlements.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
    "entitlements.datasource.schema": {"sensitive": false, "value": "public"},
    
    "legal.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/legal"},
    "legal.datasource.username": {"sensitive": false, "value": "osduadmin"},
    "legal.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
    "legal.datasource.schema": {"sensitive": false, "value": "public"},
    
    "storage.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/storage"},
    "storage.datasource.username": {"sensitive": false, "value": "osduadmin"},
    "storage.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
    "storage.datasource.schema": {"sensitive": false, "value": "public"},
    
    "schema.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/schema"},
    "schema.datasource.username": {"sensitive": false, "value": "osduadmin"},
    "schema.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
    "schema.datasource.schema": {"sensitive": false, "value": "public"},
    
    "file.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/file"},
    "file.datasource.username": {"sensitive": false, "value": "osduadmin"},
    "file.datasource.password": {"sensitive": false, "value": "CHANGE_ME_STRONG"},
    "file.datasource.schema": {"sensitive": false, "value": "public"}
  }
}
```

**Lưu ý quan trọng:**
- `sensitive: true` → service sẽ tìm **env var có tên = value** để lấy giá trị thực
- `sensitive: false` → service sử dụng value trực tiếp

---

### 1.2 Entitlements Service - Database Schema & Redis

**Vấn đề 1:** Database `entitlements` trống, không có tables.

**Root cause:** Core Plus images không có Flyway/auto-DDL, cần tạo schema thủ công.

**Fix - SQL Schema cho Entitlements:**
```sql
-- Database: entitlements

CREATE TABLE member (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    partition_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE "group" (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    partition_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE member_to_group (
    id BIGSERIAL PRIMARY KEY,
    member_id BIGINT NOT NULL REFERENCES member(id) ON DELETE CASCADE,
    group_id BIGINT NOT NULL REFERENCES "group"(id) ON DELETE CASCADE,
    role VARCHAR(50) DEFAULT 'MEMBER',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(member_id, group_id)
);

CREATE TABLE embedded_group (
    id BIGSERIAL PRIMARY KEY,
    parent_id BIGINT NOT NULL REFERENCES "group"(id) ON DELETE CASCADE,
    child_id BIGINT NOT NULL REFERENCES "group"(id) ON DELETE CASCADE,
    UNIQUE(parent_id, child_id)
);

-- Indexes
CREATE INDEX idx_member_email ON member(email);
CREATE INDEX idx_member_partition ON member(partition_id);
CREATE INDEX idx_group_email ON "group"(email);
CREATE INDEX idx_group_partition ON "group"(partition_id);
CREATE INDEX idx_m2g_member ON member_to_group(member_id);
CREATE INDEX idx_m2g_group ON member_to_group(group_id);
CREATE INDEX idx_embedded_parent ON embedded_group(parent_id);
CREATE INDEX idx_embedded_child ON embedded_group(child_id);
```

**Vấn đề 2:** Entitlements dùng Redis variables khác với các services khác.

**Root cause:** Entitlements Core Plus có riêng config cho Redis user info/groups.

**Fix - Environment variables cho Entitlements:**
```yaml
env:
  - name: REDIS_USER_INFO_HOST
    value: "osdu-redis.osdu-data.svc.cluster.local"
  - name: REDIS_USER_INFO_PORT
    value: "6379"
  - name: REDIS_USER_GROUPS_HOST
    value: "osdu-redis.osdu-data.svc.cluster.local"
  - name: REDIS_USER_GROUPS_PORT
    value: "6379"
  - name: POSTGRES_PASSWORD
    value: "CHANGE_ME_STRONG"  # hoặc secretKeyRef
```

---

### 1.3 Legal Service - Database Schema & Service URLs

**Vấn đề 1:** Legal gọi service names sai (`entitlements`, `partition` thay vì `osdu-entitlements`, `osdu-partition`).

**Fix - Environment variables cho Legal:**
```yaml
env:
  - name: PARTITION_HOST
    value: "http://osdu-partition:8080"
  - name: PARTITION_API
    value: "http://osdu-partition:8080/api/partition/v1"
  - name: PARTITION_SERVICE_ENDPOINT
    value: "http://osdu-partition:8080"
  - name: ENTITLEMENTS_HOST
    value: "http://osdu-entitlements:8080"
  - name: ENTITLEMENTS_URL
    value: "http://osdu-entitlements:8080/api/entitlements/v2"
  - name: AUTHORIZE_API
    value: "http://osdu-entitlements:8080/api/entitlements/v2"
  - name: OBM_MINIO_SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: rook-ceph-object-user-osdu-store-osdu-s3-user
        key: SecretKey
```

**Vấn đề 2:** Database `legal` cần table `osdu."LegalTagOsm"` với schema cụ thể.

**Fix - SQL Schema cho Legal:**
```sql
-- Database: legal

CREATE SCHEMA IF NOT EXISTS osdu;

CREATE TABLE osdu."LegalTagOsm" (
    pk BIGSERIAL PRIMARY KEY,
    id VARCHAR(255),
    name VARCHAR(255),
    description TEXT,
    properties JSONB,
    data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255),
    modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_by VARCHAR(255)
);

CREATE INDEX idx_legaltag_name ON osdu."LegalTagOsm"(name);
```

---

### 1.4 Entitlements Bootstrap - Groups & User Membership

**Vấn đề:** User không có quyền vì chưa có groups trong database.

**Fix - Bootstrap data:**
```sql
-- Database: entitlements

-- 1. Insert user (email phải khớp với JWT claim)
INSERT INTO member (email, partition_id) 
VALUES ('test@osdu.internal', 'osdu')
ON CONFLICT (email) DO NOTHING;

-- 2. Insert essential groups
INSERT INTO "group" (email, name, description, partition_id) VALUES
('users@osdu.osdu.local', 'users', 'All users', 'osdu'),
('users.datalake.ops@osdu.osdu.local', 'users.datalake.ops', 'OSDU Operators', 'osdu'),
('users.datalake.admins@osdu.osdu.local', 'users.datalake.admins', 'OSDU Admins', 'osdu'),
('users.datalake.viewers@osdu.osdu.local', 'users.datalake.viewers', 'OSDU Viewers', 'osdu'),
('users.datalake.editors@osdu.osdu.local', 'users.datalake.editors', 'OSDU Editors', 'osdu'),
('service.entitlements.user@osdu.osdu.local', 'service.entitlements.user', 'Entitlements Service', 'osdu'),
('service.legal.user@osdu.osdu.local', 'service.legal.user', 'Legal Service User', 'osdu'),
('service.legal.admin@osdu.osdu.local', 'service.legal.admin', 'Legal Service Admin', 'osdu'),
('service.legal.editor@osdu.osdu.local', 'service.legal.editor', 'Legal Service Editor', 'osdu')
ON CONFLICT (email) DO NOTHING;

-- 3. Add user to groups
INSERT INTO member_to_group (member_id, group_id, role)
SELECT m.id, g.id, 'OWNER'
FROM member m, "group" g
WHERE m.email = 'test@osdu.internal' 
AND g.email IN (
  'users@osdu.osdu.local',
  'users.datalake.ops@osdu.osdu.local',
  'users.datalake.admins@osdu.osdu.local',
  'service.legal.user@osdu.osdu.local',
  'service.legal.admin@osdu.osdu.local',
  'service.legal.editor@osdu.osdu.local'
)
ON CONFLICT (member_id, group_id) DO NOTHING;
```

---

## 2. Phân loại các thao tác

### 2.1 Cần Repo-first (GitOps)

| Item | File/Location | Priority |
|------|---------------|----------|
| Entitlements env vars | `k8s/osdu/core/base/entitlements.yaml` | HIGH |
| Legal env vars | `k8s/osdu/core/base/legal.yaml` | HIGH |
| DB init SQL scripts | `k8s/osdu/deps/base/initdb/` | MEDIUM |

### 2.2 Bootstrap (One-time setup)

| Item | Khi nào chạy | Tool |
|------|--------------|------|
| Partition properties | Sau khi partition service running | curl/script |
| Entitlements DB schema | Sau khi postgres ready, trước khi dùng entitlements | psql/Job |
| Legal DB schema | Sau khi postgres ready, trước khi dùng legal | psql/Job |
| Groups & user membership | Sau khi entitlements schema ready | psql/script |

### 2.3 Operational (Có thể cần lặp lại)

| Item | Trigger | Runbook |
|------|---------|---------|
| Add new user | Khi có user mới | `runbooks/add-osdu-user.md` |
| Add new group | Khi cần permission mới | `runbooks/add-osdu-group.md` |
| Update partition | Khi thay đổi config | `runbooks/update-partition.md` |
| Restart services | Sau khi thay đổi partition | kubectl rollout |

---

## 3. Scripts Bootstrap

### 3.1 Script khởi tạo Partition
File: `scripts/bootstrap/01-init-partition.sh`

### 3.2 Script khởi tạo Database Schemas
File: `scripts/bootstrap/02-init-db-schemas.sh`

### 3.3 Script khởi tạo Entitlements Data
File: `scripts/bootstrap/03-init-entitlements.sh`

---

## 4. Troubleshooting Guide

### 4.1 Lỗi "TenantInfo misconfiguration: X property not present"
**Nguyên nhân:** Partition thiếu property bắt buộc.
**Giải pháp:** Thêm property vào partition, restart service.

### 4.2 Lỗi "Expected BEGIN_ARRAY but was STRING"
**Nguyên nhân:** `crmAccountID` cần là JSON array string `["value"]`.
**Giải pháp:** Sửa partition property format.

### 4.3 Lỗi "relation X does not exist"
**Nguyên nhân:** Database schema chưa được tạo.
**Giải pháp:** Chạy SQL init scripts.

### 4.4 Lỗi "UnknownHostException: entitlements"
**Nguyên nhân:** Service URL default không đúng với cluster naming.
**Giải pháp:** Set env `ENTITLEMENTS_HOST`, `PARTITION_HOST`.

### 4.5 Lỗi "User is not authorized"
**Nguyên nhân:** User chưa có trong groups cần thiết.
**Giải pháp:** Add user vào groups trong entitlements database.

### 4.6 Lỗi "HV000028: Unexpected exception during isValid"
**Nguyên nhân:** Validation service cần fetch property từ partition nhưng fail.
**Giải pháp:** Kiểm tra logs DEBUG để xem đang resolve property gì, thêm vào partition.

---

## 5. Verification Commands
```bash
# 1. Test Entitlements
curl -s "http://osdu-entitlements:8080/api/entitlements/v2/groups" \
  -H "data-partition-id: osdu" \
  -H "Authorization: Bearer $TOKEN"

# 2. Test Legal - Create
curl -s -X POST "http://osdu-legal:8080/api/legal/v1/legaltags" \
  -H "Content-Type: application/json" \
  -H "data-partition-id: osdu" \
  -H "X-Forwarded-Proto: https" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name": "test-tag", "description": "Test", "properties": {...}}'

# 3. Test Legal - List
curl -s "http://osdu-legal:8080/api/legal/v1/legaltags" \
  -H "data-partition-id: osdu" \
  -H "X-Forwarded-Proto: https" \
  -H "Authorization: Bearer $TOKEN"

# 4. Test Schema
curl -s "http://osdu-schema:8080/api/schema-service/v1/info" \
  -H "data-partition-id: osdu" \
  -H "Authorization: Bearer $TOKEN"

# 5. Test Storage
curl -s "http://osdu-storage:8080/api/storage/v2/info" \
  -H "data-partition-id: osdu" \
  -H "Authorization: Bearer $TOKEN"
```
