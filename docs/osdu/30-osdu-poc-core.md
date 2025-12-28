# Step 13 — OSDU POC Core: Freeze distro/version + dependency matrix

## 1) Mục tiêu
- Chốt distro/version để các bước Identity/Deps/Core không đổi liên tục.
- Chốt dependency tối thiểu cho POC.

## 2) Distro/Version đề xuất (POC)
- Milestone baseline: M25 (Release 0.28)
- Ghi chú: tránh dùng preview (M26/0.29) cho POC đầu tiên.

## 3) Dependency tối thiểu (POC)
1. Identity/OIDC: Keycloak (hoặc IdP sẵn có)
2. Database: PostgreSQL
3. Search: OpenSearch/Elasticsearch
4. Object Storage: S3-compatible (MinIO) hoặc object storage managed
5. Queue/Event: Kafka (tối thiểu)
6. Ingress/TLS: ingress-nginx + cert-manager (internal-ca)
7. GitOps: ArgoCD App-of-Apps

## 4) Naming/Namespace đề xuất
- osdu
- osdu-identity
- osdu-data
- osdu-core
