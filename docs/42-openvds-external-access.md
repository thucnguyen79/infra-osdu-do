# OpenVDS External Access Guide

**Status:** ✅ Available via VPN  
**Date:** 2026-02-25  

---

## 1. Tổng quan

OpenVDS (Open Volume Data Store) là **CLI toolset** (không phải REST API service).  
Gồm 4 tools: `SEGYImport`, `SEGYExport`, `VDSInfo`, `VDSCopy`.

**Đã triển khai:**
- Pod `openvds-toolbox` chạy liên tục trong namespace `osdu-core`
- Image: `openvds-ingestion:3.4.9`
- S3 credentials pre-configured (Ceph RGW)
- Bucket: `osdu-seismic`

**Đã verified:**
- SEGY → VDS import (25 traces, 5×5 grid) ✅
- VDS stored on S3/Ceph ✅
- VDSInfo read from S3 ✅

---

## 2. Cách sử dụng từ bên ngoài

### Option A: VPN Access (Khuyến nghị cho POC)

Developers kết nối VPN → kubectl exec vào openvds-toolbox:
```bash
# Kết nối VPN (WireGuard)
# Sau đó từ máy có kubectl config:

# 1. Interactive shell
kubectl -n osdu-core exec -it deploy/openvds-toolbox -- bash

# 2. Check tools
which SEGYImport SEGYExport VDSInfo VDSCopy

# 3. Import SEGY file
# Copy file vào pod trước:
kubectl -n osdu-core cp /local/path/data.segy openvds-toolbox-xxx:/data/data.segy

# 4. Run import
SEGYImport \
  --url s3://osdu-seismic/surveys/my-survey \
  --url-connection "EndpointOverride=http://rook-ceph-rgw-osdu-store.rook-ceph.svc:80;Region=us-east-1;AccessKeyId=$AWS_ACCESS_KEY_ID;SecretKey=$AWS_SECRET_ACCESS_KEY" \
  /data/data.segy

# 5. Verify
VDSInfo \
  s3://osdu-seismic/surveys/my-survey/<hash-dir> \
  --connection "EndpointOverride=http://rook-ceph-rgw-osdu-store.rook-ceph.svc:80;Region=us-east-1;AccessKeyId=$AWS_ACCESS_KEY_ID;SecretKey=$AWS_SECRET_ACCESS_KEY" \
  --axis --channels
```

### Option B: Batch Job (cho production ingestion)

Dùng Job template để import SEGY files theo batch:
```bash
# Template có sẵn: k8s/osdu/core/base/services/openvds/segyimport-job-template.yaml
# Customize rồi apply:

kubectl -n osdu-core create -f - << 'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: segyimport-survey-001
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: segyimport
          image: community.opengroup.org:5555/osdu/platform/domain-data-mgmt-services/seismic/open-vds/openvds-ingestion:3.4.9
          command: ["SEGYImport"]
          args:
            - "--url"
            - "s3://osdu-seismic/surveys/survey-001"
            - "--url-connection"
            - "EndpointOverride=http://rook-ceph-rgw-osdu-store.rook-ceph.svc:80;Region=us-east-1"
            - "/data/input.segy"
          env:
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: openvds-s3-secret
                  key: ACCESS_KEY
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: openvds-s3-secret
                  key: SECRET_KEY
          volumeMounts:
            - name: data
              mountPath: /data
          resources:
            requests:
              cpu: "1"
              memory: 2Gi
            limits:
              cpu: "4"
              memory: 8Gi
      volumes:
        - name: data
          emptyDir:
            sizeLimit: 50Gi
YAML
```

### Option C: Workflow Integration (Future)

Kết hợp với OSDU Workflow service:
1. Upload SEGY via File service (`/api/file/v2/files/uploadURL`)
2. Trigger Workflow để chạy SEGYImport Job
3. Job kết quả lưu vào S3, metadata vào Storage service
4. Search/query qua OSDU API

> ⚠️ Option C cần custom Workflow DAG — chưa triển khai trong POC.

---

## 3. Connection String Reference

| Key | Value | Mô tả |
|-----|-------|-------|
| EndpointOverride | `http://rook-ceph-rgw-osdu-store.rook-ceph.svc:80` | Ceph RGW endpoint |
| Region | `us-east-1` | Required by S3 SDK |
| AccessKeyId | *(from secret)* | S3 access key |
| SecretKey | *(from secret)* | S3 secret key |

**Lưu ý quan trọng:**
- SEGYImport tạo hash subdirectory dưới `--url` path
- VDSInfo dùng `--connection` (không phải `--url-connection`)
- VDSCopy không có `--output-connection`; dùng SEGYImport direct to S3
- Keys có thể viết CamelCase hoặc snake_case

---

## 4. Seismic Store API (REST)

Seismic Store service (Node.js, port 5000) đã được expose public:
```
https://api-do-osdu.esstar.com.vn/api/seismic-store/v3/
```

| Endpoint | Method | Auth | Mô tả |
|----------|--------|------|-------|
| `/api/seismic-store/v3/svcstatus` | GET | Bearer | Service status |
| `/api/seismic-store/v3/svcstatus/readiness` | GET | No | Readiness check |
| `/api/seismic-store/v3/subproject` | GET | Bearer | List subprojects |

> Seismic Store quản lý metadata; OpenVDS xử lý data ingestion.

---

**Document Version:** 1.0  
**Created:** 2026-02-25  
