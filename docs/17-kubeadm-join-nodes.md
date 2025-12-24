# Step 4.4 - kubeadm join (ControlPlane02/03 + Worker01/02)

## Goal
- Join remaining control-plane nodes (CP02, CP03) to the HA cluster via k8s-api.internal:6443
- Join worker nodes (Worker01, Worker02)
- Store secrets (token/cert-key) under artifacts-private/ (never commit)
- Store non-secret evidence under artifacts/

## Expected status
- Nodes may remain NotReady until CNI is installed (Step 5)

## Control-plane join trên DO phải dùng --apiserver-advertise-address <private-ip>…” (vì kubeadm nếu không set sẽ chọn default NIC)
- “Control-plane join must include --apiserver-advertise-address=<private eth1 IP>
- docs/issues/step4.4-join-cp02-etcd-learner-not-in-sync.md

## Worker join (WorkerNode01/02)
- Workers join using the current join token (stored under artifacts-private/)
- No special advertise-address flag is required for workers in this lab (kubelet node-ip already forced to private in Step 4.2)
