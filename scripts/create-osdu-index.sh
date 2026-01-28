#!/bin/bash
# Usage: ./create-osdu-index.sh <kind>
# Example: ./create-osdu-index.sh osdu:wks:master-data--Well:1.0.0

KIND=$1
if [ -z "$KIND" ]; then
    echo "Usage: $0 <kind>"
    echo "Example: $0 osdu:wks:master-data--Well:1.0.0"
    exit 1
fi

# Convert kind to index name (lowercase, replace : with -)
INDEX_NAME=$(echo "$KIND" | tr '[:upper:]' '[:lower:]' | sed 's/:/-/g')

TOOLBOX="kubectl -n osdu-core exec deploy/osdu-toolbox --"

echo "Creating index: $INDEX_NAME for kind: $KIND"

$TOOLBOX curl -s -X PUT -u admin:admin \
  -H "Content-Type: application/json" \
  "http://osdu-opensearch.osdu-data:9200/$INDEX_NAME" \
  -d '{
  "settings": {"number_of_shards": 1, "number_of_replicas": 1},
  "mappings": {
    "properties": {
      "id": {"type": "keyword"},
      "kind": {"type": "keyword"},
      "namespace": {"type": "keyword"},
      "type": {"type": "keyword"},
      "version": {"type": "long"},
      "acl": {"properties": {"viewers": {"type": "keyword"}, "owners": {"type": "keyword"}}},
      "legal": {"properties": {"legaltags": {"type": "keyword"}, "otherRelevantDataCountries": {"type": "keyword"}}},
      "tags": {"type": "object", "enabled": false},
      "data": {"type": "object", "dynamic": true},
      "index": {"properties": {"statusCode": {"type": "integer"}, "lastUpdateTime": {"type": "date"}, "trace": {"type": "text"}}},
      "authority": {"type": "keyword"},
      "source": {"type": "keyword"},
      "createUser": {"type": "keyword"},
      "createTime": {"type": "date"},
      "modifyUser": {"type": "keyword"},
      "modifyTime": {"type": "date"},
      "x-acl": {"type": "keyword"}
    }
  }
}'

echo ""
echo "Done!"
