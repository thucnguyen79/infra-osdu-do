# Step 31 — Secret Service

## Status: ✅ OPERATIONAL (CRUD + Enable/Disable verified)

## Image
`community.opengroup.org:5555/osdu/platform/security-and-compliance/secret/core-plus-secret-release:28061ab0`
Version: 0.28.3-SNAPSHOT

## Architecture
- **API**: port 8080, context path `/api/secret`
- **Actuator**: port 8081, health at `/health`
- **Storage backend**: Kubernetes Secrets (KsDriver) in namespace `osdu-core`
- **Auth**: Entitlements service via alias `http://entitlements:80`

## Key Fixes Applied

### 1. Dual-Port (8080 API + 8081 Actuator)
Probes target `8081/health`, Service targets `8080`.

### 2. Alias Services
Secret service hardcodes `http://entitlements` and `http://partition` (port 80).
Created ClusterIP alias services mapping port 80 → targetPort 8080.

### 3. RBAC for K8s Secrets
ServiceAccount `osdu-secret` with Role granting CRUD on K8s Secrets.

### 4. Partition Property `sd.ksd.k8s.namespace`
Required for KsDriver to know which namespace to store secrets.

### 5. DOMAIN=osdu.local (Critical!)
`@ConfigurationProperties` binds `domain` field from env `DOMAIN` (NOT `GROUP_ID`).
`getDomain(partitionId)` = `String.format("%s.%s", partitionId, DOMAIN)` = `osdu.osdu.local`.

### 6. ACL Regex: Groups Must Contain "secret"
`EMAIL_PATTERN` = `^[a-z0-9.]+secret[a-z0-9.]+@[A-Za-z0-9+_.-]{1,256}$`
Only `service.secret.*` groups are valid for ACLs.

### 7. Entitlements Groups Domain Fix
Groups created with wrong domain `@osdu.group` → fixed to `@osdu.osdu.local` via SQL.

## Environment Variables
| Variable | Value | Purpose |
|----------|-------|---------|
| DOMAIN | osdu.local | ACL domain validation |
| ENTITLEMENTS_API | http://osdu-entitlements:8080/api/entitlements/v2 | Auth |
| PARTITION_API | http://osdu-partition:8080/api/partition/v1 | Config |

## Known Limitation
List endpoint fails if non-OSDU K8s secrets exist in same namespace
(KsDriver iterates ALL secrets and fails parsing TLS certs).

## Smoke Test Results
| Operation | Method | Path | Status |
|-----------|--------|------|--------|
| Create | POST | /v2/secrets | 201 ✅ |
| Get | GET | /v2/secrets/{id} | 200 ✅ |
| Update | PUT | /v2/secrets/{id} | 202 ✅ |
| Enable | PATCH | /v2/secrets/{id}/enable | 202 ✅ |
| Disable | PATCH | /v2/secrets/{id}/disable | 202 ✅ |
| Delete | DELETE | /v2/secrets/{id} | 204 ✅ |
| List | GET | /v2/secrets/list | ⚠️ 404 |
| Health | GET | /v1/health | 200 ✅ |
| Info | GET | /v2/info | 200 ✅ |
