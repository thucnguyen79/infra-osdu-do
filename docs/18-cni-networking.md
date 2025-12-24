# Step 5 — CNI / Pod Networking (Calico VXLAN)

## Purpose
- Enable pod-to-pod networking across nodes (overlay)
- Make nodes Ready and allow CoreDNS to schedule/run
- Foundation for Ingress/Storage/OSDU later

## Why Calico VXLAN (DigitalOcean)
- DigitalOcean Cloud Firewall does not support IP protocol 4 (IPIP), so Calico default IPIP may break.
- VXLAN uses UDP 4789 (firewall-friendly).

## Decisions
- CNI: Calico (manifest-based)
- Encapsulation: VXLAN
- Pod CIDR: (must match kubeadm podSubnet)
- Service CIDR: (from kubeadm)

## Evidence
- artifacts/step5-cni/
  - kubeadm-cidrs.txt
  - calico-apply.txt
  - kube-system-after-cni.txt
  - nodes-after-cni.txt
