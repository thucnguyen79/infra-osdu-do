# OSDU Testing Quick Start Guide

## 📋 Tổng quan

Bộ scripts này giúp kiểm tra và test OSDU platform trên Kubernetes:

| Script | Mục đích |
|--------|----------|
| `01-preflight-checks.sh` | Kiểm tra tất cả services trước khi test |
| `02-test-scenarios.sh` | Test chức năng từng service |
| `03-well-known-issues.md` | Tài liệu các vấn đề đã biết & cách xử lý |

---

## 🚀 Cách sử dụng

### Bước 1: Copy scripts lên ToolServer01

```bash
# Tạo thư mục
ssh ops@ToolServer01 "mkdir -p /opt/infra-osdu-do/scripts/testing"

# Copy scripts
scp 01-preflight-checks.sh ops@ToolServer01:/opt/infra-osdu-do/scripts/testing/
scp 02-test-scenarios.sh ops@ToolServer01:/opt/infra-osdu-do/scripts/testing/
scp 03-well-known-issues.md ops@ToolServer01:/opt/infra-osdu-do/scripts/testing/

# SSH vào ToolServer
ssh ops@ToolServer01
cd /opt/infra-osdu-do/scripts/testing

# Chmod
chmod +x *.sh
```

### Bước 2: Chạy Pre-flight Checks

```bash
./01-preflight-checks.sh
```

**Expected output:**
- ✅ All nodes Ready
- ✅ All infrastructure services Running
- ✅ All OSDU services Running
- ✅ Network connectivity OK
- ✅ Access token acquired

**Nếu có FAIL:**
- Xem `03-well-known-issues.md` để troubleshoot
- Fix issues trước khi chạy tests

### Bước 3: Chạy Test Scenarios

```bash
# Chạy tất cả tests
./02-test-scenarios.sh all

# Hoặc chạy từng service
./02-test-scenarios.sh partition
./02-test-scenarios.sh entitlements
./02-test-scenarios.sh legal
./02-test-scenarios.sh schema
./02-test-scenarios.sh storage
./02-test-scenarios.sh file
./02-test-scenarios.sh search
./02-test-scenarios.sh indexer

# Chạy E2E test (quan trọng nhất)
./02-test-scenarios.sh e2e
```

---

## 📊 Test Suites Overview

### 1. Partition Service Tests
- List partitions
- Get partition details
- Verify critical properties

### 2. Entitlements Service Tests
- List groups
- Verify required groups exist
- Get user groups
- Create test group

### 3. Legal Service Tests
- Service info
- List legal tags
- Create legal tag
- Validate legal tag

### 4. Schema Service Tests
- Service info
- List schemas
- Create test schema

### 5. Storage Service Tests
- Service info
- Query records
- Create record
- Get record by ID

### 6. File Service Tests
- Service info
- Get upload URL

### 7. Search Service Tests
- Health check
- Search all records
- Search for specific record

### 8. Indexer Service Tests
- Actuator health
- Check subscriptions

### 9. E2E Data Flow Test
**Luồng test:**
```
Create Legal Tag → Create Record (Storage) → Wait for Indexing → Search for Record
```

Đây là test quan trọng nhất để verify toàn bộ data pipeline hoạt động.

---

## 🔍 Troubleshooting Quick Reference

### Common Issues & Fixes

| Vấn đề | Kiểm tra | Giải pháp |
|--------|----------|-----------|
| Token failed | Keycloak running? | Check Keycloak pod, user credentials |
| 403 Forbidden | User in groups? | Add user to entitlement groups |
| Search empty | Indexer running? | Wait 30s, check Indexer logs |
| SSL errors | Protocol config | Set `elasticsearch.8.protocol=http` |
| RabbitMQ 404 | Vhost issue | Create topology in vhost "" |

### Debug Commands

```bash
# Service logs
kubectl -n osdu-core logs deploy/osdu-<service> --tail=100

# Pod status
kubectl -n osdu-core get pods -o wide

# Events
kubectl -n osdu-core get events --sort-by='.lastTimestamp' | tail -20

# Connectivity test
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -v http://osdu-<service>:8080/
```

---

## ✅ Success Criteria

### Pre-flight Checks
- [ ] 0 FAILED checks
- [ ] All services Running (1/1)
- [ ] Access token acquired

### Functional Tests
- [ ] All 9 test suites PASSED
- [ ] E2E test PASSED (most important)

### E2E Test Success Message
```
╔═════════════════════════════════════════════════════╗
║  DATA FLOW VERIFIED:                                ║
║  Storage → RabbitMQ → Indexer → OpenSearch → Search ║
╚═════════════════════════════════════════════════════╝
```

---

## 📝 Test Results Template

```
Date: ____________
Tester: ____________
Environment: DigitalOcean / osdu-core

PRE-FLIGHT CHECKS
-----------------
[ ] Cluster nodes: ___ / ___ Ready
[ ] Infrastructure services: ___ / 7 Running
[ ] OSDU services: ___ / 8 Running
[ ] Token acquisition: PASS / FAIL

FUNCTIONAL TESTS
----------------
[ ] Partition:    PASS / FAIL  Notes: ____________
[ ] Entitlements: PASS / FAIL  Notes: ____________
[ ] Legal:        PASS / FAIL  Notes: ____________
[ ] Schema:       PASS / FAIL  Notes: ____________
[ ] Storage:      PASS / FAIL  Notes: ____________
[ ] File:         PASS / FAIL  Notes: ____________
[ ] Search:       PASS / FAIL  Notes: ____________
[ ] Indexer:      PASS / FAIL  Notes: ____________
[ ] E2E:          PASS / FAIL  Notes: ____________

SUMMARY
-------
Total Passed: ___ / 9
Total Failed: ___
Issues Found: ____________
```

---

## 🎯 Next Steps After Testing

1. **If all tests PASS:**
   - Document test results
   - Export RabbitMQ definitions to repo
   - Create seed scripts for reproducibility
   - Proceed to UAT

2. **If tests FAIL:**
   - Check `03-well-known-issues.md`
   - Collect logs
   - Fix issues
   - Re-run tests

---

## 📚 Related Documents

- `/mnt/project/04-deploy-checklist.md` - Deployment checklist
- `/mnt/project/Configuration.xlsx` - Server configuration
- `/mnt/project/Kế_hoạch_triển_khai_Kubernetes_và_OSDU.docx` - Deployment plan
