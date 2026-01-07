# Partition "osdu" Properties

## Required Properties for OSDU Core Plus M25

Đã seed partition "osdu" với các properties sau:

### Datasource Properties (per service)
| Property | Sensitive | Value |
|----------|-----------|-------|
| `{service}.datasource.url` | false | `jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/{service}` |
| `{service}.datasource.username` | false | `osduadmin` |
| `{service}.datasource.password` | true | `{SERVICE}_DB_PASSWORD` (env var name) |
| `{service}.datasource.schema` | false | `public` |

Services: entitlements, legal, storage, schema, file

### Infrastructure Properties
| Property | Sensitive | Value |
|----------|-----------|-------|
| `elastic-endpoint` | true | `http://osdu-opensearch.osdu-data:9200` |
| `elastic-username` | true | `admin` |
| `elastic-password` | true | `admin` |
| `storage-account-name` | false | `osdu` |
| `redis-database` | false | `4` |
| `compliance-ruleset` | false | `shared` |

### Sensitive Property Pattern
When `sensitive: true`, the value is interpreted as an **environment variable name**.
The actual secret value must be set as an env var in the deployment.

Example:
```yaml
# In partition:
"entitlements.datasource.password": {"sensitive": true, "value": "ENTITLEMENTS_DB_PASSWORD"}

# In deployment:
env:
  - name: ENTITLEMENTS_DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: osdu-postgres-secret
        key: POSTGRES_PASSWORD
```

## Seed Command
```bash
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s -X POST \
  "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -H "Content-Type: application/json" \
  -d '{"properties": {...}}'
```
