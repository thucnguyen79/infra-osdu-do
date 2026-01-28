# Step 27: Known Issues & Workarounds

## 1. OpenSearch Flattened Type Incompatibility

### Issue
OSDU Indexer is built for Elasticsearch and uses `flattened` type for `tags` field.
OpenSearch 7.x does not support `flattened` type.

### Error
```
Failed to parse mapping [_doc]: No handler for type [flattened] declared on field [tags]
```

### Workaround
Pre-create indices with compatible mapping before using new kinds:
1. Index Template: `osdu-template` (applied to `osdu-*` indices)
2. Pre-created indices: Via `opensearch-init-job.yaml`
3. Manual script: `scripts/create-osdu-index.sh`

### Long-term Solutions
- Upgrade to OpenSearch 2.7+ (has `flat_object` type)
- Switch to Elasticsearch
- Fork OSDU Indexer (not recommended)

## 2. S3 Credentials Sensitive Flag

### Issue
Schema Service expects S3 credentials as values, not environment variable names.

### Fix
Partition properties must have `sensitive: false` for S3 credentials:
```json
"obm.minio.accessKey": {"sensitive": false, "value": "ACTUAL_KEY"}
```

## 3. Schema Bucket Required

### Issue
Schema Service requires S3 bucket `osdu-poc-osdu-schema` to store schema JSON files.

### Fix
- Created via ObjectBucketClaim: `k8s/osdu/storage/base/schema-bucket-obc.yaml`
- Or manually via boto3/aws-cli

## 4. Partition Properties

### Important Properties
| Property | Value | Notes |
|----------|-------|-------|
| `system.schema.bucket.name` | osdu-poc-osdu-schema | Schema JSON storage |
| `obm.minio.schema.bucket` | osdu-poc-osdu-schema | Alternative property |
| `obm.minio.accessKey` | (actual key) | sensitive=false |
| `obm.minio.secretKey` | (actual key) | sensitive=false |

## 5. Index Template Limitation

Index Template only applies when:
- Index is auto-created (by indexing a document)
- Index is created WITHOUT explicit mapping

Index Template does NOT apply when:
- Request includes explicit mapping (which Indexer always does)

Therefore, we must pre-create indices before Indexer tries to create them.
