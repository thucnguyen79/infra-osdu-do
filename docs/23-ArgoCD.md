Step 11 — GitOps (Argo CD)
Mục tiêu của Step 11
Thiết lập Argo CD làm "bộ não" điều phối cho cụm OSDU. Step 11 hiện thực hóa mô hình GitOps, trong đó Git là "Nguồn sự thật" (Source of Truth). Mọi thay đổi về hạ tầng và ứng dụng sẽ được khai báo trong code, Argo CD chịu trách nhiệm tự động đồng bộ (Sync) và duy trì trạng thái mong muốn trong Cluster.

Kết quả mong muốn sau Step 11:

GitOps Engine: Argo CD hoạt động ổn định, quản lý được chính nó và các add-ons khác.

Security: Truy cập Web UI qua HTTPS (argocd.internal) tích hợp với cert-manager và Internal CA.

Scalability: Sẵn sàng cho chiến lược đa môi trường (dev/stage/prod) thông qua Kustomize Overlays.

Automation: Hạn chế tối đa việc sử dụng kubectl apply thủ công, chuyển sang quy trình Commit -> Sync.

Công cụ được dùng trong Step 11 (và công dụng)
kubectl: Thực hiện apply --server-side để nạp các CRD của Argo CD (vốn rất lớn, dễ gây lỗi phình annotation).

Kustomize: Quản lý sự khác biệt giữa cấu hình chuẩn (base) và cấu hình riêng cho DigitalOcean (overlay).

curl: Verify chứng chỉ TLS nội bộ và kiểm tra độ sẵn sàng của Argo CD Server.

base64: Giải mã mật khẩu quản trị khởi tạo từ Kubernetes Secret.

Repo-first: vị trí file & evidence
Manifests:

k8s/addons/gitops/argocd/base/vendor/install.yaml (File gốc từ dự án Argo proj).

k8s/addons/gitops/argocd/overlays/do-private/patches/ (Chứa bản vá chỉnh sửa URL và chế độ insecure).

Evidence: artifacts/step11-gitops/.

Runbook chi tiết
11.1 Khởi tạo không gian lưu trữ bằng chứng
Bash

cd /opt/infra-osdu-do
mkdir -p artifacts/step11-gitops
11.2 Chuẩn bị Namespace và Manifest
Bash

# Tạo namespace
kubectl get ns argocd || kubectl create ns argocd
kubectl get ns argocd | tee artifacts/step11-gitops/ns-argocd.txt

# Đếm dòng để verify file vendor (Kỳ vọng > 10.000 dòng)
wc -l k8s/addons/gitops/argocd/base/vendor/install.yaml \
  | tee artifacts/step11-gitops/argocd-install-wc.txt
11.3 Triển khai Argo CD (Server-side apply)
Lưu ý: Để tránh lỗi "metadata.annotations: Too long" đã gặp ở Step 10, bắt buộc sử dụng tham số --server-side.

Bash

kubectl apply --server-side -k k8s/addons/observability/logging-loki/overlays/do-private \
  | tee artifacts/step11-gitops/argocd-apply.txt
11.4 Kiểm tra trạng thái hệ thống
Bash

# Đợi pods chuyển sang trạng thái Running
kubectl -n argocd get pods -o wide | tee artifacts/step11-gitops/argocd-pods.txt

# Kiểm tra Ingress và Certificate
kubectl -n argocd get ingress,certificate -o wide | tee artifacts/step11-gitops/argocd-verify.txt
Kỳ vọng: argocd-internal-tls có trạng thái READY=True.

11.5 Lấy mật khẩu quản trị và Smoke Test
Bash

# Lấy Initial Admin Password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo \
  | tee artifacts/step11-gitops/argocd-initial-admin-password.txt

# Kiểm tra HTTPS (Yêu cầu đã sửa /etc/hosts cho argocd.internal)
curl -sSIk https://argocd.internal --cacert artifacts/step8-tls/internal-root-ca.crt \
  | tee artifacts/step11-gitops/argocd-https-head.txt
Issues đã gặp và cách xử lý
Issue A — Kustomize Load-restrictor Error
Triệu chứng: security; file '...' is not in or below '...'. Nguyên nhân: Kustomize không cho phép overlay truy cập patches nằm ngoài thư mục của nó. Fix: Di chuyển thư mục patches/ vào bên trong overlays/do-private/ để đảm bảo tính đóng gói.

Issue B — Patch target not found (Namespace conflict)
Triệu chứng: failed to find unique target for patch ConfigMap.v1.[noGrp]/argocd-cm. Nguyên nhân: Khai báo namespace trùng lặp ở cả tầng base và overlay gây sai lệch ID tài nguyên. Fix: Xóa dòng namespace cứng trong các file patch, để kustomization.yaml của overlay tự quản lý namespace.

Issue C — Could not resolve host: argocd.internal
Triệu chứng: Lệnh curl thất bại dù Ingress đã Ready. Nguyên nhân: DNS nội bộ chưa cập nhật bản ghi cho domain mới. Fix: Bổ sung argocd.internal vào file /etc/hosts trên ToolServer.
