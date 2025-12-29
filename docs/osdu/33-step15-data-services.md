# Step 15 — Data Services: Object Storage (Ceph/Rook)

## 1. Mục tiêu
Triển khai hệ thống lưu trữ đối tượng (Object Storage) tương thích chuẩn S3 để phục vụ cho các dịch vụ OSDU (File Service, Dataset Service).
* **Công nghệ:** Ceph (Storage Engine) + Rook (Kubernetes Operator).
* **Thay thế:** MinIO (Do yêu cầu về tính năng production-grade và bản quyền).
* **Phạm vi:** Chỉ triển khai Ceph trong Step này. Elasticsearch và Database sẽ được triển khai ở Step 16.

## 2. Kiến trúc & Cấu hình (POC)

### 2.1. Thông tin chung
* **Namespace:** `rook-ceph`
* **Version:**
  * Rook Operator: `v1.14.9` (Stable).
  * Ceph Version: `v18.2.4` (Quincy).
* **Storage Class:** `do-block-storage-retain` (DigitalOcean Block Storage).

### 2.2. Topo triển khai (Minimal)
Để tối ưu chi phí và tài nguyên trên môi trường POC, cấu hình Cluster được tinh chỉnh như sau:
* **Monitors (MON):** 1 (Thay vì 3).
* **Managers (MGR):** 1.
* **OSD (Ổ cứng):** 1 Node, 1 PVC (Size 50Gi, Mode: Block).
* **Replica:** 1 (Tắt sao lưu dự phòng - `failureDomain: host`).
* **Ingress:** `s3.internal` (TLS enabled via `internal-ca`).

## 3. Cấu trúc Repository (GitOps)
Code được tổ chức theo mô hình **Repo-first** với Kustomize:

```text
k8s/addons/storage/rook-ceph/
├── base/
│   ├── kustomization.yaml
│   └── vendor/             # Manifests gốc từ Rook (CRDs, Operator)
└── overlays/
    └── do-private/         # Cấu hình riêng cho môi trường DO
        ├── kustomization.yaml
        ├── cephcluster.yaml    # Định nghĩa cụm Ceph (OSD trên PVC)
        ├── objectstore.yaml    # Định nghĩa S3 Gateway (RGW)
        ├── objectstore-user.yaml # User OSDU
        ├── rgw-cert.yaml       # Certificate (internal-ca)
        └── rgw-ingress.yaml    # Ingress (s3.internal)

## 4. ArgoCD Configuration
Do Ceph yêu cầu quyền quản trị Cluster (Cluster-scoped permissions), Application ArgoCD được cấu hình đặc biệt:
Project: default (Thay vì osdu để tránh lỗi giới hạn Namespace destination).
Sync Policy: Automated (Prune + SelfHeal).
Sync Options: ServerSideApply=true (Bắt buộc để xử lý các CRD lớn của Ceph).
File cấu hình: k8s/gitops/apps/osdu/05-ceph.yaml
## 5. Thông tin Kết nối & Credentials (QUAN TRỌNG)
Dùng các thông tin dưới đây để cấu hình cho OSDU Services ở Step 16.
S3 Endpoint (Internal): http://rook-ceph-rgw-osdu-store.rook-ceph.svc:80
S3 Endpoint (External): https://s3.internal (Cần cấu hình /etc/hosts).
Region: us-east-1 (Mặc định).
Bucket mặc định: osdu-bucket (Hoặc tạo mới tùy service).
Cách lấy AccessKey / SecretKey
Chạy lệnh sau trên ToolServer:
Bash
echo "AccessKey: $(kubectl -n rook-ceph get secret rook-ceph-object-user-osdu-store-osdu-s3-user -o jsonpath='{.data.AccessKey}' | base64 -d)"
echo "SecretKey: $(kubectl -n rook-ceph get secret rook-ceph-object-user-osdu-store-osdu-s3-user -o jsonpath='{.data.SecretKey}' | base64 -d)"

## 6. Verification (Kiểm tra hoạt động)
### 6.1. Pods Status
Tất cả các Pods trong namespace rook-ceph phải ở trạng thái Running:
rook-ceph-operator
rook-ceph-mon-a, mgr-a
rook-ceph-osd-0 (Quan trọng - Chứng tỏ đã nhận ổ cứng).
rook-ceph-rgw-osdu-store-a (S3 Gateway).
### 6.2. Connectivity Test
Kiểm tra kết nối HTTP tới S3 Gateway từ nội bộ Cluster:
Bash
kubectl -n rook-ceph exec deploy/rook-ceph-operator -- curl -I [http://rook-ceph-rgw-osdu-store.rook-ceph.svc:80](http://rook-ceph-rgw-osdu-store.rook-ceph.svc:80)

Kỳ vọng: Trả về HTTP/1.1 200 OK.
## 7. Troubleshooting / Các vấn đề đã xử lý
Lỗi ArgoCD Permissions:
Vấn đề: ArgoCD báo lỗi không thể deploy vào namespace rook-ceph nếu dùng project osdu.
Giải pháp: Chuyển Application osdu-ceph sang dùng project default.
Lỗi OSD không khởi động:
Nguyên nhân: StorageClass không hỗ trợ volumeMode: Block hoặc PVC chưa bound.
Giải pháp: Đảm bảo file cephcluster.yaml dùng đúng StorageClass do-block-storage-retain.
Tài liệu này được dùng làm cơ sở để triển khai Step 16 (OSDU Core Services).

