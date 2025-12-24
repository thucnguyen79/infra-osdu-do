# Step 4.4 - kubeadm join (ControlPlane02/03 + Worker01/02)

## Goal
- Join remaining control-plane nodes (CP02, CP03) to the HA cluster via k8s-api.internal:6443
- Join worker nodes (Worker01, Worker02)
- Store secrets (token/cert-key) under artifacts-private/ (never commit)
- Store non-secret evidence under artifacts/

## Expected status
- Nodes may remain NotReady until CNI is installed (Step 5)

## Control-plane join trên DO phải dùng --apiserver-advertise-address <private-ip>…” (vì kubeadm nếu không set sẽ chọn default NIC)
