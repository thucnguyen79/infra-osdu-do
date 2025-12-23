# Step 4.1 - Kubernetes Node Baseline (kubeadm prerequisites)

## Scope
Applies to:
- ControlPlane01-03
- WorkerNode01-02

Not applied to:
- AppServer01 (LB)
- ToolServer01 (management/VPN)

## Goals
- Disable swap
- Load kernel modules: overlay, br_netfilter
- sysctl: ip_forward=1, bridge-nf-call-iptables=1
- Install & configure containerd (SystemdCgroup=true)
- Provide evidence logs in artifacts/step4-node-baseline/

## Evidence
- artifacts/step4-node-baseline/run.log
- artifacts/step4-node-baseline/<node>/*
