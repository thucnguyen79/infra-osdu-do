# Issue: Step 4.4 join ControlPlane02 fails - etcd learner not in sync

## Symptom
kubeadm join --control-plane stops at etcd join with:
- etcdserver: can only promote a learner member which is in sync with leader

## Context
DigitalOcean droplets have both public + private IP.
Public access to CP/Worker is disabled; cluster communication must use private eth1 (10.118.0.0/20).

## Root cause
kubeadm join on ControlPlane02 auto-selected the default interface (public IP) as advertise address.
Evidence: certificates/manifests referenced public IP (138.x.x.x), causing etcd peer replication to fail (leader cannot sync learner via public network).

## Fix
1) Reset CP02 and remove stale etcd member on CP01
2) Re-join CP02 with:
- kubeadm join ... --control-plane ... --apiserver-advertise-address 10.118.0.3

## Evidence
- artifacts/step4-kubeadm-join/ControlPlane02/etcd-manifest-urls.txt
- artifacts/step4-kubeadm-join/ControlPlane02/public-ip-found.txt
- artifacts-private/step4-kubeadm-join/join-controlplane02*.txt
