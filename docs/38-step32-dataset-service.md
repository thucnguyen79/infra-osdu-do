# Step 32 — Dataset Service + File/Dataset DMS Integration

## Mục tiêu

Triển khai Dataset service, cấu hình DMS handler mapping tới File service, và đảm bảo luồng `storageInstructions` hoạt động end-to-end (Dataset → File → Ceph S3).

## Image

```
community.opengroup.org:5555/osdu/platform/system/dataset/core-plus-dataset-release:4cae824d
```

## Các bước thực hiện

### 1. Deploy Dataset service
- Tạo `k8s/osdu/core/base/services/dataset/dataset-deploy.yaml` + `dataset-svc.yaml`
- Thêm vào `kustomization.yaml`
- Tạo database `dataset` trong PostgreSQL
- Commit/Push → ArgoCD sync

### 2. Tạo Entitlements groups cho Dataset
Dataset service tự động tạo groups nhưng sai domain (`@osdu.group` thay vì `@osdu.osdu.local`).

**Fix:** Cập nhật SQL domain cho groups `service.dataset.{admin,editor,user}`:
```sql
UPDATE public."group" SET email = REPLACE(email, '@osdu.group', '@osdu.osdu.local')
  WHERE email LIKE 'service.dataset%@osdu.group';
```

**Quan trọng — Plural groups:** File DMS API (`FileDmsApi`) sử dụng `@PreAuthorize` annotation yêu cầu:
- `service.dataset.editors` (có **s**) cho write operations
- `service.dataset.viewers` (có **s**) cho read operations

Các groups này cũng bị tạo tự động với sai domain → cần fix SQL tương tự + thêm membership.

### 3. DMS Handler Registration (OSM Table)
Dataset service dùng `osm.postgres.*` partition properties (trỏ tới DB `schema`, schema `public`).

Tạo table `DmsServiceProperties` trong DB `schema`:
```sql
CREATE TABLE public."DmsServiceProperties"(
    id text PRIMARY KEY,
    pk bigint GENERATED ALWAYS AS IDENTITY,
    data jsonb NOT NULL,
    CONSTRAINT DmsServiceProperties_id UNIQUE (id)
);
```

Seed DMS handlers:
```sql
INSERT INTO public."DmsServiceProperties"(id, data) VALUES
  ('dataset--File.*', '{"datasetKind":"dataset--File.*","isStorageAllowed":true,"dmsServiceBaseUrl":"http://osdu-file:8080/api/file/v2/files","isStagingLocationSupported":true}'),
  ('dataset--FileCollection.*', '{"datasetKind":"dataset--FileCollection.*","isStorageAllowed":true,"dmsServiceBaseUrl":"http://osdu-file:8080/api/file/v2/file-collections","isStagingLocationSupported":true}');
```

Tạo table `DeletedDataset` trong DB `schema`, schema `osdu`:
```sql
CREATE TABLE osdu."DeletedDataset"(
    id text PRIMARY KEY,
    pk bigint GENERATED ALWAYS AS IDENTITY,
    data jsonb NOT NULL,
    CONSTRAINT "DeletedDataset_id" UNIQUE (id)
);
```

### 4. S3 Buckets cho File service
File service cần 2 buckets trong Ceph RGW:
```bash
aws s3 mb s3://osdu-poc-osdu-staging-area --endpoint-url $CEPH_ENDPOINT
aws s3 mb s3://osdu-poc-osdu-file-persistent-area --endpoint-url $CEPH_ENDPOINT
```

### 5. File service env vars bổ sung
```yaml
- name: SEARCH_QUERY_RECORD_HOST
  value: "http://osdu-search:8080/api/search/v2/query"
```

## Issues & Root Causes

### Issue 1: 403 Forbidden — Entitlements groups sai domain
- **Nguyên nhân:** Services auto-create groups với `@osdu.group` thay vì `@osdu.osdu.local`
- **Fix:** SQL UPDATE domain + INSERT membership + Redis FLUSHALL
- **Pattern lặp lại:** Secret (Step 31), Dataset (Step 32) — cần chú ý cho mọi service mới

### Issue 2: 500 Internal Server Error — Missing OSM table
- **Nguyên nhân:** Dataset service dùng `osm.postgres.*` (generic) thay vì `osm.dataset.*`
- **Fix:** Tạo table `DmsServiceProperties` trong DB `schema`, schema `public`

### Issue 3: 404 / DMS handler not found
- **Nguyên nhân:** Chưa seed DMS mapping data
- **Fix:** INSERT vào `DmsServiceProperties` table

### Issue 4: 401 Unauthorized — File service authorization
- **Nguyên nhân:** `FileDmsApi` annotation `@PreAuthorize("@authorizationFilter.hasPermission('service.dataset.editors')")` yêu cầu group **plural** (`editors`/`viewers`)
- **Phát hiện:** Decompile bytecode bằng `javap` để đọc `@PreAuthorize` annotation
- **Fix:** Tạo groups `service.dataset.editors` + `service.dataset.viewers` (fix domain + add membership)
- **Lưu ý:** Groups phải tạo qua Entitlements API hoặc fix SQL + flush Redis. Tạo SQL trực tiếp → cần flush Redis cache

### Issue 5: 500 — NoSuchBucket
- **Nguyên nhân:** Bucket `osdu-poc-osdu-staging-area` chưa tồn tại trong Ceph RGW
- **Fix:** Tạo 2 buckets: `osdu-poc-osdu-staging-area` + `osdu-poc-osdu-file-persistent-area`

## Bài học rút ra

1. **Entitlements groups domain:** Mọi OSDU service đều auto-create groups với sai domain. Cần fix SQL pattern cho mỗi service mới.
2. **Plural vs singular groups:** Một số API endpoint yêu cầu group dạng plural (`editors` thay vì `editor`). Cần kiểm tra `@PreAuthorize` annotations.
3. **Groups tạo qua SQL vs API:** Nếu tạo qua SQL trực tiếp, entitlements service không nhận (do cache). Cần Redis FLUSHALL.
4. **OSM table naming:** Mỗi service có convention riêng. Dataset dùng `osm.postgres.*` (generic) → table tạo trong DB `schema`.
5. **Bytecode analysis:** `javap -p -verbose` là công cụ hữu ích để xác định authorization requirements khi không có source code.

## Kết quả cuối

```
File storageInstructions:   HTTP 200 (signedUrl trả về OK)
Dataset storageInstructions: HTTP 200 (forwarded tới File service OK)
```

## Artifacts
- `artifacts/step32-dataset/` — evidence output
