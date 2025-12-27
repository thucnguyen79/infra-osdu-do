#Step 10: Observability (Monitoring/Logging)
Repo: /opt/infra-osdu-do
Evidence: artifacts/step10-observability/
TLS: dùng cert-manager + ClusterIssuer internal-ca (từ Step 8)
Truy cập nội bộ: grafana.internal, prometheus.internal, alertmanager.internal (qua LB/Ingress của )

##10.0 Mục tiêu Step 10
Monitoring (10.4)
Triển khai kube-prometheus-stack (Prometheus Operator) để có:
- Prometheus: thu metrics cluster/node/k8s…
- Alertmanager: nhận & xử lý cảnh báo
- Grafana: dashboard + Explore

Logging (10.5)
Triển khai Loki + Promtail để:
- Promtail chạy trên node, gom log container → đẩy về Loki
- Grafana đọc log từ Loki (Explore)

##10.1 Công cụ dùng trong Step 10 (và công dụng)
kubectl
- kubectl diff -k / kubectl apply -k: triển khai theo Kustomize overlay (repo-first)
- kubectl apply -f: apply CRDs (CustomResourceDefinition)
- kubectl get/describe/logs: verify tình trạng tài nguyên/pod
- kubectl api-resources: kiểm tra CRD đã “đăng ký” vào API server chưa

curl
- Smoke test HTTP/HTTPS, redirect, verify TLS bằng Internal CA

grep/egrep/sed/head/wc, tee
- Lọc output và lưu evidence vào artifacts/…

helm template (Hướng B cho Loki/Promtail)
- Render YAML từ chart → lưu vào base/vendor/ trong repo, sau đó apply bằng kustomize

##10.2 Repo structure (liên quan Step 10)
kube-prometheus-stack
- k8s/addons/observability/kube-prometheus-stack/base/vendor/
  - crds.yaml
  - stack.yaml

ingress (grafana/prometheus/alertmanager)
- k8s/addons/observability/ingress/base/
  - *-certificate.yaml
  - *-ingress.yaml

logging loki/promtail
- k8s/addons/observability/logging-loki/overlays/do-private/
  - values-loki.yaml [x] ( đã fix)
  - values-promtail.yaml

##10.4 Monitoring — kube-prometheus-stack (Runbook)
###10.4.1 Tạo namespace
kubectl get ns observability || kubectl create ns observability
kubectl get ns observability | tee artifacts/step10-observability/ns-observability.txt

**Kỳ vọng:** observability Active

###10.4.2 Issue #1 — diff/apply báo thiếu CRD (Alertmanager)
**Triệu chứng**
- no matches for kind "Alertmanager" in version "monitoring.coreos.com/v1"
- “ensure CRDs are installed first”
**Nguyên nhân**
Prometheus Operator dùng CRDs thuộc group monitoring.coreos.com. Chưa có CRD → diff/apply fail.

**Cách xử lý (repo-first)**

Apply CRDs trước:

kubectl apply -f k8s/addons/observability/kube-prometheus-stack/base/vendor/crds.yaml \
  | tee artifacts/step10-observability/kps-crds-apply.txt

###10.4.3 Issue #2 — CRDs apply bị lỗi metadata.annotations: Too long
**Triệu chứng**
Một số CRD (alertmanagers/…/thanosrulers/…) báo:
metadata.annotations: Too long: must have at most 262144 bytes

**Nguyên nhân** hay gặp
Apply kiểu client-side dễ phát sinh/đụng “annotation quá lớn” với các CRD rất dài.

**Cách xử lý khuyến nghị và bền vững**
Lần sau (hoặc để làm sạch repo cho idempotent), ưu tiên apply CRDs bằng server-side:

kubectl apply --server-side -f k8s/addons/observability/kube-prometheus-stack/base/vendor/crds.yaml \
  | tee artifacts/step10-observability/kps-crds-apply-serverside.txt


**Điểm quan trọng: Sau khi  xử lý, output kps-api-resources-after.txt đã có đầy đủ:**
alertmanagers
prometheuses
thanosrulers
servicemonitors/podmonitors/prometheusrules …
=> nghĩa là CRDs đã OK.

###10.4.4 Verify CRDs
kubectl api-resources --api-group=monitoring.coreos.com \
  | tee artifacts/step10-observability/kps-api-resources-after.txt


**Kỳ vọng:** thấy Alertmanager, Prometheus, ThanosRuler… (đúng như  đã có)

###10.4.5 diff/apply kube-prometheus-stack
kubectl diff -k k8s/addons/observability/kube-prometheus-stack/overlays/do-private \
  | tee artifacts/step10-observability/kps-diff.txt || true

kubectl apply -k k8s/addons/observability/kube-prometheus-stack/overlays/do-private \
  | tee artifacts/step10-observability/kps-apply.txt


Kết quả có: kps-diff.txt trống ⇒ manifest trong cluster đã khớp repo (tín hiệu rất tốt).

###10.4.6 Verify pods (Monitoring)
kubectl -n observability get pods -o wide \
  | tee artifacts/step10-observability/obs-pods.txt

Đánh giá theo output  gửi: [x] Đạt
- Alertmanager Running
- Prometheus Running
- Grafana Running
- Operator Running
- Node-exporter chạy trên các node

kps-grafana-test Completed là job test/one-shot → bình thường.

##10.5 Ingress + TLS nội bộ (Runbook)
###10.5.1 Issue #3 — Ingress trùng host/path bị admission webhook chặn

**Triệu chứng**
host "alertmanager.internal" and path "/" is already defined ...

**Nguyên nhân**
Tồn tại 2 ingress cùng host/path (trùng route) → nginx validating webhook deny.

**Cách xử lý đúng (Hướng B)**
Không tạo ingress trùng.
Hoặc “giữ ingress do chart tạo sẵn” và chỉ patch TLS/cert/annotations lên ingress đó,
Hoặc “dùng ingress base riêng” thì phải đảm bảo chart không tạo ingress (tắt ingress trong values).

###10.5.2 Verify Ingress hiện trạng
kubectl -n observability get ingress -o wide


Đánh giá theo output  gửi: [x] Đạt — hiện có đúng 3 ingress:
- grafana.internal
- prometheus.internal
- alertmanager.internal

###10.5.3 Verify Certificates (Internal CA)
kubectl -n observability get certificate -o wide

Đánh giá theo output  gửi: [x] Đạt — cả 3 cert READY=True
- grafana-internal-tls
- prometheus-internal-tls
- alertmanager-internal-tls

10.5.4 Smoke test HTTP→HTTPS và HTTPS verify CA
Đã test và ra kết quả:
- HTTP trả 308 redirect sang HTTPS [x]
- HTTPS verify CA trả:
  - Grafana: 302 /login [x]
  - Prometheus/Alertmanager:  đang dùng request kiểu HEAD/không đúng endpoint nên thấy 405 (bình thường)

Chuẩn verify (nên lưu lại để Step 11):

# Dùng GET readiness endpoint
curl -sS --cacert artifacts/step8-tls/internal-root-ca.crt https://prometheus.internal/-/ready -o /dev/null -w "%{http_code}\n"
curl -sS --cacert artifacts/step8-tls/internal-root-ca.crt https://alertmanager.internal/-/ready -o /dev/null -w "%{http_code}\n"


**Kỳ vọng:** 200

##10.5 Logging — Loki + Promtail (Hướng B)
###10.5.1 Mục tiêu
Loki lưu log (bền vững bằng PVC + DO block storage retain)
Promtail gom log node/pod → đẩy vào Loki
Grafana đọc Loki để query log

###10.5.2 GHI NHẬN QUAN TRỌNG —  phải sửa values-loki.yaml (Loki 6.x)

Thực tế: phải sửa như đoạn dưới thì mới chạy đúng. Mình ghi nhận vào document Step 10 như “final config”.

[x] Final values-loki.yaml (bản cung cấp):

deploymentMode: SingleBinary

loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: 'filesystem'
    bucketNames:
      chunks: 'chunks'
      rules: 'rules'
      admin: 'admin'

  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: index_
          period: 24h

singleBinary:
  replicas: 1
  persistence:
    enabled: true
    storageClass: do-block-storage-retain
    size: 20Gi

read:
  replicas: 0
write:
  replicas: 0
backend:
  replicas: 0

ingress:
  enabled: false
gateway:
  enabled: false


**Ý nghĩa:**
Loki 6.x yêu cầu schemaConfig (tsdb/v13) → thiếu là lỗi.
SingleBinary + 1 replica phù hợp cluster nhỏ.
PVC dùng do-block-storage-retain để log không mất khi reinstall.

###10.5.3 Verify tối thiểu sau khi deploy Loki/Promtail ( nên lưu evidence)

kubectl -n observability get pods -o wide | egrep -i 'loki|promtail' \
  | tee artifacts/step10-observability/loki-promtail-pods.txt

kubectl -n observability get pvc -o wide | egrep -i 'loki' \
  | tee artifacts/step10-observability/loki-pvc.txt

kubectl -n observability get svc -o wide | egrep -i 'loki' \
  | tee artifacts/step10-observability/loki-svc.txt


**Kỳ vọng:**
Loki pod Running
PVC Loki Bound, storageClass = do-block-storage-retain
Promtail DaemonSet chạy đủ số node
