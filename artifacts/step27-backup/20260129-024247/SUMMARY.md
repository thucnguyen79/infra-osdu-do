# Step 27 Runtime Configuration Backup

## Contents

| File | Description |
|------|-------------|
| partition-properties.json | All OSDU partition properties (CRITICAL) |
| env-*.txt | Environment variables for each service |
| configmaps-osdu-core.yaml | All ConfigMaps in osdu-core namespace |
| s3-credentials.txt | S3 access credentials (DO NOT COMMIT!) |
| s3-buckets.txt | List of S3 buckets |
| opensearch-indices.txt | OpenSearch indices list |
| opensearch-template.json | Index template for osdu-* |
| mapping-*.json | Index mappings |
| rabbitmq-queues.txt | RabbitMQ queue list |
| rabbitmq-exchanges.txt | RabbitMQ exchange list |
| secrets-*.txt | Secret names (not values) |
| db-schema-reference.txt | Database reference data |
| java-tool-options.txt | JAVA_TOOL_OPTIONS for each service |

## Key Configurations Changed in Step 27

### Partition Properties
- `obm.minio.accessKey`: sensitive=false (CRITICAL for Schema Service)
- `obm.minio.secretKey`: sensitive=false
- `obm.minio.schema.bucket`: osdu-poc-osdu-schema
- `system.schema.bucket.name`: osdu-poc-osdu-schema
- `storage.s3.accessKeyId`: sensitive=false
- `storage.s3.secretAccessKey`: sensitive=false
- `oqm.s3.accessKeyId`: sensitive=false
- `oqm.s3.secretAccessKey`: sensitive=false

### Indexer Environment
- `SCHEMA_HOST`: http://osdu-schema:8080/api/schema-service/v1/schema

### S3 Buckets Created
- osdu-poc-osdu-schema (for Schema Service)

### OpenSearch
- Index template: osdu-template (workaround for flattened type)
- Pre-created indices with compatible mapping

## Restore Procedure

1. Restore partition properties:
```bash
   curl -X PUT "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d @partition-properties.json
```

2. Recreate S3 bucket if needed:
```bash
   python3 -c "
   import boto3
   s3 = boto3.client('s3', endpoint_url='...', ...)
   s3.create_bucket(Bucket='osdu-poc-osdu-schema')
   "
```

3. Recreate OpenSearch indices:
```bash
   ./scripts/create-osdu-index.sh osdu:wks:master-data--Well:1.0.0
```

