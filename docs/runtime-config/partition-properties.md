# Partition Properties (Runtime Configuration)

## Lý do không thể Repo-first
Partition properties được lưu trong PostgreSQL database, là runtime configuration của OSDU platform.
Không thể quản lý bằng GitOps vì:
- Stored trong DB, không phải K8s manifest
- Được tạo/update qua Partition Service API
- Có thể chứa sensitive data (credentials)

## Cách ghi nhận
1. Export bằng API hoặc psql query
2. Lưu vào `docs/runtime-config/` (masked sensitive data)
3. Document các properties required

## Properties hiện tại (osdu partition)
Xem file: `docs/runtime-config/osdu-partition-properties.txt`

## Cách recreate
```bash
# Dùng Partition API để tạo lại properties
curl -X PATCH "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @docs/runtime-config/osdu-partition-payload.json
```
