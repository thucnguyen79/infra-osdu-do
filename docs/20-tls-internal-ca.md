# Step 8 — TLS (Option A) Internal CA with cert-manager

## Goal
- Install **cert-manager** as the cluster certificate controller.
- Create an **Internal Root CA** and a **ClusterIssuer** for signing internal TLS certs.
- Issue a test certificate for `echo.internal` and verify TLS flow through:
  **AppServer01 (HAProxy TCP passthrough 443) -> ingress-nginx (TLS termination) -> Service/Pod**

## Why we need this step
- Kubernetes/OSDU add-ons (Ingress, web UIs, APIs) need HTTPS.
- With private-only networking, we usually avoid public ACME challenges and use **Internal CA**.
- cert-manager automates issuance/renewal and keeps cert lifecycle consistent.

## Scope / Assumptions (current environment)
- DO VPC: `10.118.0.0/20`, nodes use `eth1` private IP.
- Ingress NodePorts: `30080/30443` on workers.
- AppServer01 HAProxy:
  - `:443` TCP passthrough to workers `:30443`
  - `:80` to `:30080`
  - `:6443` to control planes `:6443`
- DNS/hosts:
  - `k8s-api.internal -> 10.118.0.8`
  - `echo.internal` will be tested via LB `10.118.0.8`

## Repo layout (suggested)
- `k8s/addons/cert-manager/`
  - `base/`
    - `kustomization.yaml`
    - `namespace.yaml` (if vendor does NOT include Namespace)
    - `vendor/cert-manager.yaml` (pinned version)
    - `patches/` (optional: delete vendor Namespace)
  - `overlays/do-private/`
    - `kustomization.yaml`
- `k8s/addons/tls-internal-ca/`
  - `internal-selfsigned-issuer.yaml`
  - `internal-root-ca-certificate.yaml`
  - `internal-ca-clusterissuer.yaml`
- `k8s/apps/echo/` (or wherever echo manifests live)
  - `certificate-echo-internal-tls.yaml`
  - ingress referencing `secretName: echo-internal-tls`

## Evidence locations
- Non-secret: `artifacts/step8-tls/`
- Secret material (avoid in docs): `artifacts-private/step8-tls/`
  - Do NOT commit `artifacts-private/` to git.

---

## 8.1 Install cert-manager (kustomize overlay)

### 8.1.1 Create evidence folder
```bash
mkdir -p artifacts/step8-tls
8.1.2 Pre-check: Namespace handling (IMPORTANT)
Problem we hit: may not add resource with an already registered id: Namespace.v1/.../cert-manager

This happens when vendor manifest already contains the Namespace cert-manager,
while we also add base/namespace.yaml.

Fix policy (choose one and document it):

Option 1 (simple): Remove base/namespace.yaml and rely on vendor Namespace. ( Chosen)
Option 2 (recommended repo-first): Keep base/namespace.yaml and delete vendor Namespace via kustomize patch.

Recommended (Option 2) patch file example:
k8s/addons/cert-manager/base/patches/delete-vendor-namespace.yaml

apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
$patch: delete

Then in base/kustomization.yaml:
resources:
  - namespace.yaml
  - vendor/cert-manager.yaml
patchesStrategicMerge:
  - patches/delete-vendor-namespace.yaml
  
8.1.3 Namespace exists before kubectl diff (IMPORTANT)
Problem we hit: Error from server (NotFound): namespaces "cert-manager" not found
kubectl diff/apply will query the live cluster; namespaced objects fail if ns doesn't exist.

Create ns first (if you manage namespace outside the vendor):
kubectl get ns cert-manager >/dev/null 2>&1 || kubectl create ns cert-manager
kubectl get ns cert-manager -o wide | tee artifacts/step8-tls/ns-cert-manager.txt

8.1.4 Diff then Apply
kubectl diff -k k8s/addons/cert-manager/overlays/do-private \
  | tee artifacts/step8-tls/cert-manager-diff.txt || true

kubectl apply -k k8s/addons/cert-manager/overlays/do-private \
  | tee artifacts/step8-tls/cert-manager-apply.txt
  
8.1.5 Verify
kubectl -n cert-manager get pods -o wide \
  | tee artifacts/step8-tls/cert-manager-pods.txt

kubectl get crd | grep cert-manager | head \
  | tee artifacts/step8-tls/cert-manager-crds.txt
Expected

3 pods running: cert-manager, cainjector, webhook

cert-manager CRDs present

8.2 Create Internal CA chain
8.2.1 Apply resources (repo-first)
Create/apply 3 resources:
internal-selfsigned Issuer (namespaced, in cert-manager)
internal-root-ca Certificate (isCA=true, stored as Secret internal-root-ca)
internal-ca ClusterIssuer (CA signer using Secret internal-root-ca)

Apply:
kubectl apply -f k8s/addons/tls-internal-ca/internal-selfsigned-issuer.yaml \
  | tee artifacts/step8-tls/internal-selfsigned-apply.txt

kubectl apply -f k8s/addons/tls-internal-ca/internal-root-ca-certificate.yaml \
  | tee artifacts/step8-tls/internal-root-ca-apply.txt

kubectl apply -f k8s/addons/tls-internal-ca/internal-ca-clusterissuer.yaml \
  | tee artifacts/step8-tls/internal-ca-clusterissuer-apply.txt
  
8.2.2 Verify readiness
kubectl get clusterissuer internal-ca -o wide \
  | tee artifacts/step8-tls/clusterissuer-internal-ca.txt

kubectl -n cert-manager get certificate internal-root-ca -o wide \
  | tee artifacts/step8-tls/cert-internal-root-ca.txt
  
Expected
internal-ca READY=True
internal-root-ca READY=True

NOTE: Do NOT dump full Secret YAML into artifacts/ because it contains the private key.
If you must capture it for incident recovery, store it in artifacts-private/step8-tls/ and never commit.

8.3 Issue a workload cert (echo.internal) + wire into Ingress
8.3.1 Apply Certificate for echo
kubectl apply -f k8s/apps/echo/certificate-echo-internal-tls.yaml \
  | tee artifacts/step8-tls/echo-cert-apply.txt
  
Verify:

kubectl -n default describe certificate echo-internal-tls \
  | tee artifacts/step8-tls/echo-cert-describe.txt
  
Expected
Certificate Ready=True
Secret exists: echo-internal-tls

8.3.2 Ensure Ingress references the TLS secret
Ingress must include:

spec:
  tls:
  - hosts:
    - echo.internal
    secretName: echo-internal-tls

Apply ingress manifests (kustomize or kubectl apply), capture output:
kubectl apply -f k8s/apps/echo/ingress.yaml \
  | tee artifacts/step8-tls/echo-ingress-apply.txt

kubectl get ingress echo -o wide \
  | tee artifacts/step8-tls/echo-ingress-get.txt
  
8.4 Verify end-to-end TLS
8.4.1 Export ONLY Root CA certificate (public cert) for client trust
kubectl -n cert-manager get secret internal-root-ca -o jsonpath='{.data.tls\.crt}' \
  | base64 -d > artifacts/step8-tls/internal-root-ca.crt
  
8.4.2 Test TLS via AppServer01 LB (443)
(Use resolve to avoid DNS dependency)
curl -sSk --resolve echo.internal:443:10.118.0.8 https://echo.internal/ | head

Now enforce trust using internal CA:
curl -sS --cacert artifacts/step8-tls/internal-root-ca.crt \
  --resolve echo.internal:443:10.118.0.8 https://echo.internal/ | head
  
Expected
HTTPS returns echo response JSON.
--cacert internal-root-ca.crt succeeds (no unknown CA error).

Troubleshooting / Issues we hit (and how we fixed)
Issue A — Duplicate Namespace (kustomize)
Symptom: may not add resource with an already registered id: Namespace.v1... cert-manager
Cause: Namespace is defined twice: vendor + our namespace.yaml.
Fix:Remove one Namespace definition, or delete vendor Namespace via kustomize patch ($patch: delete).

Issue B — Namespace not found during kubectl diff
Symptom:Error from server (NotFound): namespaces "cert-manager" not found
Cause:kubectl diff queries the live cluster; namespace must exist first.
Fix:Create ns before diff/apply OR ensure vendor includes Namespace and it is applied first.

Issue C — Wrong path treated as directory/file (kustomize)
Symptom:... file is not directory / must resolve to a file
Cause:Mis-referenced resources in kustomization (pointing to a file where a directory expected, or vice versa).
Fix:Ensure resources: entries are correct:
YAML file -> file path
base/overlay -> directory path with its own kustomization.yaml

Exit criteria (Step 8 done)
kubectl -n cert-manager get pods all Running
kubectl get clusterissuer internal-ca READY=True
kubectl -n default describe certificate echo-internal-tls Ready=True
HTTPS test via LB works using --cacert internal-root-ca.crt

Next step preview (Step 9)
Storage + foundational add-ons for OSDU workloads (dynamic provisioning, default StorageClass, etc.)
