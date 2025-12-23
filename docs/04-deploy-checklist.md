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
