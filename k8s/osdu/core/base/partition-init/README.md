# Partition Init Properties

This directory contains partition properties that need to be applied via the Partition API.

## Elasticsearch/OpenSearch Properties

File: `elasticsearch-properties-payload.json`

These properties configure OSDU services to connect to OpenSearch via the nginx proxy.

### Why Proxy?
OSDU Search service uses Elasticsearch 8.x Java client which is not compatible with OpenSearch 2.x.
The `opensearch-proxy` in `osdu-data` namespace:
- Rewrites ES8 Content-Type header to standard JSON
- Adds `X-Elastic-Product: Elasticsearch` header to responses

### How to Apply
```bash
# 1. Get token
TOOLBOX="kubectl -n osdu-core exec deploy/osdu-toolbox --"
TOKEN=$($TOOLBOX curl -s -X POST "http://keycloak.osdu-identity.svc.cluster.local/realms/osdu/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=osdu-cli&username=test&password=Test@12345" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

# 2. Apply properties
$TOOLBOX curl -s -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "data-partition-id: osdu" \
  "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -d '@/path/to/elasticsearch-properties-payload.json'

# Or inline:
$TOOLBOX curl -s -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "data-partition-id: osdu" \
  "http://osdu-partition:8080/api/partition/v1/partitions/osdu" \
  -d '{
    "properties": {
      "elasticsearch.8.host": {"sensitive": false, "value": "opensearch-proxy.osdu-data.svc.cluster.local"},
      "elasticsearch.8.port": {"sensitive": false, "value": "9200"},
      "elasticsearch.8.https": {"sensitive": false, "value": "false"},
      "elasticsearch.8.tls": {"sensitive": false, "value": "false"}
    }
  }'

# 3. Flush Redis cache
kubectl -n osdu-data exec deploy/osdu-redis -- redis-cli FLUSHALL

# 4. Restart affected services
kubectl -n osdu-core rollout restart deploy/osdu-search
kubectl -n osdu-core rollout restart deploy/osdu-indexer
```

### Verification
```bash
# Check properties were applied
$TOOLBOX curl -s -H "Authorization: Bearer $TOKEN" -H "data-partition-id: osdu" \
  "http://osdu-partition:8080/api/partition/v1/partitions/osdu" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'{k}: {v.get(\"value\",\"N/A\")}') for k,v in sorted(d.get('properties',{}).items()) if 'elastic' in k.lower()]"
```

## Future: Auto-Init Job

TODO: Create a Kubernetes Job that runs on partition creation to auto-apply these properties.
