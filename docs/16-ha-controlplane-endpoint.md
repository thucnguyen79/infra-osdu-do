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
