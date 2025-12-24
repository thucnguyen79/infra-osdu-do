# Deployment Checklist (Kubernetes + OSDU on DigitalOcean)

## Step 1 - ToolServer01 base + repo skeleton
- [x] Hostname/Timezone/NTP OK
- [x] User ops + sudo OK
- [x] Repo /opt/infra-osdu-do created (docs/ ansible/ k8s/ osdu/ diagrams/)
- [x] Inventory base documented (docs/02-inventory.md)

## Step 2 - VPN WireGuard
- [x] WireGuard installed on ToolServer01
- [x] wg0 up (10.200.200.1/24)
- [x] DO Firewall allows UDP 51820 -> ToolServer01
- [x] AdminPC connected (10.200.200.2)
- [x] SSH to ControlPlane01 via private eth1 (ops@10.118.0.2) OK

## Step 2.9 - Ansible inventory over private eth1
- [x] Ansible installed on ToolServer01
- [x] ansible.cfg created and points to ansible/hosts.ini
- [x] ansible/hosts.ini uses ONLY 10.118.0.x addresses
- [x] Ansible ping: ansible all -m ping (SUCCESS)

## Step 3 - Security baseline (Firewall/SSH)
### Step 3.1 DigitalOcean Firewall
- [x] FW-TOOLSERVER01 created and applied
- [x] FW-CLUSTER-NODES created and applied
- [x] Public SSH to CP/Worker/AppServer01 blocked
- [x] Private SSH via VPN/VPC works (ssh ops@10.118.0.2 OK)
- [x] Evidence stored in artifacts/step3-firewall/

### Step 3.3 SSH hardening (key-only)
- [x] Canary: apply hardening to ControlPlane01
- [x] Verify: new SSH session ops@10.118.0.2 works
- [x] Rollout: apply hardening to CP/Worker/AppServer01
- [x] Verify: ansible ping all OK after hardening
- [x] Apply hardening to ToolServer01 last
- [x] Evidence stored in artifacts/step3-ssh-hardening/

## Step 4 - Kubernetes prerequisites (node baseline)
### Step 4.1 Node baseline (CP/Worker)
- [x] Swap disabled on all CP/Worker
- [x] Kernel modules overlay, br_netfilter loaded
- [x] sysctl configured for Kubernetes networking
- [x] containerd installed & running (SystemdCgroup=true)
- [x] Evidence stored in artifacts/step4-node-baseline/
- [x] kubeadm/kubelet/kubectl installed on CP/Worker
- [x] Packages held: apt-mark hold kubelet kubeadm kubectl
- [x] kubelet node-ip forced to private eth1 (10.118.0.0/20) via /etc/default/kubelet
- [x] Canary run OK (artifacts/step4-k8s-packages/run-canary*.log)
- [x] Evidence saved per node: artifacts/step4-k8s-packages/<node>/k8s-packages.txt
- [x] Issue documented (if occurred): docs/issues/step4.2-pipefail-dash.md
- [x] Doc updated: docs/15-k8s-packages.md

### Step 4.3 - HA Control Plane endpoint (Self-managed LB on AppServer01)
#### Step 4.3.1 - Update DO Firewall for internal VPC control-plane traffic
- [x] FW-CLUSTER-NODES inbound allows VPC CIDR 10.118.0.0/20:
  - [x] TCP 6443 (Kubernetes API)
  - [x] TCP 2379-2380 (etcd stacked)
  - [x] TCP 10250 (kubelet API)
- [x] Evidence screenshots stored: artifacts/step4-controlplane-endpoint/screenshots/

#### Step 4.3.2 - Deploy API LoadBalancer on AppServer01 (HAProxy)
- [x] HAProxy installed & enabled on AppServer01
- [x] HAProxy listens on 10.118.0.8:6443
- [x] Backend targets configured: 10.118.0.2/3/4:6443
- [x] Evidence saved: artifacts/step4-controlplane-endpoint/AppServer01/haproxy.txt
- [x] Run log saved: artifacts/step4-controlplane-endpoint/run-lb.log
- [x] Ansible playbook committed: ansible/playbooks/30-apiserver-lb.yml

#### Step 4.3.3 - Standardize controlPlaneEndpoint name (hosts entry)
- [x] /etc/hosts updated on ToolServer01 + all k8s nodes:
  - [x] 10.118.0.8 k8s-api.internal
- [x] Verification OK: getent hosts k8s-api.internal (on k8s_cluster)
- [x] Run log saved: artifacts/step4-controlplane-endpoint/run-hosts.log
- [x] Ansible playbook committed: ansible/playbooks/31-hosts-k8s-api.yml

#### Step 4.3.4 - Create/Stage/Validate kubeadm HA config
- [x] kubeadm HA config created in repo: k8s/kubeadm/kubeadm-init-ha-v1.30.yaml
- [x] Config staged to ControlPlane01: /etc/kubernetes/kubeadm/kubeadm-init-ha-v1.30.yaml
- [x] kubeadm config validate PASS on ControlPlane01
- [x] Evidence saved:
  - [x] artifacts/step4-controlplane-endpoint/ControlPlane01/kubeadm-validate.txt
  - [x] artifacts/step4-controlplane-endpoint/run-validate.log
- [x] Issue documented (if occurred): docs/issues/step4.3-kubeadm-validate-file-missing.md
- [x] Ansible playbook committed: ansible/playbooks/32-kubeadm-stage-validate.yml
- [x] Doc updated: docs/16-ha-controlplane-endpoint.md


### Step 4.3.5 kubeadm init (HA endpoint)
- [x] artifacts-private/ created and gitignored (tokens/certs)
- [x] kubeadm init completed on ControlPlane01 (using controlPlaneEndpoint)
- [x] kubeconfig configured (CP01 + ToolServer01)
- [x] kubectl get nodes works from ToolServer01
- [x] Non-secret evidence saved under artifacts/step4-controlplane-endpoint/
