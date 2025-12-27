# Step 7 — Self-managed Load Balancer on AppServer01 (HAProxy)

## Goal
Provide a stable private endpoint (AppServer01) for HTTP/HTTPS to Kubernetes ingress-nginx NodePorts.

Traffic flow:
ToolServer01/VPN -> AppServer01:80/443 -> WorkerNode01/02:30080/30443 -> ingress-nginx -> Ingress/Services

## Why HAProxy
- Simple, reliable
- Supports TCP passthrough for 443
- Easy health checks and evidence capture

## Precheck
Evidence:
- artifacts/step7-lb-appserver01/AppServer01/ss-80-443.txt
- artifacts/step7-lb-appserver01/AppServer01/backend-tcp-precheck.txt
s step exists
In this project we run Kubernetes in **private-only** mode on DigitalOcean VPC.

We deliberately use:
- **Ingress-NGINX as NodePort** on workers (HTTP `30080`, HTTPS `30443`), no DO Load Balancer.
- A **stable control-plane endpoint** `k8s-api.internal:6443` (required by kubeadm HA best practice).

AppServer01 is the **single internal LB endpoint** that:
- Exposes **Kubernetes API** on `6443` and forwards to `controlplane01/02/03:6443`.
- Exposes **Ingress HTTP/HTTPS** on `80/443` and forwards to `workernode01/02:30080/30443`.

> Notes
> - This is an *internal* LB. Opening ports to the public internet is out of scope at this stage.
> - Later we can add HA (2x LB + VRRP) but current scope is 1 LB.

---

## Topology
- LB: AppServer01 `10.118.0.8`
- ControlPlanes: `10.118.0.2/.3/.4`
- Workers: `10.118.0.6/.7`

DNS/hosts:
- `k8s-api.internal -> 10.118.0.8`

---

## Firewall (DigitalOcean)
On the DO firewall attached to **AppServer01**, allow inbound (private only):
- TCP `6443` from `10.118.0.0/20` (and optionally from VPN CIDR if you route it)
- TCP `80,443` from `10.118.0.0/20` (and optionally VPN CIDR)

Keep SSH restricted (e.g. only from ToolServer01/VPN).

Evidence is captured in:
- `docs/11-firewall-do.md`

---

## Repo-first implementation
### Files
- Playbook: `ansible/playbooks/31-appserver01-lb-haproxy.yml`
- Template: `ansible/templates/haproxy.cfg.j2`

Inventory groups:
- `lb`: AppServer01
- `k8s_cluster/controlplane`: ControlPlane01..03
- `k8s_cluster/worker`: WorkerNode01..02

### Variables
The playbook/template expects 2 lists:
- `lb_controlplanes`: list of CP nodes (name + ip)
- `lb_workers`: list of worker nodes (name + ip)

Recommended to define in group_vars (repo-first):
- `ansible/group_vars/lb.yml` (or wherever your repo keeps group vars)

---

## HAProxy config (final intent)
We use **TCP mode** for all three frontends:
- API is TLS (kube-apiserver), so TCP passthrough.
- HTTPS is TLS passthrough.
- HTTP NodePort can be checked with TCP to avoid false DOWN due to 404.

Health-check guidance:
- **Do not** use `httpchk GET /` against ingress NodePort unless you route a guaranteed-200 path.
- In this repo we use `option tcp-check` for port `30080` to avoid `Layer7 wrong status: 404`.

---

## Run (ToolServer01)
Make sure Ansible uses the repo config/inventory:

```bash
cd /opt/infra-osdu-do
source .venv/bin/activate
export ANSIBLE_CONFIG=/opt/infra-osdu-do/ansible/ansible.cfg

ansible-inventory --graph
ansible-playbook ansible/playbooks/31-appserver01-lb-haproxy.yml -l AppServer01 \
  | tee artifacts/step7-lb-appserver01/run-appserver01-haproxy.log
```

---

## Verify
### 1) HAProxy service + listening ports (on AppServer01)
```bash
ssh ops@10.118.0.8 'sudo systemctl --no-pager -l status haproxy | head -n 60'
ssh ops@10.118.0.8 'sudo haproxy -c -f /etc/haproxy/haproxy.cfg'
ssh ops@10.118.0.8 'sudo ss -lntp | egrep ":6443|:80|:443" || true'
```

### 2) TCP reachability from ToolServer01
```bash
for p in 6443 80 443; do
  timeout 2 bash -c "</dev/tcp/10.118.0.8/$p" && echo "LB_${p}_OK" || echo "LB_${p}_FAIL"
done

timeout 2 bash -c "</dev/tcp/k8s-api.internal/6443" && echo API_LB_OK || echo API_LB_FAIL
```

### 3) kubectl must work through `k8s-api.internal`
```bash
kubectl get nodes -o wide
```

### 4) Ingress routing via LB
```bash
curl -sS -H "Host: echo.internal" http://10.118.0.8/ | head
```

Evidence (expected in this project):
- `artifacts/step7-lb-appserver01/lb-tcp-ports.txt`
- `artifacts/step7-lb-appserver01/api-6443-after-fix.txt`
- `artifacts/step7-lb-appserver01/kubectl-get-nodes-after-fix.txt`
- `artifacts/step7-lb-appserver01/echo-via-lb-after-fix.txt`

---

## Known pitfalls (from this project)
1) **Ansible shows “No inventory was parsed”**
   - Root cause: forgot `export ANSIBLE_CONFIG=...` or wrong working directory.

2) **NodePort check marks backends DOWN with 404**
   - Root cause: ingress returns 404 on `/` if no default backend.
   - Fix: TCP check (preferred) or use an HTTP check against a guaranteed-200 virtual host/path.

3) **kubectl fails with `connection refused k8s-api.internal:6443`**
   - Check: DO firewall to AppServer01 allows 6443 from VPC.
   - Check: `k8s-api.internal` resolves to `10.118.0.8` on ToolServer01 and nodes.
   - Check: HAProxy actually binds `:6443` and backend points to CP private IPs.
