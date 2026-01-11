# OSDU Core Services Smoke Test - SUCCESS

## Date: 2026-01-11

## Status: ✅ ALL CORE SERVICES WORKING

### Services Tested
| Service | Endpoint | Status |
|---------|----------|--------|
| Entitlements | /api/entitlements/v2/groups | 200 OK |
| Legal | /api/legal/v1/legaltags | 200/201 OK |
| Schema | /api/schema-service/v1/info | 200 OK |
| Storage | /api/storage/v2/info | 200 OK |

## Key Fixes Applied

### 1. Partition Configuration
- `crmAccountID` must be JSON array: `["osdu-crm"]`
- Added `osm.postgres.datasource.*` properties
- Added `obm.minio.*` properties for object storage

### 2. Entitlements Database Schema
Created tables in `entitlements` database:
- `member` (with partition_id)
- `"group"` (with partition_id)  
- `member_to_group`
- `embedded_group` (parent_id, child_id)

### 3. Legal Database Schema
Created in `legal` database:
- Schema: `osdu`
- Table: `osdu."LegalTagOsm"` with `pk BIGSERIAL PRIMARY KEY`

### 4. Service Environment Variables
Legal service needs:
- `PARTITION_HOST=http://osdu-partition:8080`
- `ENTITLEMENTS_HOST=http://osdu-entitlements:8080`
- `OBM_MINIO_SECRET_KEY=<from Ceph secret>`

### 5. Entitlements Bootstrap
Created groups and added user `test@osdu.internal` to:
- users, users.datalake.ops, users.datalake.admins
- service.legal.user, service.legal.admin, service.legal.editor
