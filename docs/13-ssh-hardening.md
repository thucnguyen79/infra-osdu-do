# Step 3.3 - SSH Hardening (Ansible)

## Goal
- Disable password-based SSH authentication (key-only)
- Keep break-glass access: root allowed only by key (PermitRootLogin prohibit-password)
- AllowUsers: ops root
- Use sshd drop-in file for easy rollback

## Implementation approach (safe)
1) Canary apply to ControlPlane01, then test new SSH session from ToolServer01
2) Rollout apply to remaining cluster nodes
3) Apply to ToolServer01 last

## Files
- ansible/playbooks/10-ssh-hardening.yml
- ansible/playbooks/11-ssh-rollback.yml
- /etc/ssh/sshd_config.d/99-osdu-hardening.conf (created on nodes)

## Rollback
- Run playbook: ansible-playbook ansible/playbooks/11-ssh-rollback.yml --limit <host>
- Or manually delete /etc/ssh/sshd_config.d/99-osdu-hardening.conf and reload ssh

## Evidence
- Paste outputs:
  - sshd -t check result (from playbook)
  - SSH new session test after reload
  - ansible-playbook logs (summary)
