# Step 14 — Identity/OIDC: Keycloak (DO private)

## Mục tiêu
- Dựng Keycloak làm IdP OIDC cho OSDU POC.
- Expose qua ingress-nginx + TLS internal-ca: https://keycloak.internal

## Namespace/Host
- Namespace: osdu-identity
- Host: keycloak.internal
- Issuer: ClusterIssuer internal-ca
- StorageClass DB: do-block-storage-retain

## Secrets (out-of-band)
- keycloak-db-secret: POSTGRES_DB/USER/PASSWORD
- keycloak-admin-secret: KEYCLOAK_ADMIN/KEYCLOAK_ADMIN_PASSWORD

## Verify
- Pods running: keycloak-db, keycloak
- Certificate READY=True: keycloak-internal-tls
- Ingress host ok
- curl HTTP 308 -> HTTPS
- curl HTTPS verify bằng internal-root-ca.crt OK
