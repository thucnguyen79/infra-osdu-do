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

# STEP 5 — Install CNI
- [ ] Step 5.1 Verify kubeadm CIDRs (podSubnet/serviceSubnet)
- [ ] Step 5.2 Prepare Calico VXLAN manifest (repo-first)
- [ ] Step 5.3 Allow UDP 4789 within VPC (cloud firewall / host firewall if any)
- [ ] Step 5.4 Apply CNI + verify nodes Ready + CoreDNS Running
- [ ] Step 5.5 Save evidence + commit
- [ ] DS/calico-node Ready 5/5
- [ ] IP_AUTODETECTION_METHOD pinned to eth1 (DO dual NIC)
- [ ] Evidence saved: artifacts/step5-cni/*
- [ ] 5.x Collect evidence for calico-node CrashLoopBackOff (describe/events/logs previous)
- [ ] 5.x Patch Calico probes for VXLAN (felix-only) OR allow BGP port 179
- [ ] 5.x Verify rollout ds/calico-node == ready on all nodes
- [ ] 5.x Verify node-to-node pod networking (ping test pod)

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
###A) Monitoring Core
-[x] Namespace observability tồn tại
-[x] CRDs monitoring.coreos.com đầy đủ (có Alertmanager/Prometheus/ThanosRuler…)
-[x] Pods Monitoring Running (Grafana/Prometheus/Alertmanager/Operator)

###B) Ingress + TLS Internal CA
-[x] Có 3 ingress đúng host: grafana/prometheus/alertmanager .internal
-[x] Có 3 certificate READY=True
-[x] HTTP 308 → HTTPS
-[x] HTTPS verify CA OK (Grafana login 302; Prometheus/Alertmanager readiness nên 200)

###C) Logging (Loki + Promtail)
-[x] Loki Running
-[x] PVC Loki Bound (retain SC)
-[x] Promtail chạy đủ node
-[x] Grafana query được log từ Loki
-[x] values-loki.yaml đã fix đúng (schemaConfig…)
