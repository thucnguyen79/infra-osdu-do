# Step 9 — Storage (DigitalOcean CSI + Snapshots)

## Mục tiêu của Step 9
Trong OSDU, rất nhiều thành phần là **stateful** (có dữ liệu lâu dài) như database, object storage, search/queue… Step 9 thiết lập **Persistent Storage** cho cluster self-managed trên DigitalOcean bằng **DigitalOcean Block Storage CSI driver**, kèm **Snapshot** (VolumeSnapshot) để phục vụ backup/restore và vận hành.

Kết quả mong muốn sau Step 9:
- Worker nodes có **iSCSI client** chạy ổn để attach/detach volume.
- CSI driver **dobs.csi.digitalocean.com** hoạt động (controller + node plugin).
- Có StorageClass chuẩn hoá (Delete/Retain; ext4/xfs) và set default đúng.
- Test PVC/Pod **Provisioning + Attach/Detach + Delete** chạy OK, có evidence.

## Công cụ được dùng trong Step 9 (và công dụng)
- **Ansible** (modules: `apt`, `shell`): cài đặt gói hệ thống & start/verify services đồng loạt trên worker nodes (repo-first, repeatable).
- **systemctl / journalctl**: quản lý và truy vết service iSCSI trên node (open-iscsi/iscsid).
- **kubectl**: diff/apply/rollout/verify tài nguyên Kubernetes.
- **Kustomize (kubectl -k)**: build manifest theo “base/overlay”, giữ cấu hình theo môi trường DO private (repo-first).
- **grep/sed/cat**: rà soát nhanh manifest (tránh duplicate resource IDs, sai target patch…).
- **Artifacts**: lưu bằng `tee` vào `artifacts/step9-storage/` để truy vết và đối chiếu.

## Repo-first: vị trí file & evidence
- Manifests:
  - `k8s/addons/storage/do-csi/base/`
  - `k8s/addons/storage/do-csi/overlays/do-private/`
- Evidence (commit được): `artifacts/step9-storage/`
- Secrets/tokens (KHÔNG commit): `artifacts-private/step9-storage/` (đảm bảo gitignored)

---

## Runbook chi tiết

### 9.1 Tạo thư mục evidence
```bash
mkdir -p artifacts/step9-storage artifacts-private/step9-storage
```
**Kỳ vọng:** có đường dẫn để lưu log/outputs.

### 9.2 Cài iSCSI trên worker nodes (bắt buộc)
> DO Block Storage attach qua iSCSI, nên worker phải có open-iscsi/iscsid.

**Cài package:**
```bash
source .venv/bin/activate
export ANSIBLE_CONFIG=/opt/infra-osdu-do/ansible/ansible.cfg

ansible worker -b -m apt -a "update_cache=yes name=open-iscsi state=present" \
  | tee artifacts/step9-storage/ansible-open-iscsi.txt
```

**Start + verify services (khuyến nghị):**
```bash
ansible worker -b -m shell -a "systemctl enable --now iscsid && systemctl is-active iscsid" \
  | tee artifacts/step9-storage/iscsid-active.txt

ansible worker -b -m shell -a "systemctl start open-iscsi || true; systemctl is-active open-iscsi || true" \
  | tee artifacts/step9-storage/open-iscsi-active.txt
```

**Kỳ vọng:**
- `iscsid` = active
- `open-iscsi` có thể `active` hoặc `exited` tuỳ distro, nhưng không lỗi khi attach volume.
- Nếu gặp lỗi kiểu `Synchronizing state ... systemd-sysv-install ... rc=3`: xem mục **Issues** bên dưới.

### 9.3 Chuẩn bị DigitalOcean API token (secret) cho CSI controller
> CSI controller cần gọi DO API để tạo/xoá/attach/detach volume.

**(A) Xác định secretName/key trong manifest (repo-first):**
```bash
grep -R --line-number -- "secretName:" k8s/addons/storage/do-csi/base/vendor/csi-digitalocean-v4.15.0/driver.yaml | head
grep -R --line-number -- "access-token" k8s/addons/storage/do-csi/base/vendor/csi-digitalocean-v4.15.0/driver.yaml | head
```

**(B) Tạo secret (ví dụ secretName=digitalocean, key=access-token):**
```bash
# Lưu token ở môi trường tạm thời (KHÔNG commit)
read -s DO_TOKEN; echo
kubectl -n kube-system delete secret digitalocean --ignore-not-found
kubectl -n kube-system create secret generic digitalocean --from-literal=access-token="$DO_TOKEN"

kubectl -n kube-system get secret digitalocean -o yaml \
  | sed -n '1,40p' | tee artifacts/step9-storage/do-token-secret-head.txt
```

**Kỳ vọng:** secret tồn tại trong `kube-system` (không log lộ token).

### 9.4 (Nếu cần) Apply CRDs trước để tránh lỗi diff “no matches for kind VolumeSnapshotClass…”
Bạn đã từng gặp:
- `no matches for kind "VolumeSnapshotClass" ... ensure CRDs are installed first`

**Giải pháp repo-first:** apply snapshot CRDs trước, rồi mới diff/apply overlay.
```bash
kubectl apply -f k8s/addons/storage/do-csi/base/vendor/csi-digitalocean-v4.15.0/crds.yaml \
  | tee artifacts/step9-storage/do-snapshot-crds-apply.txt
```

### 9.5 Diff (trước khi apply) theo overlay do-private
```bash
kubectl diff -k k8s/addons/storage/do-csi/overlays/do-private \
  | tee artifacts/step9-storage/do-csi-diff.txt || true
```

### 9.6 Apply DO CSI driver + snapshot-controller + storageclasses
```bash
kubectl apply -k k8s/addons/storage/do-csi/overlays/do-private \
  | tee artifacts/step9-storage/do-csi-apply.txt
```

### 9.7 Rollout/health checks
```bash
kubectl -n kube-system rollout status ds/csi-do-node --timeout=300s \
  | tee artifacts/step9-storage/rollout-csi-do-node.txt || true

kubectl -n kube-system rollout status sts/csi-do-controller --timeout=300s \
  | tee artifacts/step9-storage/rollout-csi-do-controller.txt || true

kubectl -n kube-system get pods -l role=csi-do -o wide \
  | tee artifacts/step9-storage/csi-do-pods.txt

kubectl get sc | tee artifacts/step9-storage/storageclass-get.txt
kubectl get volumesnapshotclass | tee artifacts/step9-storage/volumesnapshotclass-get.txt
kubectl get csidriver dobs.csi.digitalocean.com -o wide \
  | tee artifacts/step9-storage/csidriver-get.txt
```

**Tiêu chí đạt (đúng với output bạn đã gửi):**
- `csi-do-node-*` trên mỗi worker: `2/2 Running`
- `csi-do-controller-0`: `5/5 Running` (restart >0 vẫn chấp nhận nếu hiện tại Running/Stable)
- StorageClasses có đủ và default đúng
- VolumeSnapshotClass `do-block-storage` tồn tại

### 9.8 Test provisioning (PVC + Pod) và thu evidence
> Mục tiêu: chứng minh end-to-end “Create -> Attach -> Mount -> Detach -> Delete”.

```bash
cat <<'YAML' | kubectl apply -f - | tee artifacts/step9-storage/pvc-test-apply.txt
apiVersion: v1
kind: Namespace
metadata:
  name: storage-test
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-test-5gi
  namespace: storage-test
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 5Gi
  storageClassName: do-block-storage
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-test
  namespace: storage-test
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh","-c","echo OK > /data/ok.txt; sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: pvc-test-5gi
YAML

kubectl -n storage-test get pvc,pod -o wide | tee artifacts/step9-storage/pvc-test-get.txt
kubectl -n kube-system logs csi-do-controller-0 -c csi-do-plugin --tail=50 \
  | tee artifacts/step9-storage/csi-controller-log-tail.txt
```

**Kỳ vọng:**
- PVC `Bound`, Pod `Running`
- Log controller có `create volume / publish volume` tương tự evidence bạn đưa.

**Cleanup test:**
```bash
kubectl delete ns storage-test --wait=true \
  | tee artifacts/step9-storage/pvc-test-cleanup.txt || true
kubectl get pvc -A | head | tee artifacts/step9-storage/pvc-list-after-cleanup.txt
```

---

## Issues đã gặp và cách xử lý (ghi vào doc)

### Issue A — open-iscsi enable/start fail (rc=3, sysv-install)
**Triệu chứng:**
- `systemctl enable --now open-iscsi` fail với `systemd-sysv-install ... rc=3`

**Fix (khuyến nghị):**
```bash
ansible worker -b -m shell -a "systemctl enable --now iscsid && systemctl is-active iscsid"
ansible worker -b -m shell -a "systemctl start open-iscsi || true; systemctl status open-iscsi --no-pager -l | head -n 60"
```

### Issue B — Kustomize diff fail do duplicate StorageClass IDs
**Triệu chứng:**
- `may not add resource with an already registered id: StorageClass ...`

**Nguyên nhân:**
- Vendor manifest đã có SC trùng tên với SC tự tạo.

**Fix:**
- Bỏ SC duplicate, chuyển sang patch để đổi default/reclaimPolicy/bindingMode.

### Issue C — Patch target not found (StorageClass)
**Triệu chứng:**
- `failed to find unique target for patch StorageClass ...`

**Nguyên nhân:**
- patch `metadata.name` không khớp tên StorageClass thật.

**Fix:**
- build/grep để lấy name đúng rồi sửa patch.

### Issue D — thiếu VolumeSnapshotClass (CRDs chưa apply)
**Triệu chứng:**
- `no matches for kind "VolumeSnapshotClass" ... ensure CRDs are installed first`

**Fix:**
- apply CRDs trước (9.4), rồi diff/apply.

### Issue E — csi-do-controller CrashLoopBackOff
**Nguyên nhân hay gặp:**
- Thiếu/sai secret DO token hoặc chặn egress.

**Fix:**
```bash
kubectl -n kube-system describe pod csi-do-controller-0 | tail -n 60
kubectl -n kube-system logs csi-do-controller-0 -c csi-do-plugin --tail=80
kubectl -n kube-system get secret digitalocean -o yaml | head
```

---

## Checklist Step 9 (tick để chốt)
- [x] Worker: `iscsid` active; open-iscsi start OK
- [x] DO token secret tồn tại (không lộ token trong repo)
- [x] `kubectl apply -k .../do-private` thành công
- [x] `ds/csi-do-node` rollout OK trên tất cả worker
- [x] `sts/csi-do-controller` Running (5/5)
- [x] StorageClasses có đủ; default đúng
- [x] Snapshot CRDs + VolumeSnapshotClass có đủ
- [x] Test PVC/Pod provisioning OK + cleanup OK
- [x] Evidence lưu trong `artifacts/step9-storage/`

