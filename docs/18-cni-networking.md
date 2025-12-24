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

## Troubleshoot/Dual NIC

 - Symptom: calico-node 0/1, CrashLoopBackOff
 - Root cause: autodetect chọn sai NIC (DO dual NIC)
 - Fix: IP_AUTODETECTION_METHOD=interface=eth1
 - refer to: https://docs.tigera.io/calico/latest/networking/ipam/ip-autodetection?utm_source=chatgpt.com

### Step 5 - CNI (Calico) - Issue: calico-node CrashLoopBackOff
- Symptom: calico-node pods CrashLoopBackOff on all nodes after applying calico manifest
- Hypothesis:
  - Wrong IP autodetection method (e.g., interface name mismatch), or
  - Host firewall blocks VXLAN UDP 4789, or
  - Other calico-node runtime error
- Evidence:
  - artifacts/step5-cni/calico-node-after.txt
  - (add) `kubectl -n kube-system get ds calico-node -o yaml | grep -n IP_AUTODETECTION_METHOD`
  - (add) `kubectl -n kube-system logs <pod> -c calico-node --tail=200`
- Fix plan:
  - Prefer `IP_AUTODETECTION_METHOD=kubernetes-internal-ip` (align with kubelet --node-ip private)
  - Re-apply manifest and re-check rollout

### Issue calico-node CrashLoopBackOff
- Evidence files:
   - artifacts/step5-cni/diagnose/describe-sample-pod.txt
   - artifacts/step5-cni/diagnose/logs-calico-node-previous.txt
   - artifacts/step5-cni/diagnose/ds-calico-node.yaml
- Root cause (sau khi bạn confirm từ describe): liveness probe fail (thường bird-live)
- Fix: remove bird probe args (VXLAN/no-BGP) hoặc mở BGP port 179 (BGP mode). Trường hợp này là: sử trong file k8s/cni/calico/calico-v3.31.3.yaml
   - livenessProbe của container calico-node:
     - từ -felix-live + -bird-live -> thành chỉ -felix-live
   - readinessProbe:
     - từ -felix-ready + -bird-ready -> thành chỉ -felix-ready
