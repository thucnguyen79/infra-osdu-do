# Issue: Step 4.3.4 kubeadm validate fails (config file missing on node)

## Symptom
Running on ToolServer01:
- kubeadm config validate --config /opt/infra-osdu-do/k8s/kubeadm/kubeadm-init-ha-v1.30.yaml
Result on ControlPlane01:
- open ...: no such file or directory

## Root cause
The repo path `/opt/infra-osdu-do/...` exists on ToolServer01 only.
ControlPlane01 does not have that file unless we copy (stage) it to the node.

## Fix
Stage the kubeadm config to ControlPlane01 first, then validate using the staged path:
- Copy to: /etc/kubernetes/kubeadm/kubeadm-init-ha-v1.30.yaml
- Validate: kubeadm config validate --config /etc/kubernetes/kubeadm/kubeadm-init-ha-v1.30.yaml

## Prevention (repo-first)
Use an Ansible playbook to:
- create destination directory
- copy config to node
- validate
- save evidence to artifacts
Playbook:
- ansible/playbooks/32-kubeadm-stage-validate.yml

## Evidence
- artifacts/step4-controlplane-endpoint/run-validate.log
- artifacts/step4-controlplane-endpoint/ControlPlane01/kubeadm-validate.txt
