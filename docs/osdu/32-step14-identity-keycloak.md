# Step 14 — Identity (Keycloak + Postgres) cho OSDU (do-private)

> **Mục tiêu:** dựng *Identity Provider* nội bộ để OSDU dùng OIDC/OAuth2 (token issuance), theo chuẩn **repo-first**: mọi manifest nằm trong repo, mọi thao tác có **artifacts** làm bằng chứng.

## 1) Phạm vi Step 14

Triển khai trong Kubernetes:

- Namespace: `osdu-identity`
- Keycloak (Deployment) + Postgres (DB cho Keycloak)
- Ingress nội bộ `keycloak.internal` (nginx ingress)
- TLS nội bộ từ **cert-manager Internal CA**
- Bootstrap realm `osdu`, client `osdu-cli`, user test để **lấy access token** (password grant cho POC)
- Export realm ra file để backup/restore (repo-first + artifacts)

## 2) Điều kiện tiên quyết (đã có từ các step trước)

- Ingress Controller (nginx) đang hoạt động (đã dùng cho `*.internal`).
- cert-manager + `ClusterIssuer internal-ca` đã Ready.
- Máy thao tác (ToolServer01) có `kubectl` truy cập cluster.
- DNS/hosts cho `keycloak.internal` **phải resolve** về LB/Ingress VIP (hoặc mapping ở `/etc/hosts`).
  - Dấu hiệu DNS chưa ổn: `curl: (6) Could not resolve host: keycloak.internal`

## 3) Cấu trúc repo liên quan

- `k8s/osdu/identity/base/`  
  - `keycloak-deploy.yaml`
  - `keycloak-svc.yaml` (nếu có)
  - `keycloak-db-*.yaml` (StatefulSet/Service/Secret cho Postgres)
  - `keycloak-ingress.yaml` (hoặc nằm ở overlay)
- `k8s/osdu/identity/overlays/do-private/`
  - `kustomization.yaml`
  - `patches/patch-keycloak-ingress-class.yaml` *(bạn đặt patch trong thư mục `patches/` và đã commit)*

## 4) Runbook triển khai Step 14 (các lệnh + kết quả kỳ vọng)

> Gợi ý: luôn ghi output vào `artifacts/step14-identity/` để “đúng bài”.

### 4.1. Tạo namespace (nếu chưa có)

```bash
kubectl get ns osdu-identity || kubectl create ns osdu-identity
```

**Kỳ vọng:** namespace `osdu-identity` ở trạng thái `Active`.

---

### 4.2. Diff trước khi apply (repo-first)

```bash
mkdir -p artifacts/step14-identity
kubectl diff -k k8s/osdu/identity/overlays/do-private   | tee artifacts/step14-identity/keycloak-diff.txt || true
```

**Kỳ vọng:** diff hiển thị thay đổi sẽ apply; không có lỗi CRD/Kind.

---

### 4.3. Apply overlay do-private

```bash
kubectl apply -k k8s/osdu/identity/overlays/do-private   | tee artifacts/step14-identity/keycloak-apply.txt
```

**Kỳ vọng:** tạo/điều chỉnh các resource Keycloak + DB + Ingress/Certificate.

---

### 4.4. Chờ rollout DB + Keycloak

```bash
kubectl -n osdu-identity rollout status sts/keycloak-db --timeout=600s   | tee artifacts/step14-identity/db-rollout.txt || true

kubectl -n osdu-identity rollout status deploy/keycloak --timeout=600s   | tee artifacts/step14-identity/keycloak-rollout.txt || true
```

**Kỳ vọng:** DB Ready; Keycloak Ready.  
Nếu Keycloak `CrashLoopBackOff` → xem mục “Issues” bên dưới.

---

### 4.5. Verify Pods/Ingress/Certificate

```bash
kubectl -n osdu-identity get pods -o wide   | tee artifacts/step14-identity/pods.txt

kubectl -n osdu-identity get ingress -o wide   | tee artifacts/step14-identity/ingress-get.txt

kubectl -n osdu-identity get certificate -o wide   | tee artifacts/step14-identity/cert-get.txt
```

**Kỳ vọng:**
- Pod Keycloak `Running` (1/1) và DB `Running`
- Ingress có host `keycloak.internal`
- Certificate READY=True, secret TLS tồn tại

---

### 4.6. Verify HTTP/HTTPS qua LB/Ingress

HTTP thường sẽ redirect sang HTTPS:

```bash
curl -sI http://keycloak.internal | tee artifacts/step14-identity/http-via-lb.txt
```

HTTPS (verify bằng Internal CA):

```bash
curl -sk --cacert artifacts/step7-cert-manager/internal-ca.crt   -sI https://keycloak.internal   | tee artifacts/step14-identity/https-via-lb-ca.txt
```

**Kỳ vọng:**
- HTTP: `308` hoặc `301` redirect
- HTTPS: trả về header hợp lệ (200/302 tuỳ endpoint), **không** lỗi TLS chain

## 5) Bootstrap realm/client/user (POC)

> Bạn đã làm đúng hướng: dùng `kcadm.sh` trong pod để thao tác Keycloak.

### 5.1. Vào pod + login admin

```bash
POD=$(kubectl -n osdu-identity get pods -l app=keycloak -o jsonpath='{.items[0].metadata.name}')
kubectl -n osdu-identity exec -it "$POD" -- bash -lc '
set -euo pipefail
KCADM=/opt/keycloak/bin/kcadm.sh
$KCADM config credentials --server http://localhost:8080 --realm master   --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD"
echo "OK: logged in"
'
```

### 5.2. Enable Direct Access Grants cho client `osdu-cli`

- Lỗi bạn gặp trước đó: `{"error":"unauthorized_client" ... "Client not allowed for direct access grants"}`
- Cách xử lý: bật `directAccessGrantsEnabled=true`

```bash
kubectl -n osdu-identity exec "$POD" -- bash -lc '
set -euo pipefail
KCADM=/opt/keycloak/bin/kcadm.sh
$KCADM config credentials --server http://localhost:8080 --realm master   --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

CID=$($KCADM get clients -r osdu -q clientId=osdu-cli   | sed -n "s/.*\"id\" *: *\"\([^\"]*\)\".*/\1/p" | head -n1)

echo "CID=$CID"
$KCADM update clients/$CID -r osdu -s directAccessGrantsEnabled=true
echo "OK: enabled directAccessGrantsEnabled"
'
```

### 5.3. Fix lỗi `invalid_grant: Account is not fully set up`

Bạn đã debug đúng: user `test` dù enabled + emailVerified + requiredActions=[] vẫn lỗi.  
Nguyên nhân thực tế: **profile user thiếu thông tin bắt buộc** (thường là `firstName/lastName/email`) → Keycloak coi tài khoản “chưa setup xong”.

Cách xử lý (bạn đã làm): cập nhật profile:

```bash
kubectl -n osdu-identity exec "$POD" -- bash -lc '
set -euo pipefail
KCADM=/opt/keycloak/bin/kcadm.sh
$KCADM config credentials --server http://localhost:8080 --realm master   --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

USER_ID=$($KCADM get users -r osdu -q username=test   | sed -n "s/.*\"id\" *: *\"\([^\"]*\)\".*/\1/p" | head -n1)

echo "Updating profile for USER_ID=$USER_ID"
$KCADM update users/$USER_ID -r osdu   -s firstName="Test"   -s lastName="User"   -s email="test@osdu.internal"

# Password grant cần password NON-temporary
$KCADM set-password -r osdu --userid "$USER_ID" --new-password "Test@12345" --temporary=false
echo "OK: user fixed"
'
```

> **Lưu ý quan trọng:** đừng dùng biến `UID=` trong bash vì `UID` là biến read-only của shell.  
> Bạn đã gặp: `bash: line 8: UID: readonly variable` → đổi sang `USER_ID`.

### 5.4. Lấy access token (password grant)

```bash
curl -sk --cacert artifacts/step7-cert-manager/internal-ca.crt   -d "grant_type=password"   -d "client_id=osdu-cli"   -d "username=test"   -d "password=Test@12345"   "https://keycloak.internal/realms/osdu/protocol/openid-connect/token" | head
```

**Kỳ vọng:** trả JSON có `access_token` (bạn đã lấy được).

## 6) Export realm `osdu` (backup/restore)

### 6.1. Chạy export trong container

Bạn chạy:

- `kc.sh export --realm osdu --dir /tmp/kc-export --users realm_file`

Log cho thấy **export thành công** và file đã tạo:

- `/tmp/kc-export/osdu-realm.json`

Nhưng bạn gặp 2 vấn đề phụ:

1) `Address already in use` khi Keycloak cố start management interface trong import/export mode  
→ **Không ảnh hưởng** đến file export nếu log đã nói “Export finished successfully”.

2) `tar: command not found`  
→ image Keycloak không có `tar`.

### 6.2. Tải file export ra host (kubectl cp không dùng được)

`kubectl cp` cần `tar` trong container, nên bạn gặp:

- `exec: "tar": executable file not found in $PATH`

Cách làm đúng (bạn đã làm): dùng `cat` để stream file ra host:

```bash
mkdir -p artifacts/step14-identity/kc-export
POD=$(kubectl -n osdu-identity get pods -l app=keycloak -o jsonpath='{.items[0].metadata.name}')

kubectl -n osdu-identity exec "$POD" -- cat /tmp/kc-export/osdu-realm.json   > artifacts/step14-identity/kc-export/osdu-realm.json
```

(Optional) nén ở phía host (ToolServer01):

```bash
tar -C artifacts/step14-identity/kc-export -czf artifacts/step14-identity/osdu-realm-export.tgz .
```

## 7) Repo-first evidence (bạn đã làm đúng)

Bạn đã:
- commit `artifacts/step14-identity/*`
- commit patch `k8s/osdu/identity/overlays/do-private/patches/patch-keycloak-ingress-class.yaml`
- push lên GitHub

## 8) Issues đã gặp & cách xử lý (tổng hợp)

### Issue A — Keycloak CrashLoopBackOff / probes
- Dấu hiệu: pod `CrashLoopBackOff` hoặc readiness/liveness fail
- Cách xử lý bạn làm:
  - chỉnh `keycloak-deploy.yaml` (proxy/hostname/http enabled)
  - tăng `initialDelaySeconds` cho probe
  - đảm bảo probe đúng endpoint `/health/ready` & `/health/live` đúng port (thường 8080 trong mode HTTP)

### Issue B — DNS: `Could not resolve host keycloak.internal`
- Nguyên nhân: máy client chưa resolve `*.internal`
- Fix: thêm record DNS nội bộ hoặc `/etc/hosts` trỏ về LB/Ingress VIP

### Issue C — Token lỗi `unauthorized_client`
- Nguyên nhân: client chưa bật direct access grants
- Fix: `directAccessGrantsEnabled=true` cho client `osdu-cli`

### Issue D — Token lỗi `invalid_grant: Account is not fully set up`
- Nguyên nhân: user thiếu profile bắt buộc (firstName/lastName/email) hoặc password temporary
- Fix: update user profile + set password `--temporary=false`

### Issue E — Bash variable `UID` read-only
- Fix: dùng `USER_ID` thay vì `UID`

### Issue F — Export realm & copy artifact
- `kc.sh export` có thể log “Address already in use” ở cuối → vẫn OK nếu export thành công
- `tar` không có trong image → `kubectl cp` thất bại
- Fix: `kubectl exec ... cat file > hostfile`, rồi nén ở host

## 9) Checklist Step 14 (đạt/không đạt)

- [ ] Namespace `osdu-identity` tồn tại
- [ ] DB Keycloak Ready (rollout OK)
- [ ] Keycloak pod Running/Ready
- [ ] Ingress `keycloak.internal` tồn tại, class `nginx`
- [ ] Certificate `keycloak-internal-tls` (hoặc tương đương) READY=True
- [ ] `curl --cacert internal-ca.crt https://keycloak.internal` không lỗi TLS
- [ ] Realm `osdu` tồn tại
- [ ] Client `osdu-cli` tồn tại và `directAccessGrantsEnabled=true`
- [ ] User `test` tồn tại, enabled, password NON-temporary, có profile (first/last/email)
- [ ] Password grant lấy được `access_token`
- [ ] Export realm tạo được `artifacts/step14-identity/kc-export/osdu-realm.json`
- [ ] Git commit + push evidence lên repo

---

**Trạng thái Step 14 (theo output bạn gửi):** đã đạt mục tiêu POC (token OK) + export realm + repo-first evidence.
