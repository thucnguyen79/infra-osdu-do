
## Step 31 — Secret Service
- [x] Image: core-plus-secret-release:28061ab0 (v0.28.3-SNAPSHOT)
- [x] Dual-port: 8080 (API) + 8081 (Actuator/Health)
- [x] ServiceAccount + RBAC (K8s Secrets CRUD)
- [x] Alias services: entitlements/partition (ClusterIP 80→8080)
- [x] Partition: sd.ksd.k8s.namespace=osdu-core
- [x] DOMAIN=osdu.local (ConfigurationProperties binding)
- [x] Entitlements groups: service.secret.{admin,user,editor}@osdu.osdu.local
- [x] Smoke test: Create/Get/Update/Enable/Disable/Delete ALL PASS
- [ ] List: known limitation (non-OSDU K8s secrets in namespace cause 404)
- [x] Evidence: artifacts/step31-secret/
- [x] Docs: docs/37-step31-secret-service.md
