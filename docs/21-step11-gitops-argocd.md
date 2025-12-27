# Step 11 — GitOps (Argo CD)

## Mục tiêu
- Cài **Argo CD** để quản lý triển khai Kubernetes theo **GitOps** (Git là nguồn sự thật).
- Chuẩn hóa việc deploy các add-ons/OSDU: mọi thay đổi đi qua PR/commit, Argo CD sẽ sync vào cluster.

## Công cụ & ý nghĩa
- **Argo CD**: Continuous Delivery theo GitOps cho Kubernetes (theo dõi repo, so diff, sync, rollback).
- **Kustomize** (qua `kubectl -k`): quản lý overlays theo môi trường (`do-private`).
- **Ingress-NGINX + cert-manager**: xuất Argo CD UI ra domain nội bộ `argocd.internal` với TLS từ internal CA.

## Repo structure (repo-first)
Tạo (hoặc copy) các file sau vào repo:
- `k8s/addons/gitops/argocd/base/vendor/install.yaml`  (manifest Argo CD)
- `k8s/addons/gitops/argocd/base/kustomization.yaml`
- `k8s/addons/gitops/argocd/base/patches/patch-argocd-cm.yaml`
- `k8s/addons/gitops/argocd/base/patches/patch-argocd-cmd-params.yaml`
- `k8s/addons/gitops/argocd/overlays/do-private/kustomization.yaml`
- `k8s/addons/gitops/argocd/overlays/do-private/argocd-certificate.yaml`
- `k8s/addons/gitops/argocd/overlays/do-private/argocd-ingress.yaml`

## Runbook (ToolServer01)

### 11.1 Chuẩn bị thư mục artifacts
```bash
mkdir -p artifacts/step11-gitops
```

### 11.2 Tạo namespace
```bash
kubectl get ns argocd || kubectl create ns argocd
kubectl get ns argocd | tee artifacts/step11-gitops/ns-argocd.txt
```
**Kỳ vọng:** namespace `argocd` trạng thái `Active`.

### 11.3 Vendor manifest Argo CD (pin version)
Khuyến nghị pin version ổn định (ví dụ v3.2.2):
```bash
ARGOCD_VER=v3.2.2
mkdir -p k8s/addons/gitops/argocd/base/vendor
curl -fsSL "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VER}/manifests/install.yaml"   -o k8s/addons/gitops/argocd/base/vendor/install.yaml
wc -l k8s/addons/gitops/argocd/base/vendor/install.yaml | tee artifacts/step11-gitops/argocd-install-wc.txt
```
> Lưu ý: do bạn từng gặp lỗi “annotations too long”, khi apply nên ưu tiên `--server-side` để tránh `kubectl.kubernetes.io/last-applied-configuration` phình to.

### 11.4 Diff (lần đầu có thể chạy luôn)
```bash
kubectl diff -k k8s/addons/gitops/argocd/overlays/do-private   | tee artifacts/step11-gitops/argocd-diff.txt || true
```

### 11.5 Apply (khuyến nghị server-side)
```bash
kubectl apply --server-side -k k8s/addons/gitops/argocd/overlays/do-private   | tee artifacts/step11-gitops/argocd-apply.txt
```

### 11.6 Verify pods / ingress / cert
```bash
kubectl -n argocd get pods -o wide | tee artifacts/step11-gitops/argocd-pods.txt
kubectl -n argocd get svc | tee artifacts/step11-gitops/argocd-svc.txt
kubectl -n argocd get ingress -o wide | tee artifacts/step11-gitops/argocd-ingress.txt
kubectl -n argocd get certificate -o wide | tee artifacts/step11-gitops/argocd-cert.txt
```
**Kỳ vọng:**
- `argocd-server`, `argocd-repo-server`, `argocd-application-controller`… đều `Running`.
- Ingress `argocd` có HOST `argocd.internal`, ports 80/443.
- Certificate `argocd-internal-tls` READY `True`.

### 11.7 Lấy mật khẩu admin lần đầu
```bash
kubectl -n argocd get secret argocd-initial-admin-secret   -o jsonpath="{.data.password}" | base64 -d; echo
```
**Kỳ vọng:** in ra mật khẩu.

### 11.8 Test truy cập qua LB + CA nội bộ
Giả sử bạn đã có file CA (từ Step 8) tại `artifacts/step8-tls/internal-ca.crt`:
```bash
curl -sSIk https://argocd.internal --cacert artifacts/step8-tls/internal-ca.crt   | tee artifacts/step11-gitops/argocd-https-head.txt
```
**Kỳ vọng:** HTTP 200/302, có header `strict-transport-security`.

## Checklist exit-criteria
- [ ] Namespace `argocd` tạo thành công.
- [ ] Pods Argo CD Running/Ready.
- [ ] Ingress `argocd.internal` hoạt động (HTTP redirect → HTTPS).
- [ ] Certificate `argocd-internal-tls` READY True và trình duyệt/`curl --cacert` verify OK.
- [ ] Lấy được `argocd-initial-admin-secret` và đăng nhập được UI.

## Common issues & fix nhanh
1) **Ingress host trùng**: webhook nginx báo host/path đã tồn tại  
→ `kubectl -A get ingress | grep argocd.internal` rồi đổi host.

2) **CRD apply lỗi annotations too long**  
→ dùng `kubectl apply --server-side ...` (không tạo last-applied annotation).

3) **UI redirect loop / backend TLS**  
→ đã set `server.insecure: "true"` để server chạy HTTP phía sau ingress; đảm bảo ingress backend port `http`.

