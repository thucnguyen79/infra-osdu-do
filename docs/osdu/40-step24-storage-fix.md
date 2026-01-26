# Step 24 - Storage Service Fix

## Date: 2026-01-25

## Overview
Fixed Storage service to successfully create and read OSDU records.

## Issues Encountered and Fixes

### Issue 1: Legal Service HTTP 307 Redirect
**Symptom:** Legal service redirecting HTTP → HTTPS even for internal calls
**Root Cause:** Spring Security channel security enabled by default
**Fix:** Added SSL disable env vars to Legal deployment:
- `SERVER_FORWARD_HEADERS_STRATEGY=framework`
- `SERVER_TOMCAT_PROTOCOL_HEADER=X-Forwarded-Proto`
- `SERVER_USE_FORWARD_HEADERS=true`
- `SECURITY_REQUIRE_HTTPS=false`
- `SECURITY_REQUIRE_SSL=false`
- etc.

**Files Modified:**
- `k8s/osdu/core/overlays/do-private/patches/patch-legal-all.yaml`

### Issue 2: Legal Service HTTP 500 - Table Not Found
**Symptom:** `relation "osdu.LegalTagOsm" does not exist`
**Root Cause:** 
1. OSM (Object Storage Model) uses `osm.postgres.datasource.url` which points to `storage` database
2. Legal service shares the same OSM datasource with Storage
3. `osdu` schema in `storage` database didn't have `LegalTagOsm` table

**Fix:** Created `LegalTagOsm` table in `storage.osdu` schema

### Issue 3: PostgreSQL search_path
**Symptom:** Queries to `osdu.*` tables failed even though tables existed
**Root Cause:** Role-level search_path for `osduadmin` was set to `dataecosystem, public` (not including `osdu`)
**Fix:** `ALTER ROLE osduadmin SET search_path TO osdu, dataecosystem, public`

### Issue 4: Missing S3 Bucket
**Symptom:** `NoSuchBucket` error for `osdu-poc-osdu-records`
**Root Cause:** Bucket not created during initial Ceph setup
**Fix:** Created bucket via minio client

## Bootstrap Scripts

### PostgreSQL Schema Bootstrap
```bash
kubectl -n osdu-data exec sts/osdu-postgres -- psql -U osduadmin -f - < scripts/osdu/bootstrap-postgres-osdu-schema.sql
```

### S3 Buckets Bootstrap
```bash
./scripts/osdu/bootstrap-s3-buckets.sh
```

## Verification

### Test Create Record
```bash
TOKEN=$($TOOLBOX curl -s -X POST "http://keycloak:80/realms/osdu/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=osdu-cli&username=test&password=Test@12345" | \
  grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

$TOOLBOX curl -s -w "\nHTTP: %{http_code}\n" \
    -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "data-partition-id: osdu" \
    -H "Content-Type: application/json" \
    -H "X-Forwarded-Proto: https" \
    "http://osdu-storage:8080/api/storage/v2/records" \
    -d '[{
        "id": "osdu:test:verify-$(date +%s)",
        "kind": "osdu:test:TestRecord:1.0.0",
        "acl": {
            "viewers": ["data.default.viewers@osdu.osdu.local"],
            "owners": ["data.default.owners@osdu.osdu.local"]
        },
        "legal": {
            "legaltags": ["osdu-step24-test"],
            "otherRelevantDataCountries": ["US"]
        },
        "data": {"name": "Verification test"}
    }]'
```

Expected: HTTP 201

### Test Read Record
```bash
$TOOLBOX curl -s \
    -H "Authorization: Bearer $TOKEN" \
    -H "data-partition-id: osdu" \
    "http://osdu-storage:8080/api/storage/v2/records/<record-id>"
```

Expected: HTTP 200 with record JSON

## Key Learnings

1. **OSDU Multi-Tenancy:** Schema name = `data-partition-id` header value
2. **OSM Shared Datasource:** All services use same `osm.postgres.datasource.url` (storage DB) for OSM tables
3. **PostgreSQL Precedence:** Role-level `search_path` overrides database-level
4. **Spring Security:** Multiple env vars needed to fully disable HTTPS redirect
5. **Bucket Naming:** Storage uses `{gcpProjectId}-osdu-records` pattern
