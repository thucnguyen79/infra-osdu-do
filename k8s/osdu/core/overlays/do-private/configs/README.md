# OSDU Partition Configuration

## partition-properties.json

This file contains the template for OSDU partition properties.

### Usage
1. Copy this template
2. Replace placeholder values with actual secrets
3. Apply via Partition API or seed job

### Important Notes

#### S3 Credentials (sensitive=false)
Schema Service requires `sensitive: false` for S3 credentials:
```json
"obm.minio.accessKey": {"sensitive": false, "value": "ACTUAL_KEY"}
```

If `sensitive: true`, Schema Service will look for an environment variable 
named with the value (e.g., `ACTUAL_KEY`) instead of using it directly.

#### Schema Bucket
Required for Schema Service to store schema JSON files:
- `system.schema.bucket.name`: osdu-poc-osdu-schema
- `obm.minio.schema.bucket`: osdu-poc-osdu-schema

### Getting Actual Values
```bash
# S3 credentials
kubectl -n rook-ceph get secret rook-ceph-object-user-osdu-store-osdu-s3-user \
  -o jsonpath='{.data.AccessKey}' | base64 -d

kubectl -n rook-ceph get secret rook-ceph-object-user-osdu-store-osdu-s3-user \
  -o jsonpath='{.data.SecretKey}' | base64 -d

# RabbitMQ password
kubectl -n osdu-data get secret osdu-rabbitmq-secret \
  -o jsonpath='{.data.RABBITMQ_PASSWORD}' | base64 -d

# Postgres password
kubectl -n osdu-data get secret osdu-postgres-secret \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
```
