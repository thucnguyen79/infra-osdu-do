# Issue: Notification Service — Spring 6 Incompatibility (All Core-Plus Images)

## Status: BLOCKED (upstream bug) — POC workaround: replicas=0

## Error
```
Caused by: java.lang.NoSuchMethodError:
  'org.springframework.http.HttpStatus
   org.springframework.web.client.HttpClientErrorException.getStatusCode()'
```

## Root Cause
All 5 available `core-plus-notification-release` images bundle a **shaded
rabbitmq-http-client** compiled against Spring Framework 5 (`getStatusCode()`
returns `HttpStatus`), but the notification jar uses **Spring Boot 3.3.5**
(Spring Framework 6, where `getStatusCode()` returns `HttpStatusCode`).

The crash occurs at startup in `OqmSubscriberManager.postConstruct()` →
`MqOqmDriver.getSubscription()` → `Client.getForObjectReturningNullOn404()`.

## Images Tested (all fail identically)
| Tag        | Size      | Published     |
|------------|-----------|---------------|
| a32d940f   | 232.79 MiB| 6 months ago  |
| 220801ac   | 230.55 MiB| 6 months ago  |
| b9c48d5b   | 230.46 MiB| 9 months ago  |
| c2b6fb0f   | 230.55 MiB| 6 months ago  |
| cd835e8a   | 232.79 MiB| 6 months ago  |

## Pre-requisites Completed (ready for when image is fixed)
- [x] Partition properties: `osm.notification.postgres.datasource.*` (schema=osdu)
- [x] DB: `notification` database with `osdu."SUBSCRIPTION"` table (pk/id/data)
- [x] Env vars: `OQM_RABBITMQ_AMQP_PASSWORD`, `OQM_RABBITMQ_ADMIN_PASSWORD`
- [x] RabbitMQ creds: username=osdu, password=osdu123
- [x] Deployment manifest ready: `k8s/osdu/core/base/services/notification/`

## POC Decision
Notification is **not critical** for POC/UAT. Core OSDU workflow
(ingest → storage → search) functions without it. Scale to 0 and revisit
when upstream publishes a fixed image.

## Resolution Path
1. Monitor OSDU Community GitLab for new `core-plus-notification-release` tags
2. When new image available: update tag, set `replicas: 1`, push, sync ArgoCD
3. Alternatively: build custom image with updated `rabbitmq-http-client` shaded jar
