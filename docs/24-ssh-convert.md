RUNBOOK: Chuyển đổi xác thực Argo CD sang SSH (Deploy Key)
Ngày thực hiện: 28/12/2025 Mục tiêu: Chuyển đổi cơ chế kết nối giữa Argo CD và GitHub Repository từ HTTPS (Token cá nhân/Public) sang SSH (Deploy Key). Lý do:
Khắc phục lỗi Repository not found hoặc Authentication required khi Token HTTPS hết hạn.
Đảm bảo bảo mật (Key là Read-only và gắn chặt với Repository cụ thể).
Chuẩn hóa mô hình GitOps cho môi trường Production.

1. Chuẩn bị SSH Key (Artifacts)
Tạo cặp khóa SSH chuẩn Ed25519 dành riêng cho Argo CD truy cập Repo infra-osdu-do.

# Tại thư mục gốc của repo trên ToolServer01
mkdir -p artifacts/step13-osdu

# Tạo key (không đặt passphrase để Argo CD có thể tự động đọc)
ssh-keygen -t ed25519 -C "argocd@infra-osdu-do" \
  -f artifacts/step13-osdu/argocd_repo_key -N ""

# Xuất nội dung Public Key để cấu hình lên GitHub
cat artifacts/step13-osdu/argocd_repo_key.pub
2. Cấu hình GitHub (Deploy Key)
Truy cập GitHub Repository: infra-osdu-do -> Settings -> Deploy keys.

Nhấn Add deploy key.

Title: ArgoCD Repo Server.

Key: Dán nội dung file .pub vừa tạo ở bước 1.

Allow write access: Bỏ chọn (Giữ Read-only để bảo mật).

Nhấn Add key.

3. Cấu hình Secret cho Argo CD (Cluster Side)
Tạo Kubernetes Secret chứa Private Key để Argo CD sử dụng khi kết nối.

Lưu ý quan trọng: Tham số url trong Secret này phải là định dạng SSH (git@github.com:...) và phải KHỚP CHÍNH XÁC với repoURL sẽ khai báo trong các file Application sau này.

Bash

# Tạo Secret định nghĩa Repository
kubectl -n argocd create secret generic repo-infra-osdu-do \
  --from-literal=type=git \
  --from-literal=url=git@github.com:thucnguyen79/infra-osdu-do.git \
  --from-file=sshPrivateKey=artifacts/step13-osdu/argocd_repo_key \
  -o yaml --dry-run=client | kubectl apply -f -

# Gán nhãn để Argo CD nhận diện đây là Credential
kubectl -n argocd label secret repo-infra-osdu-do \
  argocd.argoproj.io/secret-type=repository --overwrite
4. Cập nhật Manifests (Repo-first)
Đây là bước quan trọng nhất để đồng bộ GitOps. Cần thay đổi toàn bộ repoURL trong các file YAML từ HTTPS sang SSH.

4.1. Thực hiện thay đổi code
Sử dụng lệnh thay thế hàng loạt cho các App hiện có (Observability Stack):


cd /opt/infra-osdu-do

# Cập nhật App cha (App-of-Apps)
sed -i 's|https://github.com/thucnguyen79/infra-osdu-do.git|git@github.com:thucnguyen79/infra-osdu-do.git|g' k8s/gitops/app-of-apps/observability.yaml

# Cập nhật các App con (Child Apps)
sed -i 's|https://github.com/thucnguyen79/infra-osdu-do.git|git@github.com:thucnguyen79/infra-osdu-do.git|g' k8s/gitops/apps/observability/*.yaml
4.2. Push thay đổi lên Git
Argo CD đọc cấu hình từ Remote Git, nên bắt buộc phải Push.

Bash

git add k8s/gitops/
git commit -m "Step 13: Migrate repoURL from HTTPS to SSH for Deploy Key auth"
git push origin main
5. Đồng bộ hóa (Sync & Refresh)
Sau khi push, cần ép Argo CD cập nhật cấu hình mới ngay lập tức.

Bash

# 1. Cập nhật thủ công App cha trên Cluster để nó trỏ ngay sang SSH
kubectl apply -f k8s/gitops/app-of-apps/observability.yaml

# 2. Hard Refresh để xóa cache và ép Argo CD dùng kết nối mới
kubectl -n argocd annotate application app-of-apps-observability \
  argocd.argoproj.io/refresh=hard --overwrite
6. Kiểm tra kết quả (Verification)
6.1. Kiểm tra URL thực tế của Application
Chạy lệnh sau để đảm bảo không còn App nào dùng HTTPS:

Bash

kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,REPO_URL:.spec.source.repoURL
Kết quả kỳ vọng: Cột REPO_URL toàn bộ phải là git@github.com:thucnguyen79/infra-osdu-do.git.

6.2. Kiểm tra kết nối trong Argo CD Settings
Truy cập Web UI -> Settings -> Repositories.

Dòng kết nối git@github.com... phải có trạng thái Successful.

(Khuyến nghị) Xóa dòng kết nối https://... cũ để tránh nhầm lẫn.

Vào Application để sync lại app

Kết luận: Hệ thống Argo CD hiện tại đã chuyển hoàn toàn sang sử dụng SSH Deploy Key. Tất cả các Application tạo mới cho OSDU (Step 14 trở đi) BẮT BUỘC sử dụng repoURL dạng SSH: git@github.com:thucnguyen79/infra-osdu-do.git