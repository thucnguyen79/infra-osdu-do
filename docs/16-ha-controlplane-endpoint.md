# Step 4.3 - HA Control Plane endpoint (Self-managed LB) + kubeadm init HA

## Goal
- Provide a stable Control Plane endpoint for kubeadm HA using a self-managed LB on AppServer01
- Initialize the first control plane node with kubeadm using that endpoint

## Design
- LB node: AppServer01 (eth1 10.118.0.8) runs HAProxy in TCP mode
- Backend: ControlPlane01-03 (eth1 10.118.0.2-4) on TCP 6443
- controlPlaneEndpoint: k8s-api.internal:6443 (mapped to 10.118.0.8)

## Important note
- With only 1 LB node, the endpoint is not fully HA (LB is a single point of failure).
  This is acceptable for the lab; production should use 2 LBs + VRRP/Keepalived or a managed LB.

## Evidence
- artifacts/step4-controlplane-endpoint/*
- (Secrets are NOT committed to git)

## Step 4.3.5 - kubeadm init on ControlPlane01
Commands (secrets are stored in artifacts-private/):
- kubeadm init:
  - sudo kubeadm init --config /etc/kubernetes/kubeadm/kubeadm-init-ha-v1.30.yaml --upload-certs
- kubeconfig for ops on CP01:
  - copy /etc/kubernetes/admin.conf to ~/.kube/config
- copy kubeconfig to ToolServer01 for management

Non-secret evidence:
- artifacts/step4-controlplane-endpoint/ControlPlane01/post-init.txt
### Chú thích
Có thể làm repo-first bằng Ansible và đó thường là hướng “tối ưu hơn” về:
- tính lặp lại (idempotent ở mức hợp lý),
- chuẩn hoá evidence/log,
- giảm thao tác tay,
- kiểm soát secrets tốt hơn (lưu vào artifacts-private/, không commit).

Tuy nhiên, dù dùng Ansible, bước kubeadm init vẫn là “one-time action”, cho nên bước này thực hiện các lệnh thủ công trước