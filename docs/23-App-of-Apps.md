# Tài liệu Triển khai Step 12: GitOps & Observability Bootstrap

## 1. Tổng quan mục tiêu
* [cite_start]**Chuyển đổi sang GitOps**: Đưa các Add-ons đã triển khai thủ công (KPS, Ingress, Loki) vào sự quản lý của Argo CD[cite: 108].
* [cite_start]**Mô hình App-of-Apps**: Sử dụng một Application "cha" để quản lý tập trung các Application "con" của từng dịch vụ[cite: 112, 113].
* [cite_start]**Repo-first**: Thiết lập Git làm "Source of Truth" duy nhất cho trạng thái mong muốn của Cluster[cite: 109, 114].

---

## 2. Nhật ký Xử lý Sự cố & Issue Log (Dành cho Troubleshooting)

Trong quá trình thực hiện, các vấn đề sau đã được ghi nhận và giải quyết:

| Vấn đề (Issue) | Mô tả chi tiết | Giải pháp (Solution) |
| :--- | :--- | :--- |
| **Lỗi xác thực Repo** | Argo CD báo `ComparisonError` kèm thông báo `authentication required` trên giao diện Web. | Đăng ký thông tin xác thực (Token/PAT) trong mục **Settings > Repositories** của Argo CD UI. |
| **Lỗi thiếu thư mục** | [cite_start]Lệnh `diff` báo lỗi `lstat ... no such file` cho thành phần Promtail[cite: 101]. | [cite_start]Tạm thời không tạo Application con cho Promtail cho đến khi thư mục `logging-promtail` được khởi tạo trong repo[cite: 119]. |
| **Lỗi CRD quá lớn** | [cite_start]Các CRD của Prometheus Operator vượt quá giới hạn dung lượng metadata (262KB)[cite: 117]. | [cite_start]Sử dụng tùy chọn `ServerSideApply=true` trong chính sách đồng bộ của Argo CD[cite: 117, 121]. |

---

## 3. Quy trình Triển khai Chi tiết

### Bước 3.1: Chuẩn bị Biến môi trường
[cite_start]Thiết lập các biến để đảm bảo tính đồng bộ khi tạo file YAML[cite: 115]:
```bash
export REPO_URL="[https://github.com/](https://github.com/)<org>/<repo>.git"
export REVISION="main"

Bước 3.2: Khởi tạo Application "Con" (Child Apps)
Tạo các định nghĩa Application cho từng thành phần tại đường dẫn k8s/gitops/apps/observability/:
+1


10-kps.yaml: Quản lý Kube-Prometheus-Stack.


20-ingress.yaml: Quản lý Ingress cho các công cụ Monitoring.


30-loki.yaml: Quản lý Logging Backend.

Bước 3.3: Khởi tạo Application "Cha" (Root App)
Tạo file k8s/gitops/app-of-apps/observability.yaml để đóng vai trò bootstrap. File này sử dụng tính năng directory.recurse: true để quét toàn bộ thư mục Application con.
+1

Bước 3.4: Repo-first & Bootstrap
Thực hiện commit cấu hình lên Git trước khi áp dụng vào cluster:

Commit & Push:

Bash

git add k8s/gitops
git commit -m "step12: bootstrap app-of-apps for observability"
git push
Apply Bootstrap:

Bash

kubectl apply -f k8s/gitops/app-of-apps/observability.yaml
4. Checklist Kiểm tra & Artifacts (Checklist)
[x] Repository Status: Argo CD hiển thị trạng thái Successful cho Git Repo.

[x] Hierarchy Structure: Giao diện Argo CD hiển thị cấu trúc cây gồm 1 App cha quản lý 3 App con.

[x] Sync Strategy: Khuyến nghị thực hiện Manual Sync trước khi chuyển sang chế độ tự động.

[x] Artifacts:


artifacts/step12-gitops/app-of-apps-observability-apply.txt.


artifacts/step12-gitops/argocd-apps-list.txt.


Ghi chú vận hành: Đối với thành phần Promtail, chỉ tiến hành đưa vào quản lý sau khi đã xác nhận sự tồn tại của DaemonSet trong cluster và tạo đúng đường dẫn thư mục trong repo

5. CÁC ARTIFACTS CẦN LƯU TRỮ
Sau khi hoàn tất, cần kiểm tra sự tồn tại của các file/trạng thái sau:

File cấu hình: Danh sách các tệp tin trong artifacts/step12-gitops/.

Trạng thái đồng bộ: Ảnh chụp màn hình Argo CD với 1 App cha và 3 App con đều màu xanh (Synced & Healthy).

Log kiểm tra: File argocd-apps-list.txt ghi nhận danh sách ứng dụng đã sẵn sàng.

Lưu ý quan trọng cho vận hành: Từ thời điểm này, mọi thay đổi về cấu hình Monitoring/Logging cho OSDU phải được thực hiện qua việc sửa file YAML trên Git. Việc dùng kubectl edit trực tiếp trên cluster sẽ bị Argo CD tự động ghi đè lại (Self-heal) để đảm bảo tính an toàn.
 
## 6. ISSUE
Tôi đã thực hiện xong theo Lần 2_Hướng dẫn Step 12_02.txt, nhưng sao tôi chỉ thấy app-of-apps-observability trong danh sách

ops@ToolServer01:/opt/infra-osdu-do$ ls k8s/gitops/apps/observability/
10-kps.yaml  20-ingress.yaml  30-loki.yaml

ops@ToolServer01:/opt/infra-osdu-do$ kubectl apply -f k8s/gitops/app-of-apps/observability.yaml \
>   | tee artifacts/step12-gitops/app-of-apps-observability-apply.txt
application.argoproj.io/app-of-apps-observability created

ops@ToolServer01:/opt/infra-osdu-do$ cat artifacts/step12-gitops/app-of-apps-observability-apply.txt
application.argoproj.io/app-of-apps-observability created

ops@ToolServer01:/opt/infra-osdu-do$ kubectl -n argocd get applications.argoproj.io \
>   | tee artifacts/step12-gitops/argocd-apps-list.txt
NAME                        SYNC STATUS   HEALTH STATUS
app-of-apps-observability   Unknown       Healthy

ops@ToolServer01:/opt/infra-osdu-do$ kubectl apply -f k8s/gitops/app-of-apps/observability.yaml \
>   | tee artifacts/step12-gitops/app-of-apps-observability-apply.txt
application.argoproj.io/app-of-apps-observability unchanged

### 1. Phân tích nguyên nhân:
Ảnh đính kèm "Failed to load target state... authentication required: Repository not found."
Điều này có nghĩa là:
Đã tạo thành công Application "cha" (app-of-apps-observability) trên Kubernetes.
Tuy nhiên, khi Argo CD cầm cái URL bạn cung cấp để đi tìm các file "con" (10-kps.yaml, 20-ingress.yaml, ...), nó bị hệ thống Git chặn lại do sai địa chỉ URL hoặc thiếu quyền truy cập (Authentication).
Vì không đọc được các file con từ Git, Argo CD không thể tạo ra các Application con tương ứng, dẫn đến việc bạn chỉ thấy duy nhất một App cha với trạng thái Unknown.
### 2. Nguyên nhân cụ thể trong tình huống của bạn
Lỗi xác thực: Nếu Repo của bạn là Private, bạn phải đăng ký thông tin đăng nhập (Username/Password hoặc Token) của Git vào trong Argo CD Settings trước khi thực hiện bước này
### 3. Cách khắc phục 
Cách 1: Sử dụng giao diện Web (Argo CD UI) - Dễ nhất
Đăng nhập vào giao diện Argo CD (theo link https://argocd.internal trong ảnh của bạn).
Truy cập vào mục Settings (biểu tượng bánh răng ở menu bên trái).
Chọn Repositories.
Nhấn nút Connect Repo.
Điền các thông tin sau:
Choose connection method: Chọn HTTPS.
Type: git.
Project: default.
Repository URL: Nhập đúng URL bạn đã dùng trong file YAML (ví dụ: https://github.com/user/repo.git).
Username: Tên đăng nhập Git của bạn.
Password: Sử dụng Personal Access Token (PAT) thay vì mật khẩu thông thường (đối với GitHub/GitLab).
Nhấn Connect. Nếu hiện trạng thái Successful, Argo CD đã có quyền truy cập.

Cách 2: Sử dụng dòng lệnh (CLI)
Nếu bạn muốn thực hiện trực tiếp trên ToolServer01, hãy dùng lệnh sau để khai báo (Yêu cầu đã cài đặt argocd CLI):

argocd repo add <URL_REPO_CUA_BAN> --username <USERNAME> --password <TOKEN_CUA_BAN>
### Sau khi đăng ký xong, bạn cần làm gì?
Khi Argo CD đã có quyền truy cập, bạn quay lại Application app-of-apps-observability và thực hiện:
  - Refresh/Hard Refresh: Để Argo CD thử quét lại thư mục k8s/gitops/apps/observability trên Git.
  - Kiểm tra kết quả: Các Application con như obs-kube-prometheus-stack, obs-ingress, và obs-loki sẽ tự động xuất hiện trong danh sách
  - Đồng bộ hóa (Sync):
     - Trạng thái ban đầu sẽ là OutOfSync.
     - Bạn nên thực hiện Manual Sync (nhấn nút Sync trên từng App con).
     - Hãy đảm bảo bật tùy chọn Server-Side Apply khi Sync để tránh lỗi giới hạn dung lượng metadata (262KB) đối với các CRD lớn của Prometheus