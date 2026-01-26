# Step 25: Search Service - OpenSearch Proxy Fix

## Problem
OSDU Search service uses Elasticsearch 8.x Java client which:
1. Sends `Content-Type: application/vnd.elasticsearch+json; compatible-with=8`
2. Expects `X-Elastic-Product: Elasticsearch` header in response

OpenSearch 2.x (fork of ES 7.x) doesn't understand these ES 8.x protocols.

## Solution
Deploy Nginx proxy between OSDU services and OpenSearch:
- Rewrites ES 8.x Content-Type to standard `application/json`
- Injects `X-Elastic-Product: Elasticsearch` header into responses

## Configuration
- Proxy: `opensearch-proxy.osdu-data.svc.cluster.local:9200`
- Partition property: `elasticsearch.8.host` points to proxy
- Manifests: `k8s/osdu/deps/base/opensearch-proxy/`

## Commits
- `b7945c3` - Initial proxy deployment
- `04f671c` - Add X-Elastic-Product header
