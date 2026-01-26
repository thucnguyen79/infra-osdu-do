# Deployment Checklist (Kubernetes + OSDU on DigitalOcean)

## Step 1 - ToolServer01 base + repo skeleton
- [x] Hostname/Timezone/NTP OK
- [x] User ops + sudo OK
- [x] Repo /opt/infra-osdu-do created (docs/ ansible/ k8s/ osdu/ diagrams/)
- [x] Inventory base documented (docs/02-inventory.md)

## Step 2 - VPN WireGuard
- [x] WireGuard installed on ToolServer01
- [x] wg0 up (10.200.200.1/24)
- [x] DO Firewall allows UDP 51820 -> ToolServer01
- [x] AdminPC connected (10.200.200.2)
- [x] SSH to ControlPlane01 via private eth1 (ops@10.118.0.2) OK

## Step 2.9 - Ansible inventory over private eth1
- [x] Ansible installed on ToolServer01
- [x] ansible.cfg created and points to ansible/hosts.ini
- [x] ansible/hosts.ini uses ONLY 10.118.0.x addresses
- [x] Ansible ping: ansible all -m ping (SUCCESS)

## Step 3 - Security baseline (Firewall/SSH)
### Step 3.1 DigitalOcean Firewall
- [x] FW-TOOLSERVER01 created and applied
- [x] FW-CLUSTER-NODES created and applied
- [x] Public SSH to CP/Worker/AppServer01 blocked
- [x] Private SSH via VPN/VPC works (ssh ops@10.118.0.2 OK)
- [x] Evidence stored in artifacts/step3-firewall/

### Step 3.3 SSH hardening (key-only)
- [x] Canary: apply hardening to ControlPlane01
- [x] Verify: new SSH session ops@10.118.0.2 works
- [x] Rollout: apply hardening to CP/Worker/AppServer01
- [x] Verify: ansible ping all OK after hardening
- [x] Apply hardening to ToolServer01 last
- [x] Evidence stored in artifacts/step3-ssh-hardening/

## Step 4 - Kubernetes prerequisites (node baseline)
### Step 4.1 Node baseline (CP/Worker)
- [x] Swap disabled on all CP/Worker
- [x] Kernel modules overlay, br_netfilter loaded
- [x] sysctl configured for Kubernetes networking
- [x] containerd installed & running (SystemdCgroup=true)
- [x] Evidence stored in artifacts/step4-node-baseline/
- [x] kubeadm/kubelet/kubectl installed on CP/Worker
- [x] Packages held: apt-mark hold kubelet kubeadm kubectl
- [x] kubelet node-ip forced to private eth1 (10.118.0.0/20) via /etc/default/kubelet
- [x] Canary run OK (artifacts/step4-k8s-packages/run-canary*.log)
- [x] Evidence saved per node: artifacts/step4-k8s-packages/<node>/k8s-packages.txt
- [x] Issue documented (if occurred): docs/issues/step4.2-pipefail-dash.md
- [x] Doc updated: docs/15-k8s-packages.md

### Step 4.3 - HA Control Plane endpoint (Self-managed LB on AppServer01)
#### Step 4.3.1 - Update DO Firewall for internal VPC control-plane traffic
- [x] FW-CLUSTER-NODES inbound allows VPC CIDR 10.118.0.0/20:
  - [x] TCP 6443 (Kubernetes API)
  - [x] TCP 2379-2380 (etcd stacked)
  - [x] TCP 10250 (kubelet API)
- [x] Evidence screenshots stored: artifacts/step4-controlplane-endpoint/screenshots/

#### Step 4.3.2 - Deploy API LoadBalancer on AppServer01 (HAProxy)
- [x] HAProxy installed & enabled on AppServer01
- [x] HAProxy listens on 10.118.0.8:6443
- [x] Backend targets configured: 10.118.0.2/3/4:6443
- [x] Evidence saved: artifacts/step4-controlplane-endpoint/AppServer01/haproxy.txt
- [x] Run log saved: artifacts/step4-controlplane-endpoint/run-lb.log
- [x] Ansible playbook committed: ansible/playbooks/30-apiserver-lb.yml

#### Step 4.3.3 - Standardize controlPlaneEndpoint name (hosts entry)
- [x] /etc/hosts updated on ToolServer01 + all k8s nodes:
  - [x] 10.118.0.8 k8s-api.internal
- [x] Verification OK: getent hosts k8s-api.internal (on k8s_cluster)
- [x] Run log saved: artifacts/step4-controlplane-endpoint/run-hosts.log
- [x] Ansible playbook committed: ansible/playbooks/31-hosts-k8s-api.yml

#### Step 4.3.4 - Create/Stage/Validate kubeadm HA config
- [x] kubeadm HA config created in repo: k8s/kubeadm/kubeadm-init-ha-v1.30.yaml
- [x] Config staged to ControlPlane01: /etc/kubernetes/kubeadm/kubeadm-init-ha-v1.30.yaml
- [x] kubeadm config validate PASS on ControlPlane01
- [x] Evidence saved:
  - [x] artifacts/step4-controlplane-endpoint/ControlPlane01/kubeadm-validate.txt
  - [x] artifacts/step4-controlplane-endpoint/run-validate.log
- [x] Issue documented (if occurred): docs/issues/step4.3-kubeadm-validate-file-missing.md
- [x] Ansible playbook committed: ansible/playbooks/32-kubeadm-stage-validate.yml
- [x] Doc updated: docs/16-ha-controlplane-endpoint.md


### Step 4.3.5 kubeadm init (HA endpoint)
- [x] artifacts-private/ created and gitignored (tokens/certs)
- [x] kubeadm init completed on ControlPlane01 (using controlPlaneEndpoint)
- [x] kubeconfig configured (CP01 + ToolServer01)
- [x] kubectl get nodes works from ToolServer01
- [x] Non-secret evidence saved under artifacts/step4-controlplane-endpoint/

### Step 4.4 Join nodes (CP02/CP03 + Workers)
- [x] Preflight: k8s-api.internal resolves to 10.118.0.8 on joining nodes
- [x] Preflight: TCP to k8s-api.internal:6443 OK from joining nodes
- [x] New join materials generated (token + cert-key) and stored in artifacts-private/
- [x] ControlPlane02 joined as control-plane
- [x] ControlPlane03 joined as control-plane
- [x] WorkerNode01 joined as worker
- [x] WorkerNode02 joined as worker
- [x] Post-join evidence saved (non-secret) under artifacts/step4-kubeadm-join/
- [x] Docs updated: docs/17-kubeadm-join-nodes.md
- [x] Control-plane join uses --apiserver-advertise-address = private eth1 IP (DO dual-NIC)

## STEP 5 — Install CNI
- [x] Step 5.1 Verify kubeadm CIDRs (podSubnet/serviceSubnet)
- [x] Step 5.2 Prepare Calico VXLAN manifest (repo-first)
- [x] Step 5.3 Allow UDP 4789 within VPC (cloud firewall / host firewall if any)
- [x] Step 5.4 Apply CNI + verify nodes Ready + CoreDNS Running
- [x] Step 5.5 Save evidence + commit
- [x] DS/calico-node Ready 5/5
- [x] IP_AUTODETECTION_METHOD pinned to eth1 (DO dual NIC)
- [x] Evidence saved: artifacts/step5-cni/*
- [x] 5.x Collect evidence for calico-node CrashLoopBackOff (describe/events/logs previous)
- [x] 5.x Patch Calico probes for VXLAN (felix-only) OR allow BGP port 179
- [x] 5.x Verify rollout ds/calico-node == ready on all nodes
- [x] 5.x Verify node-to-node pod networking (ping test pod)

## Step 6 - Ingress Controller (ingress-nginx -NodePort private-only)

- [x] 6.1 Prepare ingress-nginx kustomize overlay (do-private-nodeport)
- [x] 6.2 Ensure namespace ingress-nginx exists
- [x] 6.3 kubectl diff -k overlay (record output)
- [x] 6.3 kubectl apply -k overlay (record output)
- [x] 6.3 Rollout status ingress-nginx-controller
- [x] 6.4 Verify Service is NodePort + pinned ports (30080/30443)
- [x] 6.4 Confirm externalTrafficPolicy=Local
- [x] 6.4 Fix DO Firewall to allow TCP 30080/30443 from 10.118.0.0/20
- [x] 6.4 Ensure controller HA across both workers (replicas=2 + worker-only + anti-affinity)
- [x] 6.4 NodePort TCP test from ToolServer01 to both workers OK
- [x] 6.5 Deploy echo test app + service
- [x] 6.5 Deploy echo ingress (host echo.internal)
- [x] 6.5 Verify routing via both workers (curl Host header) OK

## Step 7 — AppServer01 self-managed LB
tep 7 — Self-managed Load Balancer on AppServer01 (HAProxy)
**Goal:** expose stable, private-only endpoints:
- Kubernetes API: `k8s-api.internal:6443` ➜ control planes (6443)
- Ingress HTTP/HTTPS: `AppServer01:80/443` ➜ workers NodePorts (30080/30443)

### 7.1 Firewall (DO)
- [x] Allow inbound to **AppServer01** (private-only):
  - TCP `6443`, `80`, `443` from `10.118.0.0/20` (and/or WireGuard subnet as needed)

### 7.2 Deploy HAProxy via Ansible (repo-first)
- [x] Playbook: `ansible/playbooks/31-appserver01-lb-haproxy.yml`
- [x] Template: `ansible/templates/haproxy.cfg.j2`
- [x] Must run with correct Ansible config/inventory:
  - `source .venv/bin/activate`
  - `export ANSIBLE_CONFIG=/opt/infra-osdu-do/ansible/ansible.cfg`

Evidence:
- `artifacts/step7-lb-appserver01/run-appserver01-haproxy-fix6443.log`

### 7.3 Verify LB is listening and config valid
- [x] `ss -lntp` shows HAProxy listening on `:6443`, `:80`, `:443`
- [x] `haproxy -c -f /etc/haproxy/haproxy.cfg` returns **Configuration file is valid**

Evidence:
- `artifacts/step7-lb-appserver01/haproxy-ss.txt`
- `artifacts/step7-lb-appserver01/haproxy-config-check.txt`
- `artifacts/step7-lb-appserver01/haproxy-status.txt`

### 7.4 Verify API reachability via control-plane endpoint
- [x] `timeout 2 bash -c "</dev/tcp/k8s-api.internal/6443"` returns OK
- [x] `kubectl get nodes -o wide` works from ToolServer01

Evidence:
- `artifacts/step7-lb-appserver01/api-6443-after-fix.txt`
- `artifacts/step7-lb-appserver01/kubectl-get-nodes-after-fix.txt`

### 7.5 Verify ingress via LB
- [x] `curl -H "Host: echo.internal" http://10.118.0.8/` returns echo JSON

Evidence:
- `artifacts/step7-lb-appserver01/echo-via-lb-after-fix.txt` (or command output captured)

### 7.6 Troubleshooting notes (what we hit)
- HTTP health-check to NodePort can fail with **404** (ingress default) ⇒ use **TCP check** for NodePort reachability, or point httpchk to a known host/path.
- If Ansible says "No inventory was parsed" ⇒ missing `ANSIBLE_CONFIG` or wrong working dir.
- If `kubectl` errors `connect: connection refused` to `k8s-api.internal:6443` ⇒ LB/API frontend not listening, firewall, or wrong `/etc/hosts` mapping.

## Step 8 — TLS (Option A: Internal CA) with cert-manager
**Goal:** Provide cluster-managed TLS (issuance + renewal) for internal services using an Internal Root CA.

### 8.1 Deploy cert-manager (kustomize)
- [x] Namespace `cert-manager` exists before diff/apply (or managed via vendor manifest)
- [x] `kubectl diff -k k8s/addons/cert-manager/overlays/do-private` passes (or diff executed after ns fix)
- [x] `kubectl apply -k ...` succeeded
- [x] Pods Running: `cert-manager`, `cainjector`, `webhook`
- [x] CRDs present

Evidence:
- `artifacts/step8-tls/ns-cert-manager.txt`
- `artifacts/step8-tls/cert-manager-diff.txt`
- `artifacts/step8-tls/cert-manager-apply.txt`
- `artifacts/step8-tls/cert-manager-pods.txt`
- `artifacts/step8-tls/cert-manager-crds.txt`

### 8.2 Internal CA chain
- [x] ClusterIssuer `internal-ca` READY=True
- [x] Certificate `internal-root-ca` READY=True (Secret: `internal-root-ca`)

Evidence:
- `artifacts/step8-tls/clusterissuer-internal-ca.txt`
- `artifacts/step8-tls/cert-internal-root-ca.txt`

### 8.3 Workload cert (echo.internal)
- [x] Certificate `echo-internal-tls` READY=True
- [x] Ingress uses `secretName: echo-internal-tls`

Evidence:
- `artifacts/step8-tls/echo-cert-describe.txt`
- `artifacts/step8-tls/echo-ingress-get.txt`

### 8.4 Verify TLS end-to-end
- [x] Export Root CA cert to `artifacts/step8-tls/internal-root-ca.crt` (public cert only)
- [x] `curl --cacert ... https://echo.internal` works via LB `10.118.0.8:443`

Evidence:
- `artifacts/step8-tls/internal-root-ca.crt` (public)
- (optional) capture curl output into `artifacts/step8-tls/echo-https-curl.txt`

### Issues encountered (and fixes)
- [x] Duplicate Namespace in kustomize (`cert-manager`) ⇒ remove duplicate or `$patch: delete` vendor Namespace.
- [x] `kubectl diff` failed because namespace not found ⇒ create namespace first (or apply vendor NS first).
- [x] `file is not directory` / path mismatch ⇒ fix `resources:` to point to correct file/dir.

## Step 9 - Storage (DigitalOcean CSI + Snapshots)
- [x] Worker prereq installed (open-iscsi/iscsid)
- [x] DO CSI driver deployed (csi-do-controller + csi-do-node Running)
- [x] Snapshot CRDs + snapshot-controller deployed
- [x] StorageClasses created (Delete/Retain, ext4/xfs); default class set
- [x] Dynamic PV provisioning verified with test PVC/Pod (create/attach/detach/delete)
- [x] Evidence stored in artifacts/step9-storage/ (secrets under artifacts-private/)

## Step 10 - Observability
### A. Monitoring Core
- [x] Namespace observability tồn tại
- [x] CRDs monitoring.coreos.com đầy đủ (có Alertmanager/Prometheus/ThanosRuler…)
- [x] Pods Monitoring Running (Grafana/Prometheus/Alertmanager/Operator)

### B. Ingress + TLS Internal CA
- [x] Có 3 ingress đúng host: grafana/prometheus/alertmanager .internal
- [x] Có 3 certificate READY=True
- [x] HTTP 308 → HTTPS
- [x] HTTPS verify CA OK (Grafana login 302; Prometheus/Alertmanager readiness nên 200)

### C. Logging (Loki + Promtail)
- [x] Loki Running
- [x] PVC Loki Bound (retain SC)
- [x] Promtail chạy đủ node
- [x] Grafana query được log từ Loki
- [x] values-loki.yaml đã fix đúng (schemaConfig…)

#### D. Truy cập 
- [x] Truy cập được giao diện Grafana Web UI qua HTTPS.
- [x] Log từ Pod test đổ về Loki thành công.
- [x] Evidence đầy đủ trong artifacts/step10-observability/.

## Step 11 - ArgoCD
- [x] Namespace argocd trạng thái Active.
- [x] Manifest install.yaml đã được nạp thành công qua Server-side apply.
- [x] Các Pod (Server, Controller, Repo-server, Redis) đã Running.
- [x] Ingress argocd.internal đã nhận IP và Certificate báo READY.
- [x] Lấy được mật khẩu Admin và lưu vào artifacts.
- [x] Lệnh curl HTTPS trả về mã 200/302 với chứng chỉ nội bộ.
- [x] Cấu hình /etc/hosts trên ToolServer đã nhận diện domain mới.

## Step 12 - Observability App-of-Apps
### A. Checklist triển khai
- [x] Chuẩn bị biến repo (để tránh sửa YAML nhiều nơi)
- [x] Tạo cấu trúc GitOps cho Observability (repo-first)
- [x] Tạo “Application con” cho từng addon Observability
  - [x] (1) kube-prometheus-stack
  - [x] (2) Observability Ingress (grafana/prometheus/alertmanager internal)
  - [x] (3) Loki
  - [ ] (4) Promtail (tùy chọn — chỉ khi bạn đã tạo addon logging-promtail)
- [x] Tạo “Application cha” App-of-Apps (bootstrap 1 lần)
- [x] Repo-first: diff → commit → push
- [x] Bootstrap vào cluster (apply đúng 1 file “cha”)
- [x] Verify Argo đã “nhìn thấy” các app con
- [ ] Sync strategy 

### B. Checklist hoạt động
- [x] Repository Connection: Argo CD hiển thị trạng thái Successful trong phần Settings > Repositories.
- [x] Hierarchy: App app-of-apps-observability hiển thị trên UI và chứa 3 App con bên trong.
- [x] Sync Strategy: Các App con được cấu hình ServerSideApply=true để tránh lỗi CRD lớn.
- [x] Clean Diff: Chạy kubectl diff -k không còn lỗi "No such file or directory".
- [x] Health Status: Tất cả các Application trên giao diện Argo CD hiển thị màu xanh (Healthy và Synced).

## Step 13 - OSDU POC: “Chốt distro/version + dependency matrix” và dựng khung GitOps cho OSDU
### A. Checklist triển khai
- [x] Chuyển đổi SSH (Deploy Key):
   - [x] Tạo cặp khóa SSH (Ed25519) và add Public Key vào GitHub Deploy Keys.
   - [x] Tạo Secret repo-infra-osdu-do trong Argo CD chứa Private Key.
   - [x] Cập nhật toàn bộ repoURL trong các App cũ (Observability) sang dạng SSH (git@...).
   - [x] Xóa kết nối HTTPS cũ trong Argo CD Settings.
- [x] Version Freeze (Tài liệu):
   - [x] Tạo file docs/osdu/30-osdu-poc-core.md chốt phiên bản M25 và danh sách Dependency.
- [x] Bootstrap OSDU Framework:
   - [x] Tạo AppProject osdu để quản lý các namespace (osdu-identity, osdu-data, osdu-core).
   - [x] Tạo cấu trúc thư mục và Stub (ConfigMap mồi) cho 3 nhóm dịch vụ:
     - [x] (1) Identity Stub (osdu-identity).
     - [x] (2) Dependencies Stub (osdu-deps).
     - [x] (3) Core Services Stub (osdu-core).
  - [x] Tạo manifest "Child Application" trỏ vào các thư mục Stub trên.
  - [x] Tạo "Parent Application" app-of-apps-osdu.
- [x] Repo-first Workflow:
  - [x] Git Add & Commit tất cả các file mới.
  - [x] Git Push lên nhánh main (Bắt buộc để Argo CD đọc được).
- [x] Apply vào Cluster:
   - [x] Apply file Project (projects/osdu.yaml).
   - [x] Apply file Parent App (app-of-apps/osdu.yaml).

### B. Checklist hoạt động
- [x] SSH Repo Access: Kiểm tra kubectl -n argocd get app -o custom-columns=NAME:.metadata.name,REPO:.spec.source.repoURL, tất cả phải là git@github.com....
- [x] AppProject: Project osdu xuất hiện trong Argo CD và whitelist đúng các namespace đích.
- [x] Hierarchy: App cha app-of-apps-osdu xuất hiện trên UI và tự động sinh ra 3 App con (osdu-identity, osdu-deps, osdu-core).
- [x] Namespace: Các namespace osdu-identity, osdu-data, osdu-core đã được tự động tạo trong Cluster.
- [x] Health Status: Tất cả 3 App con hiển thị màu xanh (Healthy và Synced).
- [x] Stub Verification: Chạy lệnh kubectl -n osdu-core get cm osdu-core-stub trả về kết quả thành công (chứng tỏ pipeline GitOps đã thông suốt).

## Step 14 - OSDU Identity (Keycloak + Postgres)
- [x] Namespace `osdu-identity` created/active
- [x] Keycloak DB deployed and Ready (rollout OK)
- [x] Keycloak deployed and Ready; accessible via Ingress `keycloak.internal`
- [x] TLS issued by cert-manager `internal-ca` (verify HTTPS with internal CA)
- [x] Realm `osdu` bootstrapped; client `osdu-cli` created
- [x] Enabled `directAccessGrantsEnabled=true` for `osdu-cli` (password grant for POC)
- [x] Test user created/fixed (profile + non-temporary password) -> access token acquired
- [x] Realm export produced (`osdu-realm.json`) and stored under `artifacts/step14-identity/`
- [x] Evidence committed/pushed (repo-first)

## Step 15 - Data Ecosystem (Ceph Object Storage)
### A. Triển khai Resources (Repo-first)
- [x] **Vendor Rook Manifests:** Đã tải CRDs, Common, Operator v1.14.9 về `base/vendor`.
- [x] **Cấu hình Overlay:**
  - [x] `CephCluster`: Cấu hình Minimal (1 Mon, 1 OSD, No Replica).
  - [x] `ObjectStore`: RGW Port 80.
  - [x] `User`: Tạo user `osdu-s3-user`.
  - [x] `Ingress/TLS`: Domain `s3.internal` với `internal-ca`.
- [x] **GitOps:**
  - [x] Commit code lên nhánh main.
  - [x] ArgoCD App `osdu-ceph` (Project `default`) Synced & Healthy.

### B. Kiểm tra & Nghiệm thu
- [x] **Pods Health:**
  - [x] Operator, Mon, Mgr Running.
  - [x] OSD-0 Running (PVC 50Gi Bound).
  - [x] RGW Running.
- [x] **Kết nối S3:**
  - [x] Lệnh `curl` nội bộ trả về 200 OK.
  - [x] Đã lấy được AccessKey và SecretKey.

## Step 16 — OSDU Deps (osdu-data): Postgres + OpenSearch + Redis + Redpanda + InitDB

### Mục tiêu
Triển khai các dependency nền phục vụ Step 17 (OSDU core services): Postgres, OpenSearch, Redis, Redpanda; đồng thời đảm bảo các DB cần thiết đã được tạo.

### Checklist (Runbook-level)

- [ ] **Precheck**
  - [ ] `kubectl get nodes -o wide` → tất cả `Ready`
  - [ ] `kubectl get sc` → có `do-block-storage-retain`, `do-block-storage-xfs-retain`
  - [ ] `kubectl -n argocd get appproject osdu -o yaml` → allow `osdu-data`

- [ ] **Repo-first**
  - [ ] Overlay `k8s/osdu/deps/overlays/do-private/` không khai báo Namespace `osdu-data` trùng với base (không có `resources: - namespace.yaml`)
  - [ ] Patch PVC templates có đủ `accessModes` + `resources.requests.storage` (Postgres/OpenSearch)
  - [ ] Postgres set `PGDATA` vào subdir + initContainer (và khuyến nghị `subPath: pgdata`)
  - [ ] OpenSearch có initContainer permissions + `fsGroup` để tránh `AccessDeniedException`

- [ ] **Secrets (Out-of-band, KHÔNG commit Git)**
  - [ ] `kubectl -n osdu-data create secret generic osdu-opensearch-secret --from-literal=OPENSEARCH_INITIAL_ADMIN_PASSWORD=... --dry-run=client -o yaml | kubectl apply -f -`
  - [ ] (Nếu có) secrets khác cho Step 17 (S3/Ceph creds, db creds…) cũng tạo out-of-band

- [ ] **GitOps Sync**
  - [ ] `kubectl diff -k k8s/osdu/deps/overlays/do-private` chạy OK (không lỗi Kustomize)
  - [ ] Commit/Push repo
  - [ ] ArgoCD app `osdu-deps` Refresh + Sync

- [ ] **Verify**
  - [ ] `kubectl -n osdu-data get sts,pod -o wide` → `osdu-postgres` READY `1/1`, `osdu-opensearch` READY `1/1`
  - [ ] `kubectl -n osdu-data get pvc -o wide` → PVC `Bound`

- [ ] **Smoke test**
  - [ ] Postgres: `psql -U "$POSTGRES_USER" -d postgres -c "\l"` thấy các DB: `osdu entitlements legal partition storage registry file schema ...`
  - [ ] OpenSearch: `port-forward` + `curl http://127.0.0.1:9200/_cluster/health?pretty` trả JSON (status `yellow/green`)

- [ ] **Artifacts**
  - [ ] Lưu toàn bộ output vào `artifacts/step16-osdu-deps/<timestamp>/` (không commit secrets)

## Step 17 — OSDU Core scaffold + Tooling (osdu-core)

### Mục tiêu
Tạo khung triển khai `osdu-core` theo GitOps (ArgoCD + Kustomize), đồng thời dựng **toolbox** để kiểm tra connectivity từ trong cluster và chuẩn bị **AdminCLI** phục vụ bootstrap/ops ở các step kế tiếp.

### Checklist (Runbook-level)

- [ ] **Precheck**
  - [ ] `kubectl -n osdu-data get sts,pod -o wide` → deps READY
  - [ ] `kubectl -n argocd get applications | egrep 'osdu-deps|osdu-identity'` → Synced/Healthy

- [ ] **Repo-first**
  - [ ] Có `k8s/osdu/core/base/` (toolbox deployment) + `k8s/osdu/core/overlays/do-private/` (namespace + marker)
  - [ ] Render check: `kubectl kustomize k8s/osdu/core/overlays/do-private` không lỗi
  - [ ] (Nếu chưa có) tạo ArgoCD `Application/osdu-core` trỏ đến `k8s/osdu/core/overlays/do-private` và `CreateNamespace=true`
  - [ ] Commit/Push repo

- [ ] **GitOps Sync**
  - [ ] ArgoCD app `osdu-core` Refresh + Sync

- [ ] **Verify**
  - [ ] `kubectl -n osdu-core get deploy,pod,cm -o wide` → `osdu-toolbox` Running

- [ ] **Smoke checks (from inside cluster)**
  - [ ] DNS: resolve `osdu-postgres.osdu-data`, `osdu-opensearch.osdu-data`
  - [ ] OpenSearch: `curl http://osdu-opensearch.osdu-data:9200/_cluster/health?pretty`
  - [ ] Postgres: copy secret `osdu-postgres-secret` sang `osdu-core` (out-of-band), `psql` list roles/DB
  - [ ] Redis: `redis-cli ping` (ephemeral pod)
  - [ ] Redpanda: `rpk cluster info` (ephemeral pod)

- [ ] **AdminCLI**
  - [ ] Cài/chuẩn bị AdminCLI (container hoặc pipx) và chạy được `admincli --help`

- [ ] **Artifacts**
  - [ ] Lưu output vào `artifacts/step17-osdu-core/<timestamp>/` (không commit secrets)

**Tài liệu chi tiết:** `docs/35-step17-osdu-core.md`

## Step 18 — OSDU Core Services (osdu-core)

### Mục tiêu
Triển khai 6 OSDU Core Services: Partition, Entitlements, Storage, Legal, Schema, File.

### A. Precheck
- [x] `kubectl -n osdu-data get sts,pod -o wide` → Postgres/OpenSearch/Redis/Redpanda READY
- [x] `kubectl -n argocd get app osdu-deps osdu-identity` → Synced/Healthy
- [x] Databases đã được tạo: partition, entitlements, storage, legal, schema, file

### B. Repo-first Deployment
- [x] Base deployments tạo trong `k8s/osdu/core/base/services/`
- [x] Overlay patches trong `k8s/osdu/core/overlays/do-private/patches/`
- [x] ConfigMap `osdu-core-env` với tất cả env vars cần thiết:
  - [x] POSTGRES_HOST, POSTGRES_PORT
  - [x] REDIS_HOST, REDIS_STORAGE_HOST, REDIS_GROUP_HOST
  - [x] PARTITION_API
  - [x] KEYCLOAK_ISSUER_URI
- [x] Patches:
  - [x] `patch-partition-env.yaml` - PARTITION_POSTGRESQL_USERNAME/PASSWORD
  - [x] `patch-entitlements.yaml` - Auth disabled for POC
  - [x] `patch-entitlements-db.yaml` - ENTITLEMENTS_DB_PASSWORD
  - [x] patch files in revision-history folder - patch 03 most recent revision-history


### C. GitOps Sync
- [x] `kubectl kustomize k8s/osdu/core/overlays/do-private` không lỗi
- [x] Git commit & push
- [x] ArgoCD app `osdu-core` Synced & Healthy
- [x] Không còn OutOfSync resources

### D. Partition Database Schema (OSM)
- [x] Tạo schema cho partition database:
  ```sql
  CREATE TABLE partition_property (
      pk BIGSERIAL PRIMARY KEY,
      id VARCHAR(255) NOT NULL UNIQUE,
      data JSONB NOT NULL
  );
  ```

### E. Partition Properties Seeding (Post-Deploy)
- [x] Chạy script `scripts/seed-partition-osdu.sh` hoặc lệnh thủ công
- [x] Properties đã seed:
  - [x] `compliance-ruleset`, `elastic-*`, `storage-account-name`, `redis-database`
  - [x] `entitlements.datasource.*` (url, username, password, schema)
  - [x] `legal.datasource.*`
  - [x] `storage.datasource.*`
  - [x] `schema.datasource.*`
  - [x] `file.datasource.*`
- [x] Verify: `curl http://osdu-partition:8080/api/partition/v1/partitions` → `["osdu"]`

### F. Services Status
- [x] osdu-partition Running
- [x] osdu-entitlements Running (0.28.2-SNAPSHOT)
- [x] osdu-storage Running (0.28.6-SNAPSHOT)
- [x] osdu-legal Running (0.28.1-SNAPSHOT)
- [x] osdu-schema Running (0.28.1-SNAPSHOT)
- [x] osdu-file Running (0.28.1-SNAPSHOT)

### G. Smoke Tests
- [x] Partition: `curl http://osdu-partition:8080/api/partition/v1/partitions`
- [x] Entitlements: `curl http://osdu-entitlements:8080/api/entitlements/v2/info`
- [x] Storage: `curl http://osdu-storage:8080/api/storage/v2/info`
- [x] Legal: `curl http://osdu-legal:8080/api/legal/v1/info`
- [x] Schema: `curl http://osdu-schema:8080/api/schema-service/v1/info`
- [x] File: `curl http://osdu-file:8080/api/file/v2/info`

### H. Issues Encountered & Resolved
- [x] Issue 1: Redis connection - Fixed by adding REDIS_STORAGE_HOST, REDIS_GROUP_HOST
- [x] Issue 2: Partition DB auth - Fixed by using PARTITION_POSTGRESQL_USERNAME (not POSTGRES)
- [x] Issue 3: OSM schema missing - Fixed by creating partition_property table manually
- [x] Issue 4: Missing datasource properties - Fixed by seeding partition properties
- [x] Issue 5: Sensitive property pattern - Fixed by using env var names, not values
- [x] Issue 6: Schema/File UnknownHost - Fixed by adding PARTITION_API to ConfigMap
- [x] Issue 7: ArgoCD value+valueFrom conflict - Fixed by removing redundant patches

### I. Artifacts
- [x] Runbook: `docs/osdu/36-step18-osdu-core-services-runbook.md`
- [x] Partition properties doc: `docs/osdu/35-partition-osdu-properties.md`
- [x] Seed script: `scripts/seed-partition-osdu.sh`

**Tài liệu chi tiết:** `docs/osdu/36-step18-osdu-core-services-runbook.md`

## Step 19 - OSDU Core Services Smoke Tests & Bootstrap

### A. Prerequisites
- [ ] Step 14 (Keycloak) completed - có user test với token
- [ ] Step 15 (Ceph) completed - S3 storage ready
- [ ] Step 16 (OSDU Deps) completed - Postgres, OpenSearch, Redis, Redpanda running
- [ ] Step 18 (OSDU Core Deploy) completed - 6 core services running

### B. Bootstrap Database Schemas (One-time)
- [ ] Entitlements DB schema created (`scripts/bootstrap/02-init-db-schemas.sh`)
  - [ ] Table `member` with `partition_id` column
  - [ ] Table `"group"` with `partition_id` column
  - [ ] Table `member_to_group`
  - [ ] Table `embedded_group` (parent_id, child_id)
- [ ] Legal DB schema created
  - [ ] Schema `osdu` exists
  - [ ] Table `osdu."LegalTagOsm"` with `pk BIGSERIAL`

### C. Initialize Partition Properties
- [ ] Run `scripts/bootstrap/01-init-partition.sh osdu`
- [ ] Verify partition has all required properties:
  - [ ] TenantInfo: name, dataPartitionId, projectId, crmAccountID (JSON array!)
  - [ ] complianceRuleSet (camelCase), domain, gcpProjectId
  - [ ] osm.postgres.datasource.* properties
  - [ ] obm.minio.* properties (endpoint, accessKey, secretKey, bucket)
  - [ ] legal-tag-allowed-* properties
  - [ ] All service datasource properties

### D. Configure Service Environment Variables
- [ ] Entitlements service env vars (Repo-first: update deployment YAML)
  - [ ] REDIS_USER_INFO_HOST, REDIS_USER_INFO_PORT
  - [ ] REDIS_USER_GROUPS_HOST, REDIS_USER_GROUPS_PORT
  - [ ] POSTGRES_PASSWORD
- [ ] Legal service env vars (Repo-first: update deployment YAML)
  - [ ] PARTITION_HOST, PARTITION_API, PARTITION_SERVICE_ENDPOINT
  - [ ] ENTITLEMENTS_HOST, ENTITLEMENTS_URL, AUTHORIZE_API
  - [ ] OBM_MINIO_SECRET_KEY (from Ceph secret)
- [ ] Restart services after env changes

### E. Bootstrap Entitlements Data
- [ ] Run `scripts/bootstrap/03-init-entitlements.sh test@osdu.internal osdu`
- [ ] Verify user email matches JWT claim (check Keycloak user email)
- [ ] Verify groups created:
  - [ ] users, users.datalake.ops, users.datalake.admins
  - [ ] service.legal.user, service.legal.admin, service.legal.editor
  - [ ] service.storage.*, service.schema-service.*

### F. Smoke Tests
- [ ] Entitlements: GET /api/entitlements/v2/groups → 200 with groups list
- [ ] Legal: POST /api/legal/v1/legaltags → 201 (create tag)
- [ ] Legal: GET /api/legal/v1/legaltags → 200 with tags list
- [ ] Schema: GET /api/schema-service/v1/info → 200
- [ ] Storage: GET /api/storage/v2/info → 200

### G. Evidence & Documentation
- [ ] Save test outputs to `artifacts/step19-smoke-tests/`
- [ ] Update deployment YAMLs with env vars (Repo-first)
- [ ] Commit bootstrap scripts
- [ ] Document troubleshooting notes if any

## Step 19 - OSDU Core Services Complete (UPDATED)

### A. Prerequisites
- [x] Step 14 (Keycloak) completed - có user test với token
- [x] Step 15 (Ceph) completed - S3 storage ready
- [x] Step 16 (OSDU Deps) completed - Postgres, OpenSearch, Redis, Redpanda running
- [x] Step 18 (OSDU Core Deploy) completed - 6 core services deployed

### B. Kustomize Patch Consolidation
- [x] Issue: Multiple patches per deployment caused merge conflicts
  - [x] Error: `valueFrom: Invalid value: may not be specified when value is not empty`
- [x] Solution: Consolidated patches into single files per service
  - [x] Created `patch-entitlements-all.yaml` (merged 3 files)
  - [x] Created `patch-legal-all.yaml` (merged 1 file)
- [x] Removed old patch files:
  - [x] `patch-entitlements.yaml`
  - [x] `patch-entitlements-db.yaml`
  - [x] `patch-entitlements-redis.yaml`
  - [x] `patch-legal-env.yaml`

### C. Legal Service - Ceph Secret
- [x] Issue: `secret "rook-ceph-object-user-osdu-store-osdu-s3-user" not found`
- [x] Solution: Copy secret from rook-ceph to osdu-core namespace
```bash
  kubectl get secret rook-ceph-object-user-osdu-store-osdu-s3-user \
    -n rook-ceph -o yaml | grep -v "namespace:" | kubectl apply -n osdu-core -f -
```

### D. Storage Service - Messaging Backend Migration
- [x] Issue: CrashLoopBackOff with `RabbitMQ Retry Mechanism has a wrong configuration`
- [x] Root cause: Core Plus image has hardcoded RabbitMQ validation
- [x] Failed attempts:
  - [x] Configure RabbitMQ with DLX/DLQ - validation still failed
  - [x] Add env vars to disable retry - no effect (hardcoded)
  - [x] Try different queue naming conventions - still failed
- [x] Solution: Migrate from RabbitMQ to Kafka/Redpanda
  - [x] Delete partition: `curl -X DELETE .../partitions/osdu`
  - [x] Recreate partition with ONLY `oqm.kafka.*` properties (no `oqm.rabbitmq.*`)
  - [x] Flush Redis cache: `redis-cli FLUSHALL`
  - [x] Create `patch-storage-kafka.yaml` with `OQM_DRIVER=kafka`
  - [x] Apply and verify Storage pod Running

### E. Final Partition Properties (OQM)
- [x] `oqm.kafka.bootstrap-servers`: `osdu-redpanda.osdu-data.svc.cluster.local:9092`
- [x] `oqm.kafka.partition-count`: `1`
- [x] `oqm.kafka.replication-factor`: `1`
- [x] `oqm.kafka.security.protocol`: `PLAINTEXT`
- [x] No `oqm.rabbitmq.*` properties (removed)

### F. Services Status - ALL OPERATIONAL
- [x] Partition:    HTTP 200 ✅
- [x] Entitlements: HTTP 200 ✅
- [x] Legal:        HTTP 200 ✅
- [x] Schema:       HTTP 200 ✅
- [x] File:         HTTP 200 ✅
- [x] Storage:      HTTP 200 ✅

### G. Smoke Test Script
```bash
kubectl -n osdu-core exec deploy/osdu-toolbox -- bash -c '
TOKEN=$(curl -s -X POST "http://keycloak:80/realms/osdu/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=osdu-cli&username=test&password=Test@12345" | \
  grep -o "\"access_token\":\"[^\"]*" | cut -d"\"" -f4)
echo "1. Partition:    $(curl -s -w "%{http_code}" -o /dev/null http://osdu-partition:8080/api/partition/v1/partitions/osdu -H "data-partition-id: osdu")"
echo "2. Entitlements: $(curl -s -w "%{http_code}" -o /dev/null http://osdu-entitlements:8080/api/entitlements/v2/groups -H "data-partition-id: osdu" -H "Authorization: Bearer $TOKEN")"
echo "3. Legal:        $(curl -s -w "%{http_code}" -o /dev/null http://osdu-legal:8080/api/legal/v1/legaltags -H "data-partition-id: osdu" -H "X-Forwarded-Proto: https" -H "Authorization: Bearer $TOKEN")"
echo "4. Schema:       $(curl -s -w "%{http_code}" -o /dev/null http://osdu-schema:8080/api/schema-service/v1/info -H "data-partition-id: osdu" -H "Authorization: Bearer $TOKEN")"
echo "5. File:         $(curl -s -w "%{http_code}" -o /dev/null http://osdu-file:8080/api/file/v2/info -H "data-partition-id: osdu" -H "Authorization: Bearer $TOKEN")"
echo "6. Storage:      $(curl -s -w "%{http_code}" -o /dev/null http://osdu-storage:8080/api/storage/v2/info -H "data-partition-id: osdu" -H "Authorization: Bearer $TOKEN")"
'
```

### H. Production Readiness Assessment
- [x] Current setup: **POC/UAT only**
- [ ] Production requirements (future):
  - [ ] Redpanda: 3-node cluster with persistent storage
  - [ ] Replication factor: 3
  - [ ] TLS + SASL/SCRAM authentication
  - [ ] Monitoring & alerting

### I. Git Commits
- [x] `e51ccf1` - Step 19: OSDU Core Services POC complete (5/6)
- [x] `65d3334` - Cleanup: Remove old patch files
- [x] `efa7f61` - Step 19 COMPLETE: All 6 OSDU Core Services operational

### J. Files Changed
```
k8s/osdu/core/overlays/do-private/
├── kustomization.yaml (updated)
└── patches/
    ├── patch-entitlements-all.yaml (NEW - consolidated)
    ├── patch-legal-all.yaml (NEW - consolidated)
    ├── patch-storage-kafka.yaml (NEW - Kafka driver)
    └── patch-partition-env.yaml (existing)
```

### K. Artifacts
- [x] Documentation: `docs/40-step19-osdu-core-services.md`
- [x] Partition backup: `/tmp/partition-backup.json` (on ToolServer01)

**Tài liệu chi tiết:** `docs/osdu/40-step19-osdu-core-services.md`


## Step 20 — Smoke Tests & RabbitMQ Fix

### Mục tiêu
Thực hiện smoke tests và fix các issues phát hiện được.

### Checklist

- [x] **RabbitMQ Deployment**
  - [x] Deploy RabbitMQ cho messaging (legaltags-changed events)
  - [x] File: `k8s/osdu/deps/rabbitmq/rabbitmq-deploy.yaml`

- [x] **Storage Service Fix**
  - [x] RabbitMQ retry bypass (rabbitmqRetryDelay=0)
  - [x] Patch: `patches/patch-storage-rabbitmq.yaml`

- [x] **File Service Fix**
  - [x] Add ENTITLEMENTS_HOST env var
  - [x] Patch: `patches/patch-file-entitlements.yaml`

- [x] **Bootstrap Data**
  - [x] Partition properties (RabbitMQ connection)
  - [x] Entitlements groups (search groups)
  - [x] S3 Buckets (osdu-storage, osdu-file)

- [x] **Services Status**
  - [x] Partition: 200 OK
  - [x] Entitlements: 200 OK
  - [x] Legal: 200 OK
  - [x] Schema: 200 OK
  - [x] Storage: 200 OK (fixed)
  - [ ] File: 401 (needs Search service)
  - [ ] Search: Not deployed

**Tài liệu chi tiết:** `docs/osdu/50-step20-smoke-tests.md`

---

## Step 21 — Fix OutOfSync & Integrate RabbitMQ GitOps

### Mục tiêu
1. Fix osdu-file và osdu-storage bị OutOfSync trong ArgoCD
2. Tích hợp RabbitMQ vào ArgoCD app `osdu-deps`

### Checklist

#### A. Fix OutOfSync (osdu-core)

- [x] **Root Cause Analysis**
  - [x] Error: `spec.template.spec.containers[0].image: Required value`
  - [x] Cause: Patch container name không match với base
  - [x] patch-storage-rabbitmq.yaml: `osdu-storage` → `storage`
  - [x] patch-file-entitlements.yaml: `osdu-file` → `file`

- [x] **Fix Patches**
  - [x] Update container names trong patches
  - [x] Validate: `kubectl kustomize k8s/osdu/core/overlays/do-private`
  - [x] Commit/Push

- [x] **Verify**
  - [x] ArgoCD app `osdu-core` Synced & Healthy
  - [x] osdu-storage pod Running 1/1
  - [x] osdu-file pod Running 1/1

#### B. Integrate RabbitMQ into GitOps

- [x] **Restructure**
  - [x] Move `rabbitmq-deploy.yaml` to `deps/base/rabbitmq/`
  - [x] Create `deps/base/rabbitmq/kustomization.yaml`
  - [x] Update `deps/overlays/do-private/kustomization.yaml` to include rabbitmq

- [x] **Fix Probe Timeouts**
  - [x] Add `timeoutSeconds: 10` (default 1s was too short)
  - [x] Increase `initialDelaySeconds` for liveness: 30 → 60
  - [x] Add `failureThreshold: 3` explicitly

- [x] **Cleanup Old ReplicaSets**
  - [x] Scale down old RS: `kubectl -n osdu-data scale rs <old-rs> --replicas=0`
  - [x] Delete CrashLoopBackOff pod

- [x] **Verify**
  - [x] ArgoCD app `osdu-deps` Synced & Healthy
  - [x] RabbitMQ pod Running 1/1
  - [x] Probe config applied: `timeoutSeconds: 10`

#### C. Final Verification

- [x] **ArgoCD Apps Status**
  ```
  app-of-apps-observability   Synced   Healthy
  app-of-apps-osdu            Synced   Healthy
  obs-ingress                 Synced   Healthy
  obs-kube-prometheus-stack   Synced   Healthy
  obs-loki                    Synced   Healthy
  osdu-ceph                   Synced   Healthy
  osdu-core                   Synced   Healthy
  osdu-deps                   Synced   Healthy
  osdu-identity               Synced   Healthy
  ```

- [x] **OSDU Core Services**
  | Service | Pod | Health | Notes |
  |---------|-----|--------|-------|
  | Partition | 1/1 Running | 200 | ✅ |
  | Entitlements | 1/1 Running | 401 | ✅ (requires auth) |
  | Legal | 1/1 Running | 401 | ✅ (requires auth) |
  | Schema | 1/1 Running | 200 | ✅ |
  | Storage | 1/1 Running | 404 | ✅ (different endpoint) |
  | File | 1/1 Running | 404 | ✅ (different endpoint) |

- [x] **Dependencies**
  | Component | Status |
  |-----------|--------|
  | PostgreSQL | 1/1 Running |
  | OpenSearch | 1/1 Running |
  | Redis | 1/1 Running |
  | Redpanda | 1/1 Running |
  | RabbitMQ | 1/1 Running |
  | Keycloak | 1/1 Running |

- [x] **RabbitMQ Connectivity**
  - [x] `curl http://osdu-rabbitmq.osdu-data:15672` → 200

- [x] **Evidence**
  - [x] Artifacts saved: `artifacts/step21-rabbitmq-gitops/<timestamp>/`

**Tài liệu chi tiết:** `docs/osdu/51-step21-outofsync-rabbitmq-gitops.md`


## Step 22 — Storage Service RabbitMQ Fix

**Goal:** Khắc phục lỗi khởi động của Storage Service liên quan đến cơ chế Dead Lettering và Replay của RabbitMQ trên Image Core Plus.

### A. Hạ tầng RabbitMQ (Repo-first)
- [x] Cập nhật định nghĩa RabbitMQ trong `k8s/osdu/deps/base/rabbitmq/rabbitmq-deploy.yaml`:
  - [x] Thêm exchange `dead-lettering-replay` (topic).
  - [x] Thêm exchange `dead-lettering-replay-subscription` (topic).
  - [x] Thêm queue `dead-lettering-replay-subscription`.
  - [x] Cấu hình các Bindings cần thiết cho luồng Dead Lettering.
- [x] Áp dụng cấu hình RabbitMQ mới qua ArgoCD (`osdu-deps`).

### B. Cấu hình Storage Service (Repo-first)
- [x] Cập nhật bản vá `k8s/osdu/core/overlays/do-private/patches/patch-storage-rabbitmq.yaml` để bypass các check không cần thiết cho POC:
  - [x] Thiết lập `FEATURE_REPLAY_ENABLED=false`.
  - [x] Thiết lập `DEAD_LETTERING_REQUIRED=false`.
- [x] Đẩy các thay đổi lên Git và kiểm tra trạng thái Sync trên ArgoCD.

### C. Khởi tạo dữ liệu và Runtime (Bootstrap)
- [x] Cập nhật Partition Properties để bao gồm các thông số Replay/Dead-lettering cho RabbitMQ:
  - [x] `oqm.rabbitmq.replay.topic/subscription`.
  - [x] `oqm.rabbitmq.dead-lettering.topic/subscription`.
- [x] Thực hiện lệnh xóa cache: `redis-cli -h osdu-redis FLUSHALL`.
- [ ] Hoàn thiện script bootstrap tự động: `scripts/bootstrap/init-partition-osdu.sh`.

### D. Nghiệm thu
- [x] Xác nhận Pod `osdu-storage` chuyển trạng thái sang **1/1 Running**.
- [x] Kiểm tra log không còn lỗi `Required subscription not exists`.

### E. Evidence
- [x] Artifacts saved: `artifacts/step22-storage-fix/`
- [x] Documentation: `docs/osdu/42-step22-storage-rabbitmq-fix.md`

**Tài liệu chi tiết:** `docs/osdu/52-step22-storage-rabbitmq-fix.md`

## Step 22: Indexer Deployment Checklist

### Phase 1: Pre-deployment Verification

#### 1.1 Infrastructure Dependencies
- [x] OpenSearch pod Running (1/1)
- [x] RabbitMQ pod Running (1/1)
- [x] Redis pod Running (1/1)
- [x] PostgreSQL pod Running (1/1)

#### 1.2 OSDU Services Dependencies
- [x] Partition service healthy (200 OK)
- [x] Entitlements service healthy (200 OK)
- [x] Storage service healthy (200 OK)
- [x] Schema service healthy (200 OK)
- [x] Search service healthy (200 OK)

---

### Phase 2: RabbitMQ Topology Setup

#### 2.1 Exchanges
- [x] `records-changed` exchange exists (type: topic, durable: true)
- [x] `schema-changed` exchange exists (type: topic, durable: true)
- [x] `reprocess` exchange exists (type: topic, durable: true)
- [x] `reindex` exchange exists (type: topic, durable: true) — **Created during deployment**

#### 2.2 Queues
- [x] `indexer-records-changed` queue exists
- [x] `indexer-schema-changed` queue exists
- [x] `indexer-reprocess` queue exists — **Created during deployment**
- [x] `indexer-reindex` queue exists — **Created during deployment**

#### 2.3 Bindings
- [x] `records-changed` → `indexer-records-changed` (routing_key: #)
- [x] `schema-changed` → `indexer-schema-changed` (routing_key: #)
- [x] `reprocess` → `indexer-reprocess` (routing_key: #) — **Created during deployment**
- [x] `reindex` → `indexer-reindex` (routing_key: #) — **Created during deployment**

#### 2.4 Verification Commands
```bash
# Exchanges
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_exchanges name type | grep -E "records|schema|reprocess|reindex"

# Queues
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_queues name messages | grep indexer

# Bindings
kubectl -n osdu-data exec deploy/osdu-rabbitmq -- rabbitmqctl list_bindings source_name destination_name | grep -E "reindex|reprocess"
```

---

### Phase 3: Indexer Configuration

#### 3.1 Redis Environment Variables
- [x] `REDIS_HOST` = `osdu-redis.osdu-data.svc.cluster.local`
- [x] `REDIS_PORT` = `6379`
- [x] `REDIS_SEARCH_HOST` = `osdu-redis.osdu-data.svc.cluster.local` — **Critical fix**
- [x] `REDIS_SEARCH_PORT` = `6379` — **Critical fix**
- [x] `REDIS_CACHE_HOST` = `osdu-redis.osdu-data.svc.cluster.local`
- [x] `SPRING_REDIS_HOST` = `osdu-redis.osdu-data.svc.cluster.local`
- [x] `SPRING_DATA_REDIS_HOST` = `osdu-redis.osdu-data.svc.cluster.local`
- [x] `SPRING_DATA_REDIS_PORT` = `6379`

#### 3.2 Other Critical Env Vars
- [x] `ELASTIC_HOST` configured
- [x] `ELASTIC_PORT` = `9200`
- [x] `ELASTIC_SCHEME` = `http`
- [x] `PARTITION_API` configured
- [x] `ENTITLEMENTS_API` configured
- [x] `STORAGE_API` configured
- [x] `SCHEMA_API` configured

---

### Phase 4: Deployment

#### 4.1 Deploy Indexer
- [x] ArgoCD sync or kubectl apply
- [x] Pod created successfully
- [x] Pod status: Running
- [x] Ready: 1/1

#### 4.2 Startup Logs Verification
- [x] `Started IndexerCorePlusApplication` in logs
- [x] No `UnknownHostException` errors
- [x] No `404 NOT_FOUND` errors
- [x] 4x `Subscriber REGISTERED` messages

---

### Phase 5: Post-deployment Verification

#### 5.1 Health Checks
- [x] Indexer pod Running 1/1
- [x] No restarts (or minimal)
- [x] Health endpoint responds

#### 5.2 Functional Verification
- [x] Consumers listening on all 4 queues
- [x] Can receive messages from RabbitMQ
- [x] Can connect to OpenSearch
- [x] Can connect to Redis

---

### Phase 6: Repo-first Compliance

#### 6.1 Update Repository
- [ ] Update `indexer-deploy.yaml` with Redis env vars
- [ ] Export RabbitMQ definitions to `definitions.json`
- [ ] Commit and push changes
- [ ] ArgoCD synced with repo

#### 6.2 Documentation
- [ ] Deployment document created
- [ ] Checklist completed
- [ ] Issues documented
- [ ] Runtime config documented

---

### Issues Encountered & Resolutions

#### Issue #1: Exchange `reindex` missing
| Field | Value |
|-------|-------|
| Symptom | `404 NOT_FOUND` for `/api/exchanges/%2F/reindex` |
| Root Cause | Exchange not created in RabbitMQ |
| Resolution | Created via HTTP API |
| Command | `curl -X PUT ... "http://osdu-rabbitmq:15672/api/exchanges/%2F/reindex"` |

#### Issue #2: Queue `indexer-reprocess` missing
| Field | Value |
|-------|-------|
| Symptom | `NOT_FOUND - no queue 'indexer-reprocess'` |
| Root Cause | Queue not created, binding missing |
| Resolution | Created queue via rabbitmqctl, binding via HTTP API |

#### Issue #3: Redis host `redis-cache-search` not found
| Field | Value |
|-------|-------|
| Symptom | `UnknownHostException: redis-cache-search` |
| Root Cause | Missing `REDIS_SEARCH_HOST` env var |
| Resolution | Added `REDIS_SEARCH_HOST=osdu-redis.osdu-data.svc.cluster.local` |

#### Issue #4: Spring 6.x incompatibility with OQM plugin
| Field | Value |
|-------|-------|
| Symptom | `NoSuchMethodError: getStatusCode()` |
| Root Cause | OQM plugin built with Spring 5.x, Indexer uses Spring 6.x |
| Resolution | Workaround: Create all RabbitMQ topology before startup to avoid 404 |

#### Issue #5: Erlang syntax error in rabbitmqctl eval
| Field | Value |
|-------|-------|
| Symptom | `{:undef, [{:rabbit_exchange, :declare, ...}]}` |
| Root Cause | Different Erlang syntax required |
| Resolution | Use HTTP Management API instead of rabbitmqctl eval |

---

### Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Deployer | DevOps Team | 2026-01-20 | ✅ |
| Reviewer | | | |
| Approver | | | |

---

### Notes

1. **CRITICAL**: Always create RabbitMQ topology BEFORE starting Indexer to avoid Spring 6.x incompatibility issue
2. **CRITICAL**: `REDIS_SEARCH_HOST` is required - Indexer uses different env var than expected
3. RabbitMQ definitions should be exported and stored in repo for reproducibility
4. Consider upgrading OQM plugin to Spring 6.x compatible version in future


## Step 23 — Fix Legal & Storage OBM Configuration (Repo-first)

### Mục tiêu
Ghi nhận config OBM (Object Blob Management) vào repo để persist qua ArgoCD sync, đảm bảo Legal và Storage services có đủ config để kết nối S3/Ceph.

### A. Phân tích vấn đề
- [x] Xác định runtime config chưa được ghi vào repo
- [x] Phát hiện cross-namespace secret issue trong `patch-legal-all.yaml`
- [x] Xác định thiếu OBM env vars: `OBM_DRIVER`, `OBM_MINIO_ENDPOINT`, `OBM_MINIO_BUCKET`, `OBM_MINIO_ACCESS_KEY`

### B. Tạo Secret (Out-of-band)
- [ ] Chạy `scripts/create-s3-secret.sh` để tạo secret `osdu-s3-credentials` trong `osdu-core`
- [ ] Verify: `kubectl -n osdu-core get secret osdu-s3-credentials`

### C. Update Patches (Repo-first)
- [ ] Backup files cũ: `patch-legal-all.yaml.bak`, `patch-storage-openid.yaml.bak`
- [ ] Replace `patches/patch-legal-all.yaml` với version đã fix
- [ ] Replace `patches/patch-storage-openid.yaml` với version đã update (thêm OBM section)
- [ ] Validate: `kubectl kustomize k8s/osdu/core/overlays/do-private` thành công

### D. Git Commit
- [ ] `git add` các files thay đổi
- [ ] `git commit -m "step23: Fix Legal & Storage OBM config (repo-first)"`
- [ ] `git push origin main`

### E. Apply & Verify
- [ ] ArgoCD sync (hoặc đợi auto-sync)
- [ ] Verify Legal pod có 5 OBM env vars: `kubectl -n osdu-core exec deploy/osdu-legal -- env | grep -i OBM`
- [ ] Verify Storage pod có 5 OBM env vars: `kubectl -n osdu-core exec deploy/osdu-storage -- env | grep -i OBM`
- [ ] Test Legal API: GET /legaltags:properties returns JSON
- [ ] Test Legal API: POST /legaltags creates tag successfully

### F. Artifacts
- [ ] `artifacts/step23-fix-legal-obm/` created
- [ ] Evidence files committed (non-secret)

### Notes
- Secret values KHÔNG được commit vào Git
- Partition properties được seed bằng `scripts/seed-partition-osdu.sh`
- Container names trong patches: `legal`, `storage` (không phải `osdu-legal`, `osdu-storage`)

## Step 24 - Storage Service Fix
- [x] Legal 307 redirect fixed (SSL env vars)
- [x] Legal 500 fixed (LegalTagOsm in storage.osdu)
- [x] Storage search_path fixed (ALTER ROLE osduadmin)
- [x] S3 bucket created (osdu-poc-osdu-records)
- [x] Create Record: HTTP 201 ✅
- [x] Read Record: HTTP 200 ✅
- [x] Evidence saved: artifacts/step24-storage-fix/

## Step 24 - Storage Service Fix
### A. Issues Fixed
- [x] Legal HTTP 307 redirect → Added SSL disable env vars
- [x] Legal HTTP 500 (LegalTagOsm not found) → Created table in storage.osdu schema
- [x] Storage HTTP 500 (search_path) → ALTER ROLE osduadmin SET search_path
- [x] Storage HTTP 500 (NoSuchBucket) → Created osdu-poc-osdu-records bucket

### B. Repo-first Documentation
- [x] Env var patches committed to Git
- [x] PostgreSQL bootstrap script: `scripts/osdu/bootstrap-postgres-osdu-schema.sql`
- [x] S3 bootstrap script: `scripts/osdu/bootstrap-s3-buckets.sh`
- [x] Step documentation: `docs/osdu/40-step24-storage-fix.md`

### C. Test Results
- [x] Create Record: HTTP 201 ✅
- [x] Read Record: HTTP 200 ✅
- [x] Evidence saved: `artifacts/step24-storage-fix/`

### D. Key Learnings
- OSM uses shared datasource (storage DB) for all services
- PostgreSQL search_path: Role-level overrides database-level
- Spring Security requires multiple env vars to disable HTTPS redirect
- Bucket naming convention: {gcpProjectId}-osdu-records

## Step 25 - Search Service Fix (OpenSearch Proxy)
- [x] Identified root cause: ES 8.x client incompatible with OpenSearch 2.x
- [x] Deployed opensearch-proxy (Nginx) to rewrite headers
- [x] Added X-Elastic-Product header for ES 8.x client
- [x] Updated partition property elasticsearch.8.host to proxy
- [x] ArgoCD Application created for opensearch-proxy
- [x] Partition properties documented in repo
- [x] All 8 OSDU services running 1/1
- [x] Search API returns valid response
- [x] Git commits pushed to main
