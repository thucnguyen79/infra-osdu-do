# Step 4.2 - Install Kubernetes packages (kubeadm/kubelet/kubectl)

## 1. Purpose
Step 4.2 standardizes Kubernetes packages on all Control Plane and Worker nodes:
- Install `kubeadm`, `kubelet`, `kubectl` from official Kubernetes repo (`pkgs.k8s.io`)
- Pin node registration to the **private eth1** network by forcing kubelet:
  - `--node-ip=<private_ip>` (10.118.0.0/20)
- Hold packages to prevent unexpected upgrades:
  - `apt-mark hold kubelet kubeadm kubectl`

## 2. Scope
**Targets**
- ControlPlane01, ControlPlane02, ControlPlane03
- WorkerNode01, WorkerNode02

**Excluded**
- ToolServer01 (management/VPN)
- AppServer01 (LB/edge)

## 3. Preconditions
- Step 2 VPN + Step 2.9 Ansible inventory over eth1 completed
- Step 3.1 DigitalOcean Firewall applied (no public SSH to CP/Worker/App)
- Step 4.1 Node baseline completed:
  - swap disabled
  - kernel modules `overlay`, `br_netfilter`
  - sysctl applied
  - containerd installed and running

## 4. Design decisions
### 4.1 Why force kubelet node-ip to private eth1?
These droplets have multiple interfaces (public eth0 + VPC eth1).  
Kubernetes should run on private network for:
- consistent control-plane/worker communication
- predictable advertise/join addresses
- avoiding public routing for cluster traffic

Implementation:
- inventory uses `ansible_host=10.118.0.x`
- kubelet uses:
  - `KUBELET_EXTRA_ARGS=--node-ip={{ ansible_host }}`
  - written to `/etc/default/kubelet`

### 4.2 Repository source for Kubernetes packages
- Use `pkgs.k8s.io` stable channel per minor version:
  - `https://pkgs.k8s.io/core:/stable:/v<minor>/deb/`
- `k8s_minor` is controlled in playbook:
  - `ansible/playbooks/21-k8s-packages.yml`

## 5. Implementation (repo-first)
### 5.1 Files in repo
- Playbook:
  - `ansible/playbooks/21-k8s-packages.yml`
- Evidence:
  - `artifacts/step4-k8s-packages/run-canary.log`
  - `artifacts/step4-k8s-packages/run.log`
  - `artifacts/step4-k8s-packages/<node>/k8s-packages.txt`
- Issue log (if any):
  - `docs/issues/step4.2-pipefail-dash.md`

### 5.2 Playbook summary
The playbook performs:
1) Install prerequisite packages (curl/gpg/keyrings)
2) Add Kubernetes repo + import repo key
3) Install `kubelet/kubeadm/kubectl`
4) Hold versions
5) Force kubelet node-ip to private address
6) Restart kubelet
7) Collect evidence per node

## 6. Execution procedure
### 6.1 Canary (ControlPlane01)
Run from ToolServer01:
```bash
cd /opt/infra-osdu-do
source .venv/bin/activate
export ANSIBLE_CONFIG=/opt/infra-osdu-do/ansible/ansible.cfg

ansible-playbook ansible/playbooks/21-k8s-packages.yml -l ControlPlane01 \
  | tee artifacts/step4-k8s-packages/run-canary.log


### Chu thich chi tiet
Verify evidence:

sed -n '1,120p' artifacts/step4-k8s-packages/ControlPlane01/k8s-packages.txt


Expected:

kubeadm version prints a version in selected minor stream

kubelet --version and kubectl version --client succeed

apt-mark showhold includes kubelet/kubeadm/kubectl

kubelet service is active (it may report “waiting for cluster” until kubeadm init/join)

6.2 Rollout (all k8s nodes)
ansible-playbook ansible/playbooks/21-k8s-packages.yml \
  | tee artifacts/step4-k8s-packages/run.log

7. Verification checklist
7.1 On each node

Kubernetes packages installed:

kubeadm version -o short

kubelet --version

kubectl version --client --short

Hold enabled:

apt-mark showhold | egrep 'kubelet|kubeadm|kubectl'

Kubelet uses private node ip:

/etc/default/kubelet contains: --node-ip=10.118.0.x

Evidence captured:

artifacts/step4-k8s-packages/<node>/k8s-packages.txt

7.2 Repo evidence

docs/04-deploy-checklist.md Step 4.2 ticked after successful rollout

Git commit created for Step 4.2

8. Rollback / re-run notes

Re-running playbook is safe (idempotent) for most tasks.

If you need to unhold packages:

sudo apt-mark unhold kubelet kubeadm kubectl

If kubelet fails to start:

check systemctl status kubelet -l --no-pager

verify containerd is active

verify /etc/default/kubelet syntax is correct

9. Known issues
9.1 /bin/sh (dash) does not support set -o pipefail

Symptom:

task “Install Kubernetes apt key (pkgs.k8s.io)” fails with:

/bin/sh: 1: set: Illegal option -o pipefail

Root cause:

Ansible shell uses /bin/sh by default (dash on Ubuntu)

dash does not support pipefail

Fix:

Force bash in that task:

args: executable: /bin/bash

Reference:

docs/issues/step4.2-pipefail-dash.md

