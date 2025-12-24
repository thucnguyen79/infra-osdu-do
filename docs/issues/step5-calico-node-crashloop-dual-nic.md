# Issue: Step 5 - calico-node CrashLoop/NotReady on dual-NIC droplets

## Symptom
- calico-node pods 0/1 or CrashLoopBackOff
- ds/calico-node rollout timed out

## Context
- DigitalOcean droplets have public + VPC interface (eth1 used for cluster private traffic)

## Root cause (likely)
- Calico IP autodetection picked the wrong interface/IP on some nodes.

## Fix
- Set IP_AUTODETECTION_METHOD=interface=eth1 in calico-node DaemonSet
- Re-apply manifest and verify ds rollout success

## Evidence
- artifacts/step5-cni/debug/*
- artifacts/step5-cni/calico-node-after.txt
