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
