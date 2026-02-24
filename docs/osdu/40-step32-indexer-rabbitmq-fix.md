# Step 32 – Indexer RabbitMQ Fix

## Problem
Indexer pod CrashLoopBackOff with multiple root causes.

## Root Causes & Fixes (in order)

### 1. Empty vhost (`vhost  not found`)
**Cause:** OQM plugin reads `oqm.rabbitmq.amqp.path` from partition properties
and uses it as AMQP URI path component. Value `/` = empty vhost in AMQP URI.
**Fix:** Set `oqm.rabbitmq.amqp.path` = `/%2f` (URI-encoded `/` vhost).

### 2. Spring 5/6 `NoSuchMethodError` on Admin API 404
**Cause:** OQM's shaded RabbitMQ HTTP client compiled against Spring 5
(`HttpClientErrorException.getStatusCode()` returns `HttpStatus`).
Spring 6 changed return type to `HttpStatusCode`. When Admin API returns
404 for a missing exchange, the error handler crashes.
**Fix:** Pre-create ALL exchanges/queues/bindings the indexer expects,
so Admin API never returns 404.

### 3. Missing exchanges/queues
Indexer requires these topic→subscription pairs:
| Topic Exchange | Subscription Exchange+Queue |
|---|---|
| records-changed | indexer-records-changed |
| legaltags-changed | indexer-legaltags-changed |
| schema-changed | indexer-schema-changed |
| reprocess | indexer-reprocess |
| reindex | indexer-reindex |
| statusChanged | indexer-statusChanged |

Each needs: exchange (topic type) + queue + binding (routing_key=#).
Plus `osdu.` prefixed variants.

## Commands Used
```bash
# Fix partition property
curl -X PATCH .../api/partition/v1/partitions/osdu \
  -d '{"properties":{"oqm.rabbitmq.amqp.path":{"sensitive":false,"value":"/%2f"}}}'

# Create exchanges + queues (example for one topic)
rabbitmqadmin declare exchange name="schema-changed" type=topic durable=true
rabbitmqadmin declare exchange name="indexer-schema-changed" type=topic durable=true
rabbitmqadmin declare queue name="indexer-schema-changed" durable=true
rabbitmqadmin declare binding source="schema-changed" \
  destination="indexer-schema-changed" destination_type="queue" routing_key="#"
# Repeat for osdu.* prefixed variants
```

## Verification
- Indexer pod: 1/1 Running (no restarts)
- RabbitMQ consumers: 10 on records-changed, 1 on schema-changed, 10 on reindex
- E2E test: 20/20 PASSED, search returns 19+ Well records

## Lessons Learned
1. AMQP URI vhost encoding: `/` as path = empty vhost; need `/%2f` for default vhost
2. Spring 5→6 breaking change: `getStatusCode()` return type changed
3. OQM treats subscriptions as exchange+queue+binding triads
4. Pre-creating all RabbitMQ topology avoids Spring incompatibility crash
5. Bytecode analysis (`javap`) essential for debugging closed-source plugins
