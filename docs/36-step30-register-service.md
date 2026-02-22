# Step 30 — Register Service Deployment

## Date: 2026-02-22
## Status: ✅ COMPLETED

## Image
`community.opengroup.org:5555/osdu/platform/system/register/core-plus-register-release:9ce538e7`

## Key Findings

### Health Probe
- Actuator port: **8081** (not 8080)
- Actuator base path: empty → health at `/health` (not `/actuator/health`)

### Database — OSM Table Pattern (CRITICAL LEARNING)
Register uses **generic OSM properties** `osm.postgres.datasource.*` → `schema` database.

| Service   | Partition prefix                     | Database  | Schema         |
|-----------|--------------------------------------|-----------|----------------|
| Storage   | `osm.storage.postgres.datasource.*`  | storage   | osdu           |
| Legal     | `osm.legal.postgres.datasource.*`    | legal     | osdu           |
| Schema    | `osm.schema.postgres.datasource.*`   | schema    | dataecosystem  |
| Register  | `osm.postgres.datasource.*` (generic)| schema    | osdu           |

OSM table structure (all services):
```sql
CREATE TABLE <schema>."<TableName>" (
    pk BIGSERIAL PRIMARY KEY,
    id TEXT NOT NULL UNIQUE,
    data JSONB NOT NULL
);
```

Register tables (in `schema` DB, `osdu` schema):
- `osdu."SUBSCRIPTION"`, `osdu."ACTION"`, `osdu."DDL"`

### Sensitive Partition Properties
`"sensitive": true` → value is **env var name**, resolved from pod environment.

## Verification
```
GET /api/register/v1/subscriptions → HTTP 200 []
```
