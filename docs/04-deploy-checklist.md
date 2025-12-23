# Deployment Checklist (Kubernetes + OSDU on DigitalOcean)

## Step 1 - ToolServer01 base + repo skeleton
- [ ] Hostname/Timezone/NTP OK
- [ ] User ops + sudo OK
- [ ] Repo /opt/infra-osdu-do created (docs/ ansible/ k8s/ osdu/ diagrams/)
- [ ] Inventory base documented (docs/02-inventory.md)

## Step 2 - VPN WireGuard
- [ ] WireGuard installed on ToolServer01
- [ ] wg0 up (10.200.200.1/24)
- [ ] DO Firewall allows UDP 51820 -> ToolServer01
- [ ] AdminPC connected (10.200.200.2)
- [ ] SSH to ControlPlane01 via private eth1 (ops@10.118.0.2) OK

## Step 2.9 - Ansible inventory over private eth1
- [ ] Ansible installed on ToolServer01
- [ ] ansible.cfg created and points to ansible/hosts.ini
- [ ] ansible/hosts.ini uses ONLY 10.118.0.x addresses
- [ ] Ansible ping: ansible all -m ping (SUCCESS)
