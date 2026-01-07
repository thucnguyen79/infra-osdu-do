# Step 18 — OSDU Core Services Runbook (Thực tế triển khai)

**Ngày hoàn thành:** 2026-01-07  
**Phiên bản OSDU:** M25 (Core Plus)  
**Trạng thái:** [x] HOÀN THÀNH

## Mục tiêu

Triển khai 6 OSDU Core Services trên Kubernetes cluster:
- Partition Service
- Entitlements Service  
- Storage Service
- Legal Service
- Schema Service
- File Service

---

## A. Kiến trúc & Dependencies

### Services và Versions

| Service | Image | Version | Database |
|---------|-------|---------|----------|
| Partition | `community.opengroup.org:5555/osdu/platform/system/partition/partition-core-plus` | latest | partition |
| Entitlements | `community.opengroup.org:5555/osdu/platform/security-and-compliance/entitlements/entitlements-core-plus` | 0.28.2-SNAPSHOT | entitlements |
| Storage | `community.opengroup.org:5555/osdu/platform/system/storage/storage-core-plus` | 0.28.6-SNAPSHOT | storage |
| Legal | `community.opengroup.org:5555/osdu/platform/security-and-compliance/legal/legal-core-plus` | 0.28.1-SNAPSHOT | legal |
| Schema | `community.opengroup.org:5555/osdu/platform/system/schema-service/schema-core-plus` | 0.28.1-SNAPSHOT | schema |
| File | `community.opengroup.org:5555/osdu/platform/system/file/file-core-plus` | 0.28.1-SNAPSHOT | file |

### Dependencies (namespace: osdu-data)

- **PostgreSQL** (osdu-postgres): Databases cho tất cả services
- **OpenSearch** (osdu-opensearch): Search/Index
- **Redis** (osdu-redis): Caching
- **Redpanda/Kafka** (osdu-kafka): Message queue

---
## Triển khai
### 1) Công cụ dùng trong Step 18

- **Kustomize**: quản lý base/overlay theo repo (không hardcode namespace ở base).
- **ArgoCD**: tự động sync/prune/self-heal theo GitOps.
- **Toolbox** (đã có từ Step 17): dùng để chạy curl/jq, kiểm tra DNS nội bộ, verify endpoint nhanh ngay trong cluster.

### 2) Pre-flight (bắt buộc)

> Copy/paste block này trên `ToolServer01` (đang ở repo `/opt/infra-osdu-do`).

```bash

set -euo pipefail

cd /opt/infra-osdu-do

export NS_DATA="osdu-data"
export NS_ID="osdu-identity"
export NS_CORE="osdu-core"

echo "== Namespaces ==" && kubectl get ns | egrep -n "($NS_DATA|$NS_ID|$NS_CORE)" || true

echo "== Deps health (osdu-data) ==" && kubectl -n "$NS_DATA" get pods -o wide
echo "== Identity health (osdu-identity) ==" && kubectl -n "$NS_ID" get pods -o wide
echo "== Core health (osdu-core) ==" && kubectl -n "$NS_CORE" get pods -o wide

```

**Kỳ vọng**
- `osdu-data`: `osdu-postgres-0`, `osdu-opensearch-0`, `osdu-redis-*`, `osdu-kafka/*` (hoặc redpanda) **Running/Ready**.
- `osdu-identity`: keycloak + postgres (nếu có) **Running/Ready**.
- `osdu-core`: `osdu-toolbox-*` **Running/Ready**.

---

### 3) Tự động “đóng khung” endpoint nội bộ + Keycloak issuer (không đoán)

#### 3.1. Xác định Redis/Kafka/OpenSearch service name (auto-detect)

```bash
set -euo pipefail
export NS_DATA="osdu-data"

# Redis service (ưu tiên osdu-redis, fallback osdu-redis-master)
if kubectl -n "$NS_DATA" get svc osdu-redis >/dev/null 2>&1; then
  export REDIS_SVC="osdu-redis"
elif kubectl -n "$NS_DATA" get svc osdu-redis-master >/dev/null 2>&1; then
  export REDIS_SVC="osdu-redis-master"
else
  echo "ERROR: không tìm thấy service redis trong $NS_DATA" >&2
  kubectl -n "$NS_DATA" get svc | sed -n '1,200p'
  exit 1
fi
export REDIS_HOST="${REDIS_SVC}.${NS_DATA}.svc.cluster.local"

# Kafka service (ưu tiên osdu-kafka, fallback osdu-redpanda)
if kubectl -n "$NS_DATA" get svc osdu-kafka >/dev/null 2>&1; then
  export KAFKA_SVC="osdu-kafka"
elif kubectl -n "$NS_DATA" get svc osdu-redpanda >/dev/null 2>&1; then
  export KAFKA_SVC="osdu-redpanda"
else
  echo "ERROR: không tìm thấy service kafka/redpanda trong $NS_DATA" >&2
  kubectl -n "$NS_DATA" get svc | sed -n '1,200p'
  exit 1
fi
export KAFKA_BOOTSTRAP="${KAFKA_SVC}.${NS_DATA}.svc.cluster.local:9092"

# OpenSearch service (ưu tiên osdu-opensearch)
if kubectl -n "$NS_DATA" get svc osdu-opensearch >/dev/null 2>&1; then
  export OPENSEARCH_SVC="osdu-opensearch"
else
  echo "ERROR: không tìm thấy service opensearch trong $NS_DATA" >&2
  kubectl -n "$NS_DATA" get svc | sed -n '1,200p'
  exit 1
fi
export OPENSEARCH_HOST="${OPENSEARCH_SVC}.${NS_DATA}.svc.cluster.local"
export OPENSEARCH_PORT="9200"

# Postgres service (theo repo của bạn: osdu-postgres)
export POSTGRES_HOST="osdu-postgres.${NS_DATA}.svc.cluster.local"
export POSTGRES_PORT="5432"

echo "REDIS_HOST=$REDIS_HOST"
echo "KAFKA_BOOTSTRAP=$KAFKA_BOOTSTRAP"
echo "OPENSEARCH_HOST=$OPENSEARCH_HOST"
echo "POSTGRES_HOST=$POSTGRES_HOST"

```

#### 3.2. Lấy Keycloak issuer URI “đúng chuẩn” từ well-known (tự dò /auth)

> Dùng `osdu-toolbox` để curl nội bộ (tránh phụ thuộc ingress/DNS bên ngoài).
Kết quả kiểm tra dịch vụ Keycloak
ops@ToolServer01:/opt/infra-osdu-do$ kubectl -n osdu-identity get svc
NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
keycloak      ClusterIP   10.103.61.58    <none>        80/TCP     2d7h
keycloak-db   ClusterIP   10.109.169.57   <none>        5432/TCP   2d7h

```bash
set -euo pipefail

# 1. Cấu hình biến môi trường
export NS_CORE="osdu-core"
export NS_ID="osdu-identity"
export KEYCLOAK_REALM="osdu"
# Tên service chính xác của bạn là "keycloak"
export KEYCLOAK_SVC_DNS="keycloak.${NS_ID}.svc.cluster.local"

# Biến cờ để đánh dấu tìm thấy hay chưa
FOUND_KEYCLOAK="false"
export KEYCLOAK_BASE_PATH=""

echo "Đang kiểm tra Keycloak tại: http://${KEYCLOAK_SVC_DNS}"

# 2. Vòng lặp dò tìm (Thử cả root và /auth)
for p in "" "/auth"; do
  CHECK_URL="http://${KEYCLOAK_SVC_DNS}${p}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration"
  
  if kubectl -n "$NS_CORE" exec deploy/osdu-toolbox -- sh -lc \
    "curl -fsS ${CHECK_URL} >/dev/null"; then
    export KEYCLOAK_BASE_PATH="$p"
    FOUND_KEYCLOAK="true"
    echo "SUCCESS: Tìm thấy Keycloak tại path prefix: '$p'"
    break
  fi
done

# 3. Kiểm tra dựa trên biến cờ (Thay vì kiểm tra chuỗi rỗng)
if [ "$FOUND_KEYCLOAK" != "true" ]; then
  echo "ERROR: không truy cập được well-known trên Keycloak (cả '' và '/auth')." >&2
  exit 1
fi

# 4. Xuất kết quả
export KEYCLOAK_BASE_URL="http://${KEYCLOAK_SVC_DNS}${KEYCLOAK_BASE_PATH}"
export KEYCLOAK_ISSUER_URI="$(kubectl -n "$NS_CORE" exec deploy/osdu-toolbox -- sh -lc \
  "curl -fsS ${KEYCLOAK_BASE_URL}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration | jq -r .issuer")"

echo "----------------------------------------"
echo "KEYCLOAK_BASE_URL=$KEYCLOAK_BASE_URL"
echo "KEYCLOAK_ISSUER_URI=$KEYCLOAK_ISSUER_URI"
echo "----------------------------------------"

```

**Kỳ vọng**
- In ra được `KEYCLOAK_BASE_URL=...` và `KEYCLOAK_ISSUER_URI=...` (không rỗng).

---

### 4) Secrets out-of-band trong `osdu-core` (không commit lên repo)

#### 4.1. Copy credential Postgres từ `osdu-data` sang `osdu-core`

> Mục tiêu: services ở `osdu-core` dùng DB user/pass giống Step 16 initdb.

```bash
set -euo pipefail
export NS_DATA="osdu-data"
export NS_CORE="osdu-core"

# Lấy user/pass từ secret ở osdu-data
PG_USER="$(kubectl -n "$NS_DATA" get secret osdu-postgres-secret -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)"
PG_PASS="$(kubectl -n "$NS_DATA" get secret osdu-postgres-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"

# Tạo/Update secret ở osdu-core
kubectl -n "$NS_CORE" create secret generic osdu-postgres-secret \
  --from-literal=POSTGRES_USER="$PG_USER" \
  --from-literal=POSTGRES_PASSWORD="$PG_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS_CORE" get secret osdu-postgres-secret
```

#### 4.2. ObjectStore secret (Ceph RGW / S3)

Tạo secret `osdu-objectstore-secret` trong `osdu-core` với các key bạn đang dùng.

> copy từ namespace `osdu-data` vì secret tồn tại ở đó.


Lệnh này sẽ:

Lấy secret osdu-s3-credentials từ osdu-data.
Đổi tên nó thành osdu-objectstore-secret (cho đúng chuẩn Core Service).
Copy sang osdu-core.

Bash
```bash
set -euo pipefail

# 1. Kiểm tra nguồn (osdu-data)
if kubectl -n osdu-data get secret osdu-s3-credentials >/dev/null 2>&1; then
  echo "Tìm thấy secret gốc 'osdu-s3-credentials' bên osdu-data."
  
  # 2. Thực hiện Copy và Đổi tên
  echo "Đang copy sang osdu-core..."
  kubectl -n osdu-data get secret osdu-s3-credentials -o json \
    | jq 'del(.metadata.namespace,.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,.metadata.annotations,.metadata.ownerReferences,.metadata.managedFields) | .metadata.name="osdu-objectstore-secret"' \
    | kubectl -n osdu-core apply -f -
    
  echo "Đã tạo thành công secret 'osdu-objectstore-secret' trong osdu-core."
else
  echo "LỖI: Không tìm thấy 'osdu-s3-credentials' bên osdu-data. Bạn cần kiểm tra lại Step 16."
  exit 1
fi

# 3. Kiểm tra lại kết quả
kubectl -n osdu-core get secret osdu-objectstore-secret
```

#### 4.3. (Tuỳ chọn) ImagePullSecret cho registry community.opengroup.org:5555

Nếu pod bị `ImagePullBackOff` do registry yêu cầu auth, hãy tạo secret và patch SA `default`.

```bash
# CHỈ chạy nếu bạn bị ImagePullBackOff với lỗi unauthorized
# kubectl -n osdu-core create secret docker-registry osdu-regcred \
#   --docker-server=community.opengroup.org:5555 \
#   --docker-username='<YOUR_USER>' \
#   --docker-password='<YOUR_PASS>' \
#   --dry-run=client -o yaml | kubectl apply -f -
#
# kubectl -n osdu-core patch serviceaccount default -p '{"imagePullSecrets":[{"name":"osdu-regcred"}]}'
```

---
Bỏ qua bước này.Lý do bỏ qua:
- Registry community.opengroup.org:5555 của cộng đồng OSDU thường để chế độ Public cho các image hệ thống (Partition, Entitlements, Legal...).
- Hầu hết mọi người deploy OSDU bản Community đều không cần đăng nhập vẫn kéo được image về bình thường.

Khi nào thì quay lại làm?
Bạn chỉ cần làm bước này nếu sau khi deploy (ở bước 5.1, 5.2 sắp tới), bạn chạy lệnh kubectl get pods mà thấy trạng thái: ImagePullBackOff hoặc ErrImagePull kèm theo lỗi "Unauthorized" trong phần describe.
Lúc đó, bạn sẽ cần đăng ký tài khoản trên community.opengroup.org, tạo Access Token và chạy lệnh tạo secret như hướng dẫn.

Hành động ngay bây giờ: Không chạy lệnh gì cả ở bước 4.3. Hãy chuyển thẳng sang Bước 5: Repo-first: tạo manifests cho core services trong runbook.

### 5) Repo-first: tạo manifests cho core services

> **Quan trọng:** ArgoCD App `osdu-core` đang trỏ tới:
> `k8s/osdu/core/overlays/do-private` (namespace đích: `osdu-core`) — chỉ cần commit/push là ArgoCD sẽ sync.

#### 5.1. Tạo structure thư mục

```bash
set -euo pipefail
cd /opt/infra-osdu-do

mkdir -p k8s/osdu/core/base/services/{partition,entitlements,schema,legal,storage,file}
```

#### 5.2. Tạo Deployment + Service cho từng core service

> Lưu ý:
> - Port chuẩn: `8080`
> - Probe dùng `tcpSocket` để tránh lệch path health (mỗi service có thể khác nhau).
> - DB name theo Step 16 initdb: `partition`, `entitlements`, `schema`, `legal`, `storage`, `file`.
> - Các image có thể tham khảo trực tiếp trên community.opengroup.org

##### 5.2.1 Partition
Dùng core-plus-partition-release: https://community.opengroup.org/osdu/platform/system/partition/container_registry/23667?orderBy=NAME&sort=desc
Link:
community.opengroup.org:5555/osdu/platform/system/partition/core-plus-partition-release:923ea1cd

```bash
cat > k8s/osdu/core/base/services/partition/partition-deploy.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: osdu-partition
  labels:
    app: osdu-partition
spec:
  replicas: 1
  selector:
    matchLabels:
      app: osdu-partition
  template:
    metadata:
      labels:
        app: osdu-partition
    spec:
      containers:
        - name: partition
          # DÙNG CHÍNH XÁC IMAGE DÀI NÀY (Không rút gọn, không sửa tag)
          image: community.opengroup.org:5555/osdu/platform/system/partition/core-plus-partition-release:923ea1cd
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: osdu-core-env
          env:
            # Cấu hình chuẩn cho Core Plus
            - name: SPRING_DATASOURCE_URL
              value: "jdbc:postgresql://$(POSTGRES_HOST):$(POSTGRES_PORT)/partition"
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_USER
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_PASSWORD
            - name: SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI
              value: "$(KEYCLOAK_ISSUER_URI)"
            # Tạm tắt Auth để test
            - name: PARTITION_AUTH_ENABLED
              value: "false"
            # Cấu hình Provider cho Core Plus
            - name: CLOUD_PROVIDER
              value: "minio"
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 10
EOF

cat > k8s/osdu/core/base/services/partition/partition-svc.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: osdu-partition
  labels:
    app: osdu-partition
spec:
  type: ClusterIP
  selector:
    app: osdu-partition
  ports:
    - name: http
      port: 8080
      targetPort: 8080
EOF
```

##### 5.2.2 Entitlements

```bash
cat > k8s/osdu/core/base/services/entitlements/entitlements-deploy.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: osdu-entitlements
  labels:
    app: osdu-entitlements
spec:
  replicas: 1
  selector:
    matchLabels:
      app: osdu-entitlements
  template:
    metadata:
      labels:
        app: osdu-entitlements
    spec:
      containers:
        - name: entitlements
          image: community.opengroup.org:5555/osdu/platform/security-and-compliance/entitlements:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: osdu-core-env
          env:
            - name: SPRING_DATASOURCE_URL
              value: "jdbc:postgresql://$(POSTGRES_HOST):$(POSTGRES_PORT)/entitlements"
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_USER
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_PASSWORD
            - name: SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI
              value: "$(KEYCLOAK_ISSUER_URI)"
            - name: PARTITION_BASE_URL
              value: "http://osdu-partition:8080"
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 20
EOF

cat > k8s/osdu/core/base/services/entitlements/entitlements-svc.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: osdu-entitlements
  labels:
    app: osdu-entitlements
spec:
  type: ClusterIP
  selector:
    app: osdu-entitlements
  ports:
    - name: http
      port: 8080
      targetPort: 8080
EOF
```

##### 5.2.3 Schema service

> Endpoint `/api/schema-service/v1/info` được dùng phổ biến để check nhanh (tuỳ version) citeturn14search11.

```bash
cat > k8s/osdu/core/base/services/schema/schema-deploy.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: osdu-schema
  labels:
    app: osdu-schema
spec:
  replicas: 1
  selector:
    matchLabels:
      app: osdu-schema
  template:
    metadata:
      labels:
        app: osdu-schema
    spec:
      containers:
        - name: schema
          image: community.opengroup.org:5555/osdu/platform/system/schema-service:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: osdu-core-env
          env:
            - name: SPRING_DATASOURCE_URL
              value: "jdbc:postgresql://$(POSTGRES_HOST):$(POSTGRES_PORT)/schema"
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_USER
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_PASSWORD
            - name: SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI
              value: "$(KEYCLOAK_ISSUER_URI)"
            - name: PARTITION_BASE_URL
              value: "http://osdu-partition:8080"
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 20
EOF

cat > k8s/osdu/core/base/services/schema/schema-svc.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: osdu-schema
  labels:
    app: osdu-schema
spec:
  type: ClusterIP
  selector:
    app: osdu-schema
  ports:
    - name: http
      port: 8080
      targetPort: 8080
EOF
```

##### 5.2.4 Legal

```bash
cat > k8s/osdu/core/base/services/legal/legal-deploy.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: osdu-legal
  labels:
    app: osdu-legal
spec:
  replicas: 1
  selector:
    matchLabels:
      app: osdu-legal
  template:
    metadata:
      labels:
        app: osdu-legal
    spec:
      containers:
        - name: legal
          image: community.opengroup.org:5555/osdu/platform/security-and-compliance/legal:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: osdu-core-env
          env:
            - name: SPRING_DATASOURCE_URL
              value: "jdbc:postgresql://$(POSTGRES_HOST):$(POSTGRES_PORT)/legal"
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_USER
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_PASSWORD
            - name: SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI
              value: "$(KEYCLOAK_ISSUER_URI)"
            - name: PARTITION_BASE_URL
              value: "http://osdu-partition:8080"
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 20
EOF

cat > k8s/osdu/core/base/services/legal/legal-svc.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: osdu-legal
  labels:
    app: osdu-legal
spec:
  type: ClusterIP
  selector:
    app: osdu-legal
  ports:
    - name: http
      port: 8080
      targetPort: 8080
EOF
```

##### 5.2.5 Storage (tuỳ chọn nhưng thường cần)

```bash
cat > k8s/osdu/core/base/services/storage/storage-deploy.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: osdu-storage
  labels:
    app: osdu-storage
spec:
  replicas: 1
  selector:
    matchLabels:
      app: osdu-storage
  template:
    metadata:
      labels:
        app: osdu-storage
    spec:
      containers:
        - name: storage
          image: community.opengroup.org:5555/osdu/platform/system/storage:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: osdu-core-env
          env:
            - name: SPRING_DATASOURCE_URL
              value: "jdbc:postgresql://$(POSTGRES_HOST):$(POSTGRES_PORT)/storage"
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_USER
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_PASSWORD
            - name: SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI
              value: "$(KEYCLOAK_ISSUER_URI)"
            - name: PARTITION_BASE_URL
              value: "http://osdu-partition:8080"
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 20
EOF

cat > k8s/osdu/core/base/services/storage/storage-svc.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: osdu-storage
  labels:
    app: osdu-storage
spec:
  type: ClusterIP
  selector:
    app: osdu-storage
  ports:
    - name: http
      port: 8080
      targetPort: 8080
EOF
```

##### 5.2.6 File (tuỳ chọn)

```bash
cat > k8s/osdu/core/base/services/file/file-deploy.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: osdu-file
  labels:
    app: osdu-file
spec:
  replicas: 1
  selector:
    matchLabels:
      app: osdu-file
  template:
    metadata:
      labels:
        app: osdu-file
    spec:
      containers:
        - name: file
          image: community.opengroup.org:5555/osdu/platform/system/file:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: osdu-core-env
          env:
            - name: SPRING_DATASOURCE_URL
              value: "jdbc:postgresql://$(POSTGRES_HOST):$(POSTGRES_PORT)/file"
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_USER
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_PASSWORD
            - name: SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI
              value: "$(KEYCLOAK_ISSUER_URI)"
            - name: PARTITION_BASE_URL
              value: "http://osdu-partition:8080"
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 20
EOF

cat > k8s/osdu/core/base/services/file/file-svc.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: osdu-file
  labels:
    app: osdu-file
spec:
  type: ClusterIP
  selector:
    app: osdu-file
  ports:
    - name: http
      port: 8080
      targetPort: 8080
EOF
```

#### 5.3. Update kustomization.yaml (base + overlay)

##### 5.3.1 Base: `k8s/osdu/core/base/kustomization.yaml`

```bash
cat > k8s/osdu/core/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  # toolbox (Step 17)
  - toolbox/toolbox-deploy.yaml

  # core services (Step 18)
  - services/partition/partition-deploy.yaml
  - services/partition/partition-svc.yaml

  - services/entitlements/entitlements-deploy.yaml
  - services/entitlements/entitlements-svc.yaml

  - services/schema/schema-deploy.yaml
  - services/schema/schema-svc.yaml

  - services/legal/legal-deploy.yaml
  - services/legal/legal-svc.yaml

  - services/storage/storage-deploy.yaml
  - services/storage/storage-svc.yaml

  - services/file/file-deploy.yaml
  - services/file/file-svc.yaml
EOF
```

##### 5.3.2 Overlay: `k8s/osdu/core/overlays/do-private/kustomization.yaml`

> **Chú ý:** block dưới đây dùng luôn các biến bạn đã export ở phần 3.

```bash
cat > k8s/osdu/core/overlays/do-private/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: osdu-core

resources:
  - ../../base
  - namespace.yaml
  - marker-configmap.yaml

generatorOptions:
  disableNameSuffixHash: true

configMapGenerator:
  - name: osdu-core-env
    literals:
      - POSTGRES_HOST=${POSTGRES_HOST}
      - POSTGRES_PORT=${POSTGRES_PORT}
      - REDIS_HOST=${REDIS_HOST}
      - KAFKA_BOOTSTRAP_SERVERS=${KAFKA_BOOTSTRAP}
      - OPENSEARCH_HOST=${OPENSEARCH_HOST}
      - OPENSEARCH_PORT=${OPENSEARCH_PORT}
      - KEYCLOAK_BASE_URL=${KEYCLOAK_BASE_URL}
      - KEYCLOAK_REALM=${KEYCLOAK_REALM}
      - KEYCLOAK_ISSUER_URI=${KEYCLOAK_ISSUER_URI}

images:
  # Bạn có thể đổi newTag sang m23/m24 khi đã chắc tag tồn tại
  - name: community.opengroup.org:5555/osdu/platform/system/partition
    newTag: latest
  - name: community.opengroup.org:5555/osdu/platform/security-and-compliance/entitlements
    newTag: latest
  - name: community.opengroup.org:5555/osdu/platform/system/schema-service
    newTag: latest
  - name: community.opengroup.org:5555/osdu/platform/security-and-compliance/legal
    newTag: latest
  - name: community.opengroup.org:5555/osdu/platform/system/storage
    newTag: latest
  - name: community.opengroup.org:5555/osdu/platform/system/file
    newTag: latest
EOF
```

---

### 6) Render / Diff nhanh (local) trước khi commit

```bash
set -euo pipefail
cd /opt/infra-osdu-do

TS="$(date +%F-%H%M%S)"
mkdir -p artifacts/step18-osdu-core-services/"$TS"

kubectl kustomize k8s/osdu/core/overlays/do-private \
  | tee artifacts/step18-osdu-core-services/"$TS"/render.yaml >/dev/null

echo "Render OK: artifacts/step18-osdu-core-services/$TS/render.yaml"
grep -n "kind: Deployment" -n artifacts/step18-osdu-core-services/"$TS"/render.yaml | head
```

---

### 7) Commit & Push (Repo-first)

```bash
set -euo pipefail
cd /opt/infra-osdu-do

git status
git add k8s/osdu/core/base k8s/osdu/core/overlays/do-private
git commit -m "Step18: deploy OSDU core services (partition/entitlements/schema/legal/storage/file)"
git push origin main
```

---

### 8) Sync/Verify (ArgoCD + Kubernetes)

#### 8.1. Theo dõi rollout

```bash
set -euo pipefail
export NS_CORE="osdu-core"

kubectl -n "$NS_CORE" get deploy,svc
kubectl -n "$NS_CORE" get pods -o wide

# theo dõi cho tới khi Ready
watch -n 2 "kubectl -n $NS_CORE get pods -o wide"
```

**Kỳ vọng**
- `osdu-partition`, `osdu-entitlements`, `osdu-schema`, `osdu-legal`, `osdu-storage`, `osdu-file` đều `1/1` Ready.

#### 8.2. Smoke test nội bộ từ toolbox

```bash
set -euo pipefail
export NS_CORE="osdu-core"

kubectl -n "$NS_CORE" exec deploy/osdu-toolbox -- sh -lc '
set -e
for svc in osdu-partition osdu-entitlements osdu-schema osdu-legal osdu-storage osdu-file; do
  echo "== $svc =="
  # thử các endpoint info phổ biến (có service sẽ khác; nếu 404 vẫn OK, miễn service trả HTTP)
  for path in \
    "/api/partition/v1/info" \
    "/api/entitlements/v2/info" \
    "/api/schema-service/v1/info" \
    "/api/legal/v1/info" \
    "/api/storage/v2/info" \
    "/api/file/v2/info" \
    "/actuator/health" \
    "/health" \
    "/"; do
    code="$(curl -s -o /dev/null -w "%{http_code}" http://$svc:8080$path || true)"
    if [ "$code" != "000" ]; then
      echo "  $path => $code"
      break
    fi
  done
done
'
```

**Kỳ vọng**
- Mỗi service trả về HTTP code khác `000` (tức đã nghe cổng và trả response).
- Nếu service yêu cầu auth, có thể trả `401/403` — vẫn chấp nhận ở mức Step 18 (deploy/ready OK).

---

### 9) Troubleshooting nhanh

#### 9.1. Pod CrashLoopBackOff / lỗi config
```bash
kubectl -n osdu-core logs deploy/osdu-partition --tail=200
kubectl -n osdu-core describe pod -l app=osdu-partition | sed -n '1,220p'
```

#### 9.2. DB connect fail
- Kiểm tra secret `osdu-postgres-secret` trong `osdu-core`:
```bash
kubectl -n osdu-core get secret osdu-postgres-secret -o yaml | sed -n '1,120p'
```
- Test DNS/port từ toolbox:
```bash
kubectl -n osdu-core exec deploy/osdu-toolbox -- sh -lc "nc -vz ${POSTGRES_HOST} 5432 || true"
```

#### 9.3. ImagePullBackOff
- Nếu lỗi `unauthorized`: tạo `osdu-regcred` và patch SA (mục 4.3).
- Nếu lỗi `manifest unknown`: đổi tag về `latest` hoặc tag tồn tại.

---

### C. Các lỗi gặp phải và cách giải quyết

#### Issue 1: Redis Connection Error (Storage Service)

**Triệu chứng:**
```
RedisConnectionFailureException: Unable to connect to Redis
Connection refused: osdu-redis.osdu-data/10.x.x.x:6379
```

**Nguyên nhân:**
Storage service cần các biến môi trường riêng cho Redis:
- `REDIS_STORAGE_HOST`
- `REDIS_GROUP_HOST`

**Giải pháp:**
Thêm vào ConfigMap `osdu-core-env`:
```yaml
configMapGenerator:
  - name: osdu-core-env
    literals:
      - REDIS_HOST=osdu-redis.osdu-data.svc.cluster.local
      - REDIS_STORAGE_HOST=osdu-redis.osdu-data.svc.cluster.local
      - REDIS_GROUP_HOST=osdu-redis.osdu-data.svc.cluster.local
```

---

### Issue 2: Partition PostgreSQL Connection Failed

**Triệu chứng:**
```
RuntimeException: Driver shaded.org.postgresql.Driver claims to not accept jdbcUrl, ${PARTITION_POSTGRES_URL}
```

**Nguyên nhân:**
Partition service sử dụng OSM library với các biến môi trường khác:
- `PARTITION_POSTGRES_URL`
- `PARTITION_POSTGRESQL_USERNAME` (không phải `PARTITION_POSTGRES_USERNAME`)
- `PARTITION_POSTGRESQL_PASSWORD`

**Cách tìm ra:**
```bash
# Extract application.properties từ JAR
kubectl -n osdu-core exec deploy/osdu-partition -- sh -c \
  "cd /tmp && jar xf /app/partition-core-plus.jar BOOT-INF/classes/application.properties && cat BOOT-INF/classes/application.properties"

# Output cho thấy:
# osm.postgres.username=${PARTITION_POSTGRESQL_USERNAME:usr_partition_pg}
# osm.postgres.password=${PARTITION_POSTGRESQL_PASSWORD:partition_pg}
```

**Giải pháp:**
Tạo patch file `patches/patch-partition-env.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: osdu-partition
spec:
  template:
    spec:
      containers:
        - name: partition
          env:
            - name: PARTITION_POSTGRES_URL
              value: "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/partition"
            - name: PARTITION_POSTGRESQL_USERNAME
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_USER
            - name: PARTITION_POSTGRESQL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: osdu-postgres-secret
                  key: POSTGRES_PASSWORD
```

---

### Issue 3: Partition Database Schema Missing (OSM Tables)

**Triệu chứng:**
```
PSQLException: ERROR: relation "partition_property" does not exist
```

**Nguyên nhân:**
Partition service sử dụng OSM (Object Storage Manager) library cần schema đặc biệt với JSONB columns.

**Giải pháp:**
Tạo schema thủ công trong PostgreSQL:
```sql
\c partition

CREATE TABLE IF NOT EXISTS partition_property (
    pk BIGSERIAL PRIMARY KEY,
    id VARCHAR(255) NOT NULL UNIQUE,
    data JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_partition_property_id ON partition_property(id);
```

---

### Issue 4: Entitlements Missing Datasource Properties

**Triệu chứng:**
```
PartitionPropertyNotFoundException: Partition property was not found, property: entitlements.datasource.url
```

**Nguyên nhân:**
OSDU Core Plus services lấy datasource config từ **Partition service**, không phải từ environment variables trực tiếp.

**Giải pháp:**
Seed partition properties (xem Section D).

---

### Issue 5: Sensitive Property Pattern

**Triệu chứng:**
```
EnvVariableSensitivePropertyResolver: jdbc:postgresql://... not configured correctly
```

**Nguyên nhân:**
Khi partition property có `sensitive: true`, OSDU Core Plus sử dụng **value làm tên biến môi trường**, không phải giá trị trực tiếp.

**Ví dụ sai:**
```json
{
  "entitlements.datasource.url": {
    "sensitive": true,
    "value": "jdbc:postgresql://..."  // SAI! Service sẽ tìm env var có tên này
  }
}
```

**Ví dụ đúng:**
```json
{
  "entitlements.datasource.url": {
    "sensitive": false,  // URL không sensitive
    "value": "jdbc:postgresql://osdu-postgres.osdu-data:5432/entitlements"
  },
  "entitlements.datasource.password": {
    "sensitive": true,  // Password sensitive
    "value": "ENTITLEMENTS_DB_PASSWORD"  // Tên env var, không phải password thật
  }
}
```

**Và trong deployment phải có:**
```yaml
env:
  - name: ENTITLEMENTS_DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: osdu-postgres-secret
        key: POSTGRES_PASSWORD
```

---

### Issue 6: Schema/File Services - UnknownHostException "partition"

**Triệu chứng:**
```
UnknownHostException: partition: Name or service not known
```

**Nguyên nhân:**
Services thiếu biến `PARTITION_API`, mặc định call hostname `partition` thay vì `osdu-partition`.

**Giải pháp:**
Thêm vào ConfigMap:
```yaml
- PARTITION_API=http://osdu-partition:8080/api/partition/v1
```

---

### Issue 7: ArgoCD Sync Error - value + valueFrom conflict

**Triệu chứng:**
```
Deployment.apps "osdu-file" is invalid: spec.template.spec.containers[0].env[0].valueFrom: 
Invalid value: "": may not be specified when `value` is not empty
```

**Nguyên nhân:**
Sử dụng `kubectl set env` (đặt `value` trực tiếp) sau đó tạo patch với `valueFrom` → conflict.

**Giải pháp:**
- Không dùng `kubectl set env` - vi phạm repo-first
- Nếu đã có `envFrom: configMapRef`, không cần patch riêng cho từng env var
- ConfigMap đã chứa PARTITION_API và được inject qua `envFrom`

---

## C. Cấu trúc Files (Repo-First)

```
k8s/osdu/core/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── services/
│   │   ├── partition/
│   │   │   ├── partition-deploy.yaml
│   │   │   └── partition-svc.yaml
│   │   ├── entitlements/
│   │   ├── storage/
│   │   ├── legal/
│   │   ├── schema/
│   │   └── file/
│   └── toolbox/
│       └── toolbox-deploy.yaml
└── overlays/
    └── do-private/
        ├── kustomization.yaml
        ├── marker-configmap.yaml
        ├── extra/
        │   └── 00-keycloak-internal-dns-alias.yaml
        └── patches/
            ├── patch-partition-env.yaml
            ├── patch-entitlements.yaml
            └── patch-entitlements-db.yaml
```

### kustomization.yaml (overlay)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: osdu-core

resources:
  - ../../base
  - marker-configmap.yaml
  - extra/00-keycloak-internal-dns-alias.yaml

patches:
  - path: patches/patch-partition-env.yaml
  - path: patches/patch-entitlements.yaml
  - path: patches/patch-entitlements-db.yaml

generatorOptions:
  disableNameSuffixHash: true

configMapGenerator:
  - name: osdu-core-env
    literals:
      - POSTGRES_HOST=osdu-postgres.osdu-data.svc.cluster.local
      - POSTGRES_PORT=5432
      - REDIS_HOST=osdu-redis.osdu-data.svc.cluster.local
      - REDIS_PORT=6379
      - REDIS_STORAGE_HOST=osdu-redis.osdu-data.svc.cluster.local
      - REDIS_GROUP_HOST=osdu-redis.osdu-data.svc.cluster.local
      - KAFKA_BOOTSTRAP_SERVERS=osdu-kafka.osdu-data.svc.cluster.local:9092
      - OPENSEARCH_HOST=osdu-opensearch.osdu-data.svc.cluster.local
      - OPENSEARCH_PORT=9200
      - KEYCLOAK_ISSUER_URI=http://keycloak.internal/realms/osdu
      - PARTITION_API=http://osdu-partition:8080/api/partition/v1
      - JAVA_OPTS=-Xms256m -Xmx512m
      - SERVER_PORT=8080
```

---

## D. Partition Properties Seeding (Bắt buộc sau khi deploy)

### Tại sao cần seed?

OSDU Core Plus services lấy datasource configuration từ Partition service, không phải từ environment variables. Đây là runtime data, không thể GitOps hóa.

### Script Seed Partition "osdu"

```bash
#!/bin/bash
# File: scripts/seed-partition-osdu.sh
# Chạy từ ToolServer01 sau khi tất cả services đã Running

TOOLBOX="kubectl -n osdu-core exec deploy/osdu-toolbox --"
PARTITION_API="http://osdu-partition:8080/api/partition/v1"

echo "=== Creating partition 'osdu' ==="
$TOOLBOX curl -s -X POST "$PARTITION_API/partitions/osdu" \
  -H "Content-Type: application/json" \
  -H "data-partition-id: osdu" \
  -d '{
    "properties": {
      "compliance-ruleset": {"sensitive": false, "value": "shared"},
      "elastic-endpoint": {"sensitive": false, "value": "http://osdu-opensearch.osdu-data:9200"},
      "elastic-username": {"sensitive": false, "value": "admin"},
      "elastic-password": {"sensitive": false, "value": "admin"},
      "storage-account-name": {"sensitive": false, "value": "osdu"},
      "redis-database": {"sensitive": false, "value": "4"},
      
      "entitlements.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/entitlements"},
      "entitlements.datasource.username": {"sensitive": false, "value": "osduadmin"},
      "entitlements.datasource.password": {"sensitive": true, "value": "ENTITLEMENTS_DB_PASSWORD"},
      "entitlements.datasource.schema": {"sensitive": false, "value": "public"},
      
      "legal.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/legal"},
      "legal.datasource.username": {"sensitive": false, "value": "osduadmin"},
      "legal.datasource.password": {"sensitive": true, "value": "LEGAL_DB_PASSWORD"},
      "legal.datasource.schema": {"sensitive": false, "value": "public"},
      
      "storage.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/storage"},
      "storage.datasource.username": {"sensitive": false, "value": "osduadmin"},
      "storage.datasource.password": {"sensitive": true, "value": "STORAGE_DB_PASSWORD"},
      "storage.datasource.schema": {"sensitive": false, "value": "public"},
      
      "schema.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/schema"},
      "schema.datasource.username": {"sensitive": false, "value": "osduadmin"},
      "schema.datasource.password": {"sensitive": true, "value": "SCHEMA_DB_PASSWORD"},
      "schema.datasource.schema": {"sensitive": false, "value": "public"},
      
      "file.datasource.url": {"sensitive": false, "value": "jdbc:postgresql://osdu-postgres.osdu-data.svc.cluster.local:5432/file"},
      "file.datasource.username": {"sensitive": false, "value": "osduadmin"},
      "file.datasource.password": {"sensitive": true, "value": "FILE_DB_PASSWORD"},
      "file.datasource.schema": {"sensitive": false, "value": "public"}
    }
  }'

echo ""
echo "=== Verifying partition ==="
$TOOLBOX curl -s "$PARTITION_API/partitions" | jq .
```

### Lưu ý quan trọng về Sensitive Properties

Khi `sensitive: true`, service sẽ **đọc giá trị từ biến môi trường** có tên = value.

Do đó, trong deployment của mỗi service cần có:
```yaml
env:
  - name: ENTITLEMENTS_DB_PASSWORD  # Tên phải khớp với value trong partition
    valueFrom:
      secretKeyRef:
        name: osdu-postgres-secret
        key: POSTGRES_PASSWORD
```

---

## E. Checklist Vận hành

### E.1 Sau khi Deploy lần đầu

- [ ] Tất cả pods Running (`kubectl -n osdu-core get pods`)
- [ ] Chạy script seed partition (Section D)
- [ ] Restart các services để nhận partition properties:
  ```bash
  kubectl -n osdu-core rollout restart deploy osdu-entitlements osdu-storage osdu-legal osdu-schema osdu-file
  ```
- [ ] Verify tất cả services trả về `/info`:
  ```bash
  for svc in partition entitlements storage legal schema file; do
    echo "=== $svc ==="
    kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s "http://osdu-$svc:8080/api/${svc}/v1/info" 2>/dev/null || \
    kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s "http://osdu-$svc:8080/api/${svc}/v2/info" 2>/dev/null || \
    kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s "http://osdu-$svc:8080/api/${svc}-service/v1/info"
  done
  ```

### E.2 Khi ArgoCD Sync

ArgoCD sync sẽ **KHÔNG** ảnh hưởng đến:
- Partition properties (trong database)
- PostgreSQL data
- OpenSearch indices

ArgoCD sync **SẼ** apply lại:
- ConfigMaps
- Deployments (với env vars từ repo)
- Services, Ingress

### E.3 Thêm Partition mới

```bash
# Tạo partition mới (ví dụ: "tenant2")
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s -X POST \
  "http://osdu-partition:8080/api/partition/v1/partitions/tenant2" \
  -H "Content-Type: application/json" \
  -H "data-partition-id: tenant2" \
  -d '{"properties": {...}}'
```

---

## F. Troubleshooting Commands

```bash
# Xem logs service
kubectl -n osdu-core logs -l app=osdu-<service> --tail=100 -f

# Xem env của deployment
kubectl -n osdu-core describe deploy osdu-<service> | grep -A50 "Environment:"

# Test connectivity từ toolbox
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s http://osdu-<service>:8080/api/.../info

# Xem partition properties
kubectl -n osdu-core exec deploy/osdu-toolbox -- curl -s \
  "http://osdu-partition:8080/api/partition/v1/partitions/osdu" | jq .

# Extract application.properties từ JAR
kubectl -n osdu-core exec deploy/osdu-<service> -- sh -c \
  "cd /tmp && jar xf /app/<service>*.jar BOOT-INF/classes/application.properties && cat BOOT-INF/classes/application.properties"
```

---

## G. Key Learnings

1. **OSDU Core Plus lấy config từ Partition Service** - không phải từ env vars trực tiếp
2. **Sensitive property pattern** - `sensitive: true` = value là tên env var
3. **OSM library có naming convention riêng** - `PARTITION_POSTGRESQL_USERNAME` không phải `PARTITION_POSTGRES_USERNAME`
4. **Không dùng `kubectl set env`** - vi phạm repo-first, conflict với GitOps
5. **envFrom + ConfigMap** - cách chuẩn để inject nhiều env vars

---

## H. References

- [OSDU Core Plus Documentation](https://community.opengroup.org/osdu/platform)
- [OSM Library](https://community.opengroup.org/osdu/platform/system/lib/core/os-osm-core)
- Transcript: `/mnt/transcripts/2026-01-07-07-13-17-osdu-core-services-operational.txt`
