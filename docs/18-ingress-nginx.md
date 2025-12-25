# Step 6 — Ingress NGINX (DigitalOcean private-only NodePort)

## Goal
Deploy ingress-nginx as the cluster ingress controller for HTTP/HTTPS traffic in a **private-only** Kubernetes cluster.
Traffic flow (current phase):
ToolServer01 (VPN/VPC) -> WorkerNode NodePort (30080/30443) -> ingress-nginx -> Services/Ingress rules.

Later phase (Step 7):
Clients/VPN -> AppServer01 (self-managed LB) -> Worker NodePorts -> ingress-nginx.

## Design decisions
- Deployment mode: ingress-nginx with **Service type NodePort**
- NodePort pinned:
  - HTTP: 30080
  - HTTPS: 30443
- externalTrafficPolicy: **Local**
  - Keeps source IP semantics (later useful when behind AppServer01 LB)
  - Requires controller endpoints on every worker receiving traffic
- Scheduling:
  - Controller replicas = 2
  - Controller scheduled on **workers only**
  - Anti-affinity by hostname to spread across WorkerNode01/02

## Pre-requisites
- Kubernetes cluster healthy + CNI ready (Calico VXLAN private-only)
- DO Cloud Firewall (FW-CLUSTER-NODES) allows from VPC:
  - TCP 30080, 30443 from 10.118.0.0/20
- ToolServer01 has kubectl access

## Implementation (repo-first)
### 6.1 Prepare kustomize overlay
Path:
- k8s/ingress/ingress-nginx/base
- k8s/ingress/ingress-nginx/overlays/do-private-nodeport

Key overlay customizations:
- Force NodePort http/https to 30080/30443
- Set Service externalTrafficPolicy = Local
- Force controller to run on workers and spread across nodes

Commands used:
- kubectl diff -k <overlay>
- kubectl apply -k <overlay>

Evidence:
- artifacts/step6-ingress-nginx/kubectl-diff*.txt
- artifacts/step6-ingress-nginx/apply*.txt

### 6.2 Namespace + install
- Ensure namespace ingress-nginx exists
- Apply overlay manifests

Evidence:
- artifacts/step6-ingress-nginx/ns-get.txt
- artifacts/step6-ingress-nginx/kubectl-diff.txt
- artifacts/step6-ingress-nginx/apply*.txt

### 6.3 Rollout verification
Check controller rollout and services:
- kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller
- kubectl -n ingress-nginx get svc ingress-nginx-controller -o yaml

Evidence:
- artifacts/step6-ingress-nginx/rollout*.txt
- artifacts/step6-ingress-nginx/controller-svc*.yaml
- artifacts/step6-ingress-nginx/nodeports.txt

### 6.4 Issue & Fix log (important)
#### Issue A — kubectl diff/build errors (kustomize path/duplicate namespace)
Symptom:
- accumulating resources / base path not directory / duplicate Namespace id

Fix:
- Ensure base referenced correctly (directory path)
- Avoid declaring Namespace twice in base + overlay

Evidence:
- artifacts/step6-ingress-nginx/kubectl-diff.txt (initial failure/then success)
- artifacts/step6-ingress-nginx/ns-get.txt

#### Issue B — NodePort test FAIL on one worker
Initial state:
- externalTrafficPolicy: Local
- Controller only on WorkerNode01 => NodePort OK only on 10.118.0.6, FAIL on 10.118.0.7

Fix steps:
1) Open DO Firewall for TCP 30080/30443 from 10.118.0.0/20 (FW-CLUSTER-NODES)
2) Scale/spread controller pods across both workers (replicas=2 + nodeAffinity + podAntiAffinity)

Evidence:
- artifacts/step6-ingress-nginx/etp.txt
- artifacts/step6-ingress-nginx/controller-pods.txt (before)
- artifacts/step6-ingress-nginx/controller-pods-after.txt (after)
- artifacts/step6-ingress-nginx/nodeport-tcp-test.txt (before partial OK)
- artifacts/step6-ingress-nginx/nodeport-tcp-test-after-controller-workers.txt (after OK)

## End-to-end verification (routing test)
Deploy echo server + Ingress:
- Host: echo.internal
- Curl via both workers NodePort 30080 with Host header

Evidence:
- artifacts/step6-ingress-nginx/echo-apply.txt
- artifacts/step6-ingress-nginx/echo-rollout.txt
- artifacts/step6-ingress-nginx/echo-ingress-get.txt
- artifacts/step6-ingress-nginx/echo-curl.txt

Expected PASS criteria:
- Ingress controller pods Running on both WorkerNode01/02
- NodePort 30080/30443 reachable from ToolServer01 to both workers
- echo.internal routing works from both workers

## Notes / Next step
Next: Step 7 — Deploy self-managed LB on AppServer01 to forward:
- 80 -> workers:30080
- 443 -> workers:30443

