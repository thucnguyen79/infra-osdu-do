# Step 16 — OSDU Deps (osdu-data): Postgres + OpenSearch + Redis + Redpanda + InitDB

> **Trạng thái hiện tại (theo ngữ cảnh của bạn):** Đã hoàn thành Step 13 (Bootstrap GitOps SSH) và Step 14 (Identity/Keycloak). ArgoCD đang chạy ổn; AppProject `osdu` đã allow namespace `osdu-data`. Cluster 3 CP + 2 Worker, StorageClass DigitalOcean CSI đã sẵn sàng (`do-block-storage*`).

## 1) Mục tiêu của Step 16

Triển khai **các dependency nền (data/deps layer)** để Step 17 (OSDU Core Services) có “hạ tầng dữ liệu” sẵn sàng:

- **PostgreSQL**: nơi các core services lưu metadata/relational data (entitlements, legal, partition, storage, registry, file, schema…).
- **OpenSearch**: phục vụ indexing/search cho một số dịch vụ.
- **Redis**: cache/session.
- **Redpanda**: message bus kiểu Kafka (event streaming).
- **InitDB Job**: tự động tạo **các database cần thiết** trước khi deploy core services.

**GitOps mục tiêu:** mọi thứ đi theo “repo-first”, **ngoại trừ** secrets nhạy cảm (tạo *out-of-band*).

---

## 2) Công cụ/khối sử dụng trong Step 16

- **ArgoCD (GitOps Controller):** đồng bộ manifests từ Git → K8s (Step 13 đã bootstrap bằng SSH).
- **Kustomize overlays:** giữ base portable, overlay tùy biến theo môi trường (DO private).
- **DigitalOcean CSI + StorageClass:** cung cấp PV/PVC cho StatefulSet.

---

## 3) Repo layout (chuẩn Step 16)

```
k8s/osdu/deps/
  base/
    namespace/namespace.yaml
    postgres/...
    postgres-initdb/postgres-initdb-job.yaml
    opensearch/...
    redis/...
    redpanda/...
  overlays/
    do-private/
      kustomization.yaml
      marker-configmap.yaml
      patches/
        patch-storageclass-postgres.yaml
        patch-storageclass-opensearch.yaml
        patch-postgres-pgdata.yaml
        patch-opensearch-initial-admin-password.yaml   # chỉ tham chiếu Secret (không chứa key)
        patch-opensearch-permissions.yaml              # initContainer + fsGroup
        patch-postgres-initdb-job.yaml                 # (nếu dùng overlay để patch job)
```

**Nguyên tắc an toàn:**  
- **KHÔNG commit** file secret chứa key/password (S3 creds, opensearch admin pass, db password…).  
- Dùng `kubectl create secret ... | kubectl apply -f -` trực tiếp (*out-of-band*), giống Step 14/15.

---

## 4) Runbook (repo-first + expected output)

### A. Precheck (trước khi chạm vào repo)

> Chạy trên ToolServer01 (đã set KUBECONFIG đúng).

```bash
set -euo pipefail
TS="$(date +%F-%H%M%S)"
mkdir -p "artifacts/step16-osdu-deps/${TS}"

echo "== nodes ==" | tee "artifacts/step16-osdu-deps/${TS}/A-nodes.txt"
kubectl get nodes -o wide | tee -a "artifacts/step16-osdu-deps/${TS}/A-nodes.txt"

echo "== sc ==" | tee "artifacts/step16-osdu-deps/${TS}/A-sc.txt"
kubectl get sc | tee -a "artifacts/step16-osdu-deps/${TS}/A-sc.txt"

echo "== appproject osdu ==" | tee "artifacts/step16-osdu-deps/${TS}/A-appproject-osdu.txt"
kubectl -n argocd get appproject osdu -o yaml | sed -n '1,240p' | tee -a "artifacts/step16-osdu-deps/${TS}/A-appproject-osdu.txt"

echo "== ns osdu-data ==" | tee "artifacts/step16-osdu-deps/${TS}/A-ns-osdu-data.txt"
kubectl get ns osdu-data -o yaml 2>/dev/null | sed -n '1,120p' | tee -a "artifacts/step16-osdu-deps/${TS}/A-ns-osdu-data.txt" || true
```

**Expected:**
- Nodes 모두 `Ready`.
- Có các StorageClass (ít nhất: `do-block-storage-retain`, `do-block-storage-xfs-retain`).
- AppProject `osdu` có `destinations` include `osdu-data`.

---

### B. Repo-first: chuẩn hoá overlay và patches

#### B1) Fix xung đột Namespace (CRITICAL)

**Issue đã gặp:** trong repo có **2 nơi** khai báo Namespace `osdu-data`:
- `k8s/osdu/deps/base/namespace/namespace.yaml`
- `k8s/osdu/deps/overlays/do-private/namespace.yaml`

Khi overlay lại còn `resources: - namespace.yaml` thì Kustomize báo:
- `may not add resource with an already registered id: Namespace... osdu-data`
- và/hoặc lỗi kiểu `file is not directory` khi tích luỹ resource.

**Fix chuẩn (khuyến nghị):** chỉ giữ **1 nguồn chân lý**.  
- Giữ Namespace ở **base** (portable), **xoá/bỏ** namespace.yaml ở overlay và **không** list trong resources.

[x]Overlay `k8s/osdu/deps/overlays/do-private/kustomization.yaml`:
- đảm bảo **KHÔNG** có `- namespace.yaml` trong `resources:`.

Expected: `kubectl diff -k ...` không còn lỗi “already registered id”.

---

#### B2) Fix PVC template cho Postgres/OpenSearch (CRITICAL)

**Issue đã gặp:** patch chỉ set `storageClassName` → PVC invalid:
- thiếu `spec.accessModes`
- thiếu `spec.resources.requests.storage`

**Fix:** patch đầy đủ `accessModes + resources.requests.storage + storageClassName`

Ví dụ (Postgres, 20Gi):
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: osdu-postgres
spec:
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: do-block-storage-retain
        resources:
          requests:
            storage: 20Gi
```

Ví dụ (OpenSearch, 50Gi, xfs retain):
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: osdu-opensearch
spec:
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: do-block-storage-xfs-retain
        resources:
          requests:
            storage: 50Gi
```

Expected: `kubectl -n osdu-data get pvc` có PVC `Bound` cho Postgres/OpenSearch.

---

#### B3) Fix Postgres initdb lỗi `lost+found` (CRITICAL)

**Issue đã gặp (log):**
`initdb: error: directory "/var/lib/postgresql/data" exists but is not empty (lost+found...)`

Nguyên nhân: volume mount point của block storage có `lost+found`.

**Fix chuẩn:** dùng `PGDATA` trỏ vào **subdir** + initContainer tạo subdir và set ownership.

Patch (tóm tắt):
- env: `PGDATA=/var/lib/postgresql/data/pgdata`
- initContainer (root): `mkdir -p .../pgdata && chown -R postgres:postgres .../pgdata`
- (khuyến nghị mạnh) volumeMount thêm `subPath: pgdata` để mount đúng thư mục.

Expected: Postgres pod chạy `Running`, log initdb OK, không còn `lost+found`.

---

#### B4) OpenSearch: password + tránh xung đột config

**Issue đã gặp 1:** OpenSearch yêu cầu `OPENSEARCH_INITIAL_ADMIN_PASSWORD` (vì Security demo installer).  
**Fix:** tạo secret *out-of-band* + envFrom/secretKeyRef.

```bash
kubectl -n osdu-data create secret generic osdu-opensearch-secret \
  --from-literal=OPENSEARCH_INITIAL_ADMIN_PASSWORD='ChangeMe_Str0ng_Passw0rd_2025!' \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Issue đã gặp 2:** log báo:
`ERROR: setting [plugins.security.disabled] already set ...`
→ thường do **trùng cấu hình** giữa config file + env var / hoặc env bị set 2 lần.

**Fix:** chỉ giữ 1 cơ chế disable security (khuyến nghị dùng env chuẩn của image):
- `DISABLE_SECURITY_PLUGIN=true`
- `DISABLE_INSTALL_DEMO_CONFIG=true`
- Không set trùng `plugins.security.disabled` nhiều nơi.

Expected: log OpenSearch không còn “already set”, pod lên `Running`.

---

#### B5) OpenSearch permission `AccessDeniedException` trên PVC (CRITICAL)

**Issue đã gặp (log):**  
`AccessDeniedException[/usr/share/opensearch/data/nodes]`

**Fix:** initContainer chown/chmod + pod securityContext `fsGroup`.

Patch ví dụ (đã áp dụng thành công):
- initContainer: tạo `.../data/nodes`, `chown -R 1000:1000`, `chmod -R g+rwX`
- pod-level: `fsGroup: 1000`, `fsGroupChangePolicy: OnRootMismatch`
- container securityContext: `runAsUser: 1000`, `runAsGroup: 1000`

Expected:
- `kubectl -n osdu-data get pod osdu-opensearch-0 -o jsonpath='{.spec.initContainers[*].name}'`
  trả về `init-opensearch-data-perms`
- initContainer `Completed`, container `Running`.

---

### C. Diff / Commit / Push (repo-first)

```bash
set -euo pipefail
TS="$(date +%F-%H%M%S)"
mkdir -p "artifacts/step16-osdu-deps/${TS}"

echo "== kustomize render sanity ==" | tee "artifacts/step16-osdu-deps/${TS}/C-render-check.txt"
kubectl kustomize k8s/osdu/deps/overlays/do-private | \
  egrep -n "kind: StatefulSet|name: osdu-postgres|name: osdu-opensearch|PGDATA|DISABLE_SECURITY_PLUGIN|init-opensearch-data-perms|subPath: pgdata" \
  | tee -a "artifacts/step16-osdu-deps/${TS}/C-render-check.txt"

echo "== diff ==" | tee "artifacts/step16-osdu-deps/${TS}/C-diff.txt"
kubectl diff -k k8s/osdu/deps/overlays/do-private | tee -a "artifacts/step16-osdu-deps/${TS}/C-diff.txt" || true

git status
git add -A
git commit -m "Step16: osdu-deps (postgres+opensearch) storage/permissions/initdb fixes"
git push origin main
```

**Expected:**
- Render check thấy đúng các keys (`PGDATA`, initContainer, storage sizes…).
- `kubectl diff` chạy được (có/không có output tuỳ thay đổi).
- Push OK.

---

### D. Sync ArgoCD

- ArgoCD UI: `osdu-deps` / `application-osdu-deps` → **Refresh** → **Sync**.
- Nếu có manual restart (delete pod) để apply nhanh: OK (không cần prune).

**Lưu ý:** StatefulSet update tạo thêm `ControllerRevision` là **bình thường** khi spec đổi.

---

### E. Verify (K8s)

```bash
set -euo pipefail
TS="$(date +%F-%H%M%S)"
mkdir -p "artifacts/step16-osdu-deps/${TS}"

kubectl -n osdu-data get all | tee "artifacts/step16-osdu-deps/${TS}/E-all.txt"
kubectl -n osdu-data get sts,pod -o wide | tee "artifacts/step16-osdu-deps/${TS}/E-sts-pods.txt"
kubectl -n osdu-data get pvc -o wide | tee "artifacts/step16-osdu-deps/${TS}/E-pvc.txt"

kubectl -n osdu-data describe sts osdu-postgres | sed -n '1,220p' | tee "artifacts/step16-osdu-deps/${TS}/E-sts-postgres.txt"
kubectl -n osdu-data describe sts osdu-opensearch | sed -n '1,220p' | tee "artifacts/step16-osdu-deps/${TS}/E-sts-opensearch.txt"
```

**Expected:**
- `osdu-postgres` READY `1/1`
- `osdu-opensearch` READY `1/1`
- PVC: `data-osdu-postgres-0` + `data-osdu-opensearch-0` trạng thái `Bound`.

---

### F. Smoke test (bắt buộc trước Step 17)

#### F1) Postgres: kiểm tra user/DB list
```bash
kubectl -n osdu-data exec -it osdu-postgres-0 -- sh -lc '
echo "POSTGRES_USER=$POSTGRES_USER";
psql -U "$POSTGRES_USER" -d postgres -c "\du";
psql -U "$POSTGRES_USER" -d postgres -c "\l"
'
```

**Expected:** có role admin (vd `osduadmin`) và có các DB tối thiểu:
`osdu entitlements legal partition storage registry file schema (và các DB khác nếu bạn thêm)`.

#### F2) OpenSearch: health endpoint (port-forward)
```bash
kubectl -n osdu-data port-forward sts/osdu-opensearch 9200:9200
# terminal khác:
curl -sS http://127.0.0.1:9200/ | head
curl -sS http://127.0.0.1:9200/_cluster/health?pretty
```

**Expected:** trả JSON và `status` ít nhất `yellow` (single node).

---

## 5) Tổng hợp Issues đã gặp & cách xử lý (Lessons Learned)

1) **Kustomize duplicate Namespace**  
   - Triệu chứng: `already registered id: Namespace... osdu-data` / diff fail  
   - Cách xử lý: chỉ khai báo Namespace **một nơi** (giữ base), overlay bỏ `namespace.yaml`.

2) **PVC invalid do thiếu accessModes/storage**  
   - Triệu chứng: sts không tạo pod, events `spec.accessModes Required`, `spec.resources[storage] Required`  
   - Cách xử lý: patch `volumeClaimTemplates` đầy đủ (`accessModes`, `requests.storage`, `storageClassName`).

3) **Postgres initdb fail do `lost+found` trên mountpoint**  
   - Triệu chứng: `initdb: ... not empty ... lost+found`  
   - Cách xử lý: set `PGDATA` subdir + initContainer + (khuyến nghị) `subPath: pgdata`.

4) **OpenSearch yêu cầu initial admin password**  
   - Triệu chứng: log yêu cầu `OPENSEARCH_INITIAL_ADMIN_PASSWORD`  
   - Cách xử lý: secret out-of-band + env var (dù disable security, vẫn nên set rõ ràng).

5) **OpenSearch config trùng key (`plugins.security.disabled`)**  
   - Triệu chứng: `already set ...`  
   - Cách xử lý: chỉ dùng 1 cơ chế disable (ưu tiên `DISABLE_SECURITY_PLUGIN`, `DISABLE_INSTALL_DEMO_CONFIG`), tránh set trùng ở nhiều nơi.

6) **OpenSearch PVC permission**  
   - Triệu chứng: `AccessDeniedException ... /data/nodes`  
   - Cách xử lý: `fsGroup` + initContainer chown/chmod.

7) **Secrets an toàn (không commit Git)**  
   - Cách xử lý: tạo secret bằng lệnh `kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -` và lưu output vào `artifacts/` (không push).

---

## 6) Tiêu chí hoàn tất Step 16 (Definition of Done)

- ArgoCD app `osdu-deps` **Synced/Healthy**.
- Namespace `osdu-data` tồn tại, không OutOfSync vì “duplicate manifest”.
- `osdu-postgres` & `osdu-opensearch` StatefulSet READY `1/1`.
- PVC `Bound` cho cả 2.
- Smoke test Postgres + OpenSearch pass.
- Artifacts được lưu dưới `artifacts/step16-osdu-deps/<timestamp>/`.

---
## Kết quả smoke test
ops@ToolServer01:/opt/infra-osdu-do$ echo "--- Testing Postgres ---"
--- Testing Postgres ---
ops@ToolServer01:/opt/infra-osdu-do$ kubectl -n osdu-data run psql-test --rm -i --restart=Never   --image=postgres:16-alpine   --env="PGPASSWORD=$PGPASS"   -- sh -lc 'psql -h osdu-postgres -U osduadmin -d osdu -c "select now();"'
              now
-------------------------------
 2025-12-30 03:57:38.580702+00
(1 row)

pod "psql-test" deleted
ops@ToolServer01:/opt/infra-osdu-do$ echo "--- Testing OpenSearch ---"
--- Testing OpenSearch ---
ata run ops@ToolServer01:/opt/infra-osdu-do$ kubectl -n osdu-data run curl-test --rm -i --restart=Never \
>   --image=curlimages/curl:8.10.1 \
>   -- sh -lc 'curl -s http://osdu-opensearch:9200/_cluster/health?pretty'
{
  "cluster_name" : "docker-cluster",
  "status" : "green",
  "timed_out" : false,
  "number_of_nodes" : 1,
  "number_of_data_nodes" : 1,
  "discovered_master" : true,
  "discovered_cluster_manager" : true,
  "active_primary_shards" : 3,
  "active_shards" : 3,
  "relocating_shards" : 0,
  "initializing_shards" : 0,
  "unassigned_shards" : 0,
  "delayed_unassigned_shards" : 0,
  "number_of_pending_tasks" : 0,
  "number_of_in_flight_fetch" : 0,
  "task_max_waiting_in_queue_millis" : 0,
  "active_shards_percent_as_number" : 100.0
}
pod "curl-test" deleted
ops@ToolServer01:/opt/infra-osdu-do$ echo "--- Testing Redpanda/Kafka ---"
--- Testing Redpanda/Kafka ---
ops@ToolServer01:/opt/infra-osdu-do$ # Lưu ý: Nếu lệnh exec sts/... báo lỗi, hãy thử thay bằng tên pod cụ thể (vd: osdu-redpanda-0)
ec -it sops@ToolServer01:/opt/infra-osdu-do$ kubectl -n osdu-data exec -it sts/osdu-redpanda -- \
>   rpk cluster info -X brokers=osdu-kafka:9092 || echo "Redpanda check failed but ignored"
CLUSTER
=======
redpanda.d06b51ca-a9f7-49f2-ae57-b0d7513bc243

BROKERS
=======
ID    HOST                                    PORT
0*    osdu-kafka.osdu-data.svc.cluster.local  9092

ops@ToolServer01:/opt/infra-osdu-do$ echo "--- Testing Redis ---"
--- Testing Redis ---
ops@ToolServer01:/opt/infra-osdu-do$ kubectl -n osdu-data exec deploy/osdu-redis -- redis-cli ping
PONG
---

## 7) Step tiếp theo (Step 17 — OSDU Core Services)

Sau Step 16, chúng ta mới deploy core services để tránh “crash vì thiếu deps”, đặc biệt là:
- DB đã có sẵn
- search engine đã lên
- message bus/cache sẵn sàng
