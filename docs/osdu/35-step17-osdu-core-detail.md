# Step 17 — Deploy `osdu-core` (Repo-first) + Tooling + Smoke checks

## 1) Mục tiêu của Step 17
Sau khi Step 16 đã triển khai xong các dependency trong `osdu-data` (Postgres / OpenSearch / Redis / Redpanda / ObjectStore config), Step 17 nhằm:

- **Dựng “khung GitOps” cho namespace `osdu-core`** (ArgoCD Application + Kustomize overlay) để các step kế tiếp đưa OSDU Core services vào đây.
- **Dựng pod “toolbox”** để test DNS/Connectivity từ *trong cluster* (đúng network path mà services sẽ sử dụng).
- **Chuẩn hoá công cụ AdminCLI** (cài đặt & cách chạy) để dùng cho bootstrap/ops ở các step tiếp theo.

Tiêu chí thành công Step 17:
- ArgoCD app `osdu-core` **Synced/Healthy**
- `deploy/osdu-toolbox` **Running** và exec được
- Smoke checks: DNS + OpenSearch + Postgres + Redis + Redpanda **pass**
- AdminCLI chạy được `--help` (đủ sẵn sàng để dùng ở step sau)

---

## 2) Công cụ và mục đích
- **ArgoCD**: GitOps, auto-sync, audit/rollback rõ ràng.
- **Kustomize**: base/overlay, tránh hardcode theo môi trường.
- **Toolbox pod**: kiểm tra nhanh kết nối service/DNS, curl API, psql DB.
- **AdminCLI**: công cụ chuẩn cho thao tác quản trị OSDU (partition/entitlements/...) và smoke test ở tầng API.

---

## 3) Pre-check
Trên ToolServer01:

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl -n osdu-data get sts,pod,svc
kubectl -n osdu-identity get deploy,pod,svc
kubectl -n argocd get applications.argoproj.io | egrep 'NAME|osdu'
```

Kỳ vọng:
- `osdu-postgres`, `osdu-opensearch` Running/Ready
- Redis/Redpanda Running
- ArgoCD app deps/identity đã Healthy

---

## 4) Repo-first: thêm manifests `osdu-core`
### 4.1 Tạo cấu trúc thư mục
```bash
cd /opt/infra-osdu-do
mkdir -p k8s/osdu/core/base/toolbox
mkdir -p k8s/osdu/core/overlays/do-private
mkdir -p artifacts/step17-osdu-core
```

### 4.2 Base: toolbox deployment
**File:** `k8s/osdu/core/base/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - toolbox/toolbox-deploy.yaml
```

**File:** `k8s/osdu/core/base/toolbox/toolbox-deploy.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: osdu-toolbox
spec:
  replicas: 1
  selector:
    matchLabels:
      app: osdu-toolbox
  template:
    metadata:
      labels:
        app: osdu-toolbox
    spec:
      containers:
        - name: toolbox
          image: postgres:16-alpine
          imagePullPolicy: IfNotPresent
          command: ["sh","-c"]
          args: ["sleep infinity"]
          # postgres image có sẵn psql/pg_isready.
          # Khi cần curl/jq/nslookup: apk add --no-cache curl jq bind-tools
```

### 4.3 Overlay do-private (namespace + marker)
**File:** `k8s/osdu/core/overlays/do-private/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: osdu-core
resources:
  - ../../base
  - marker-configmap.yaml
```

**File:** `k8s/osdu/core/overlays/do-private/marker-configmap.yaml`
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: osdu-core-marker
data:
  env: do-private
  owner: gitops
  note: "Created by Step17"
```

### 4.4 Render-check trước khi commit
```bash
TS="$(date +%F-%H%M%S)"
mkdir -p "artifacts/step17-osdu-core/${TS}"

kubectl kustomize k8s/osdu/core/overlays/do-private \
  | egrep -n "kind: (Deployment|ConfigMap)|name: osdu-toolbox|name: osdu-core-marker" \
  | tee "artifacts/step17-osdu-core/${TS}/A-render-check.txt"
```

### 4.5 ArgoCD Application `osdu-core` (nếu chưa có)
Tìm nơi khai báo Application trong repo:

```bash
grep -R "kind: Application" -n k8s | head -n 20
```

ops@ToolServer01:/opt/infra-osdu-do$ grep -R "kind: Application" -n k8s | head -n 20
k8s/addons/gitops/argocd/base/vendor/install.yaml:12:    kind: Application
k8s/addons/gitops/argocd/base/vendor/install.yaml:5928:    kind: ApplicationSet
k8s/gitops/app-of-apps/osdu.yaml:2:kind: Application
k8s/gitops/app-of-apps/observability.yaml:2:kind: Application
k8s/gitops/apps/osdu/05-ceph.yaml:2:kind: Application
k8s/gitops/apps/osdu/10-identity.yaml:2:kind: Application
k8s/gitops/apps/osdu/20-deps.yaml:2:kind: Application
k8s/gitops/apps/osdu/30-core.yaml:2:kind: Application
k8s/gitops/apps/observability/10-kps.yaml:2:kind: Application
k8s/gitops/apps/observability/20-ingress.yaml:2:kind: Application
k8s/gitops/apps/observability/30-loki.yaml:2:kind: Application

Tạo file Application mới (đặt cạnh các app khác trong repo, tuỳ layout), cụ thể là k8s/gitops/apps/osdu/30-core.yaml:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: osdu-core
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <YOUR_REPO_URL>
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
```

### 4.6 Commit & push
```bash
git add -A
git commit -m "Step17: add osdu-core skeleton (toolbox + marker)"
git push origin main
```

---

## 5) Sync & Verify
Sau khi ArgoCD sync:

```bash
kubectl -n osdu-core get deploy,pod,cm -o wide
kubectl -n osdu-core get pod -l app=osdu-toolbox
```

Kỳ vọng:
- `deploy/osdu-toolbox` AVAILABLE 1
- Pod `osdu-toolbox-*` Running
- `cm/osdu-core-marker` tồn tại

---

## 6) Smoke checks (từ trong cluster)
### 6.1 Cài tool trong toolbox
```bash
kubectl -n osdu-core exec -it deploy/osdu-toolbox -- sh -lc 'apk add --no-cache curl jq bind-tools'
```

### 6.2 DNS / reachability
```bash
kubectl -n osdu-core exec -it deploy/osdu-toolbox -- sh -lc '
  nslookup osdu-postgres.osdu-data.svc.cluster.local >/dev/null &&
  nslookup osdu-opensearch.osdu-data.svc.cluster.local >/dev/null &&
  echo "DNS OK"
'
```

### 6.3 OpenSearch health
```bash
kubectl -n osdu-core exec -it deploy/osdu-toolbox -- sh -lc '
  curl -sS http://osdu-opensearch.osdu-data:9200/_cluster/health?pretty | jq .
'
```

### 6.4 Postgres connectivity
Lấy credentials từ secret ở `osdu-data` (không commit), rồi exec psql:

```bash
POSTGRES_USER=$(kubectl -n osdu-data get secret osdu-postgres-secret -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
POSTGRES_PASSWORD=$(kubectl -n osdu-data get secret osdu-postgres-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)

kubectl -n osdu-core exec -it deploy/osdu-toolbox -- sh -lc "\
  export PGPASSWORD='${POSTGRES_PASSWORD}'; \
  psql -h osdu-postgres.osdu-data -U '${POSTGRES_USER}' -d postgres -c '\\du'; \
  psql -h osdu-postgres.osdu-data -U '${POSTGRES_USER}' -d postgres -c '\\l' \
"
```

### 6.5 Redis ping (ephemeral pod)
```bash
kubectl -n osdu-core run -it --rm redis-cli --image=redis:7-alpine -- \
  redis-cli -h osdu-redis-master.osdu-data ping
```
Lệnh làm gì? Tạo một Pod tạm thời tên redis-cli, tải image redis:7-alpine, và thử ping vào server Redis thật.
Tại sao lỗi? Lỗi timed out khi dùng kubectl run thường do 2 nguyên nhân:
Mạng chậm: Việc tải image redis:7-alpine về máy WorkerNode mất quá nhiều thời gian (hơn 60s), nên lệnh kubectl trên máy bạn bị timeout (ngắt kết nối) trước khi Pod kịp chạy.
Pod start/stop quá nhanh: Pod vừa chạy lên, thực hiện lệnh xong và tắt ngay lập tức trước khi kubectl kịp bắt (attach) vào để xem kết quả.

Do đó, ta chạy lệnh kiểm tra trực tiếp:
ops@ToolServer01:/opt/infra-osdu-do$ kubectl -n osdu-core exec -it deploy/osdu-toolbox -- redis-cli -h osdu-redis.osdu-data ping
PONG

### 6.6 Redpanda quick check (ephemeral pod)
Dùng tag trùng với Redpanda đang chạy ở deps (v24.2.6 trong repo hiện tại):

```bash
kubectl -n osdu-core run -it --rm rpk --image=redpandadata/redpanda:v24.2.6 -- \
  rpk cluster info --brokers osdu-redpanda.osdu-data:9092
```

kubectl -n osdu-core run -it --rm rpk-test --restart=Never \
  --image=redpandadata/redpanda:v24.2.6 \
  -- cluster info -X brokers=osdu-kafka.osdu-data:9092

Do hướng dẫn sai tên, ta cần kiểm tra lại tên service. Chạy kubectl -n osdu-data get svc để xác nhận tên Service.
ops@ToolServer01:/opt/infra-osdu-do$ kubectl -n osdu-data get svc
NAME              TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
osdu-kafka        ClusterIP   10.97.253.103    <none>        9092/TCP   24h
osdu-opensearch   ClusterIP   10.102.200.152   <none>        9200/TCP   24h
osdu-postgres     ClusterIP   10.109.9.83      <none>        5432/TCP   24h
osdu-redis        ClusterIP   10.107.46.176    <none>        6379/TCP   24h 
 
Chạy lại lệnh Redpanda với tên Service đúng
ops@ToolServer01:/opt/infra-osdu-do$ kubectl -n osdu-core run -it --rm rpk-test --restart=Never \
>   --image=redpandadata/redpanda:v24.2.6 \
>   -- cluster info -X brokers=osdu-kafka.osdu-data:9092
+ '[' '' = true ']'
+ exec /usr/bin/rpk cluster info -X brokers=osdu-kafka.osdu-data:9092

CLUSTER
=======
redpanda.d06b51ca-a9f7-49f2-ae57-b0d7513bc243

BROKERS
=======
ID    HOST                                    PORT
0*    osdu-kafka.osdu-data.svc.cluster.local  9092

pod "rpk-test" deleted

ops@ToolServer01:/opt/infra-osdu-do$

### 6.7 Lưu bằng chứng
```bash
TS="$(date +%F-%H%M%S)"
mkdir -p "artifacts/step17-osdu-core/${TS}"

kubectl -n osdu-core get all -o wide | tee "artifacts/step17-osdu-core/${TS}/C1-osdu-core-getall.txt"
kubectl -n osdu-data get sts,pod -o wide | tee "artifacts/step17-osdu-core/${TS}/C2-osdu-data-sts-pod.txt"
```

---

## 7) Chuẩn bị AdminCLI (dùng lại cho Step sau)
### Option A (khuyến nghị): chạy bằng Docker
AdminCLI có image public trên registry của OSDU:

```bash
# kiểm tra help
 docker run --rm community.opengroup.org:5555/osdu/ui/admincli:latest --help

# khung chạy (BASE_URL/DATA_PARTITION/TOKEN sẽ dùng thật sự ở step sau khi core APIs sẵn sàng)
# export BASE_URL="https://<osdu-gateway-host>"
# export DATA_PARTITION="<partition>"   # ví dụ: opendes
# export TOKEN="<access_token>"          # lấy từ Keycloak
# docker run --rm -e BASE_URL -e DATA_PARTITION -e TOKEN \
#   community.opengroup.org:5555/osdu/ui/admincli:latest partition list
```

### Option B: cài pipx trên ToolServer01
Nếu bạn muốn cài vào host (phục vụ automation/script):

```bash
sudo apt-get update
sudo apt-get install -y python3-pip pipx
pipx ensurepath
# xem tài liệu AdminCLI để biết đúng package/command tương ứng
```

---

## 8) Troubleshooting nhanh
- Toolbox không lên: `kubectl -n osdu-core describe pod -l app=osdu-toolbox`
- DNS fail: kiểm tra CoreDNS `kubectl -n kube-system get pods -l k8s-app=kube-dns`
- OpenSearch lỗi: xem lại Step16 (initContainer permission + fsGroup)
- Postgres auth fail: confirm service DNS `osdu-postgres.osdu-data` và password đúng
