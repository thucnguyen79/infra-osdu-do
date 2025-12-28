STEP 13: OSDU POC - Version Freeze & GitOps Bootstrap
Mục tiêu:
Chốt phiên bản (Version Freeze): Xác định rõ Distro OSDU (M25) và các Dependency (Postgres, Keycloak...) để tránh thay đổi liên tục trong quá trình POC.

Dựng khung GitOps (App-of-Apps): Thiết lập cấu trúc Argo CD Project và các Application con (Identity, Deps, Core) ở dạng "Stub" (vỏ rỗng) để đảm bảo luồng CD hoạt động trước khi đổ code thật vào.

Điều kiện tiên quyết:
Argo CD đã cấu hình Repo URL dạng SSH (git@github.com:...) [Đã hoàn thành ở Step 13.0].
1. Chốt Distro/Version & Dependency (13.1)
Tạo tài liệu lưu trữ thông tin phiên bản để làm chuẩn cho cả team.
Lệnh thực hiện:
cd /opt/infra-osdu-do
mkdir -p docs/osdu artifacts/step13-osdu

cat > docs/osdu/30-osdu-poc-core.md <<'EOF'
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
EOF

# Commit tài liệu vào Git
git add docs/osdu/30-osdu-poc-core.md
git commit -m "Step 13: freeze OSDU distro/version + dependency matrix (POC)"

2. Bootstrap "App-of-Apps" cho OSDU (13.2)
2.1. Tạo AppProject (Phân quyền & Quản lý Namespace)
Tạo Project osdu trong Argo CD để quản lý riêng biệt các nhóm ứng dụng OSDU, tách biệt với nhóm default hay observability
mkdir -p k8s/gitops/projects

cat > k8s/gitops/projects/osdu.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: osdu
  namespace: argocd
spec:
  description: OSDU POC apps
  sourceRepos:
  - '*'
  destinations:
  - namespace: argocd
    server: https://kubernetes.default.svc
  - namespace: osdu
    server: https://kubernetes.default.svc
  - namespace: osdu-identity
    server: https://kubernetes.default.svc
  - namespace: osdu-data
    server: https://kubernetes.default.svc
  - namespace: osdu-core
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
EOF

2.2. Tạo cấu trúc thư mục & Stub Applications
Chúng ta sẽ tạo các thư mục thật nhưng bên trong chỉ chứa ConfigMap đơn giản (Stub) để Argo CD có thể sync thành công. Sau này (Step 14-17), chúng ta sẽ thay thế các file này bằng Helm Chart thật.
Lưu ý: URL Repo đã được fix cứng thành SSH: git@github.com:thucnguyen79/infra-osdu-do.git
A) Identity Stub (Cho Keycloak sau này)
# Tạo cấu trúc thư mục
mkdir -p k8s/osdu/identity/overlays/do-private
mkdir -p k8s/gitops/apps/osdu

# Tạo file Kustomization & Resource Stub
cat > k8s/osdu/identity/overlays/do-private/kustomization.yaml <<'EOF'
resources:
  - namespace.yaml
  - marker-configmap.yaml
EOF

cat > k8s/osdu/identity/overlays/do-private/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: osdu-identity
EOF

cat > k8s/osdu/identity/overlays/do-private/marker-configmap.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: osdu-identity-stub
  namespace: osdu-identity
data:
  note: "Step 14 will replace this stub with Keycloak manifests"
EOF

# Tạo Argo CD Application Definition
cat > k8s/gitops/apps/osdu/10-identity.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: osdu-identity
  namespace: argocd
spec:
  project: osdu
  source:
    repoURL: git@github.com:thucnguyen79/infra-osdu-do.git
    targetRevision: main
    path: k8s/osdu/identity/overlays/do-private
  destination:
    server: https://kubernetes.default.svc
    namespace: osdu-identity
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
B) Dependencies Stub (Cho Postgres, MinIO, Elastic...)
Bash

mkdir -p k8s/osdu/deps/overlays/do-private

cat > k8s/osdu/deps/overlays/do-private/kustomization.yaml <<'EOF'
resources:
  - namespace.yaml
  - marker-configmap.yaml
EOF

cat > k8s/osdu/deps/overlays/do-private/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: osdu-data
EOF

cat > k8s/osdu/deps/overlays/do-private/marker-configmap.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: osdu-deps-stub
  namespace: osdu-data
data:
  note: "Step 15 will replace this stub with Postgres/OpenSearch/MinIO/Kafka"
EOF

cat > k8s/gitops/apps/osdu/20-deps.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: osdu-deps
  namespace: argocd
spec:
  project: osdu
  source:
    repoURL: git@github.com:thucnguyen79/infra-osdu-do.git
    targetRevision: main
    path: k8s/osdu/deps/overlays/do-private
  destination:
    server: https://kubernetes.default.svc
    namespace: osdu-data
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
C) Core Stub (Cho Partition, Legal, Entitlements...)
Bash

mkdir -p k8s/osdu/core/overlays/do-private

cat > k8s/osdu/core/overlays/do-private/kustomization.yaml <<'EOF'
resources:
  - namespace.yaml
  - marker-configmap.yaml
EOF

cat > k8s/osdu/core/overlays/do-private/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: osdu-core
EOF

cat > k8s/osdu/core/overlays/do-private/marker-configmap.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: osdu-core-stub
  namespace: osdu-core
data:
  note: "Step 16 will replace this stub with OSDU core services"
EOF

cat > k8s/gitops/apps/osdu/30-core.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: osdu-core
  namespace: argocd
spec:
  project: osdu
  source:
    repoURL: git@github.com:thucnguyen79/infra-osdu-do.git
    targetRevision: main
    path: k8s/osdu/core/overlays/do-private
  destination:
    server: https://kubernetes.default.svc
    namespace: osdu-core
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
2.3. Tạo "App-of-Apps" Parent cho OSDU
Đây là Application cha, chịu trách nhiệm quản lý 3 App con vừa tạo ở trên.


mkdir -p k8s/gitops/app-of-apps

cat > k8s/gitops/app-of-apps/osdu.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps-osdu
  namespace: argocd
spec:
  project: osdu
  source:
    repoURL: git@github.com:thucnguyen79/infra-osdu-do.git
    targetRevision: main
    path: k8s/gitops/apps/osdu
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
3. Triển khai (Apply)
Thực hiện theo đúng quy trình Repo-first: Push lên Git trước, sau đó Apply file mồi vào Cluster.

# 1. Add và Commit code
cd /opt/infra-osdu-do
git add k8s/gitops k8s/osdu
git commit -m "Step 13: bootstrap App-of-Apps for OSDU (identity/deps/core stubs)"

# 2. Push lên GitHub (Quan trọng: Argo CD đọc từ đây)
git push origin main

# 3. Apply AppProject trước
kubectl apply -f k8s/gitops/projects/osdu.yaml

# 4. Apply App-of-Apps Parent
kubectl apply -f k8s/gitops/app-of-apps/osdu.yaml

4. Checklist Kiểm tra & Nghiệm thu (Step 13 Done)
STT	Hạng mục kiểm tra	Lệnh/Cách kiểm tra	Kết quả kỳ vọng
1	Repo Access	Vào UI Argo CD -> Settings -> Repositories	Kết nối SSH git@github.com... trạng thái Successful.
2	App Project	kubectl -n argocd get appprojects	Thấy project osdu.
3	Parent App	kubectl -n argocd get app app-of-apps-osdu	Status Synced / Healthy.
4	Child Apps	`kubectl -n argocd get app	grep osdu-`
5	Namespaces	`kubectl get ns	grep osdu`
6	Stub Data	kubectl -n osdu-core get cm osdu-core-stub	Lệnh trả về ConfigMap thành công (không báo lỗi NotFound).
7	Doc Version	cat docs/osdu/30-osdu-poc-core.md	File tồn tại và nội dung đúng version M25/0.28.