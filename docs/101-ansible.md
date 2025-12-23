A) Cài đặt Ansible
Mục đích: Quản lý hạ tầng, user của cụm cluster
A1) Cài Ansible trên ToolServer01
Trên ToolServer01:
sudo apt update
sudo apt install -y ansible
ansible --version

###
Evidence: 
ops@ToolServer01:~$ ansible --version
ansible 2.10.8
  config file = None
  configured module search path = ['/home/ops/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/lib/python3/dist-packages/ansible
  executable location = /usr/bin/ansible
  python version = 3.10.12 (main, Nov  4 2025, 08:48:33) [GCC 11.4.0]


A2) Tạo inventory cho các node (private IP theo bảng của bạn)
Tạo file ~/ansible/hosts.ini:
mkdir -p ~/ansible
cat > ~/ansible/hosts.ini <<'EOF'
[all]
appserver01     ansible_host=10.118.0.8
controlplane01  ansible_host=10.118.0.2
controlplane02  ansible_host=10.118.0.3
controlplane03  ansible_host=10.118.0.4
toolserver01    ansible_host=10.118.0.5
workernode01    ansible_host=10.118.0.6
workernode02    ansible_host=10.118.0.7

[all:vars]
ansible_user=root
EOF

A3) Chuẩn bị SSH public key của AdminPC để gán cho user ops

Trên Windows (AdminPC):
type $env:USERPROFILE\.ssh\id_ed25519.pub
Nếu chưa có thì tạo:
ssh-keygen -t ed25519 -C "adminpc"
type $env:USERPROFILE\.ssh\id_ed25519.pub
Copy nguyên 1 dòng ssh-ed25519 ...

Trên ToolServer01, lưu key vào file:
cat > ~/ansible/ops.pub <<'EOF'
ssh-ed25519 AAAA... adminpc
EOF
A4) Viết playbook tạo user ops
Tạo ~/ansible/bootstrap-ops.yml:
cat > ~/ansible/bootstrap-ops.yml <<'EOF'
- name: Bootstrap ops user on all nodes
  hosts: all
  become: false
  vars:
    ops_user: ops
    ops_pubkey: "{{ lookup('file', playbook_dir + '/ops.pub') }}"
  tasks:
    - name: Ensure ops user exists
      ansible.builtin.user:
        name: "{{ ops_user }}"
        shell: /bin/bash
        create_home: true
        state: present

    - name: Ensure ops is in sudo group
      ansible.builtin.user:
        name: "{{ ops_user }}"
        groups: sudo
        append: true

    - name: Install SSH public key for ops
      ansible.posix.authorized_key:
        user: "{{ ops_user }}"
        key: "{{ ops_pubkey }}"
        state: present

    # (khuyến nghị) Cho ops sudo không cần password để vận hành nhanh
    - name: Allow ops passwordless sudo
      ansible.builtin.copy:
        dest: "/etc/sudoers.d/90-ops-nopasswd"
        content: "ops ALL=(ALL) NOPASSWD:ALL\n"
        owner: root
        group: root
        mode: "0440"
EOF
A5) Test kết nối Ansible trước

Nếu root SSH bằng password
Cài thêm sshpass trên ToolServer01 rồi chạy --ask-pass:
sudo apt install -y sshpass
cd ~/ansible
ansible all -i hosts.ini -m ping --ask-pass

**Nếu chưa có thêm fingerprint của các host***
Pre-add host keys vào known_hosts bằng ssh-keyscan.
Trên ToolServer01 (user ops), chạy:

mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/known_hosts
chmod 600 ~/.ssh/known_hosts

# Quét và add host keys cho toàn bộ node (SSH port 22)
ssh-keyscan -H 10.118.0.2 10.118.0.3 10.118.0.4 10.118.0.5 10.118.0.6 10.118.0.7 10.118.0.8 >> ~/.ssh/

Rồi test lại:
cd ~/ansible
ansible all -i hosts.ini -m ping --ask-pass
***END***


Nếu root SSH bằng SSH key
Chỉ cần:
cd ~/ansible
ansible all -i hosts.ini -m ping

###
Evidence:
ops@ToolServer01:~/ansible$ ansible all -i hosts.ini -m ping --ask-pass
SSH password:
toolserver01 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
controlplane02 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
controlplane03 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
controlplane01 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
appserver01 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
workernode02 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
workernode01 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}


A6) Chạy playbook
cd ~/ansible
ansible-playbook -i hosts.ini bootstrap-ops.yml --ask-pass
# (bỏ --ask-pass nếu bạn dùng SSH key)

###
Evidence:
ops@ToolServer01:~/ansible$ ansible-playbook -i hosts.ini bootstrap-ops.yml --ask-pass
SSH password:

PLAY [Bootstrap ops user on all nodes] ******************************************************************************************************************************************************************************************************

TASK [Gathering Facts] **********************************************************************************************************************************************************************************************************************
ok: [controlplane01]
ok: [controlplane03]
ok: [toolserver01]
ok: [controlplane02]
ok: [appserver01]
ok: [workernode02]
ok: [workernode01]

TASK [Ensure ops user exists] ***************************************************************************************************************************************************************************************************************
changed: [controlplane03]
ok: [toolserver01]
changed: [controlplane01]
changed: [controlplane02]
changed: [appserver01]
changed: [workernode02]
changed: [workernode01]

TASK [Ensure ops is in sudo group] **********************************************************************************************************************************************************************************************************
ok: [toolserver01]
changed: [controlplane03]
changed: [controlplane01]
changed: [appserver01]
changed: [controlplane02]
changed: [workernode01]
changed: [workernode02]

TASK [Install SSH public key for ops] *******************************************************************************************************************************************************************************************************
changed: [controlplane02]
changed: [controlplane01]
changed: [toolserver01]
changed: [controlplane03]
changed: [appserver01]
changed: [workernode02]
changed: [workernode01]

TASK [Allow ops passwordless sudo] **********************************************************************************************************************************************************************************************************
changed: [controlplane02]
changed: [controlplane01]
changed: [controlplane03]
changed: [toolserver01]
changed: [appserver01]
changed: [workernode02]
changed: [workernode01]

PLAY RECAP **********************************************************************************************************************************************************************************************************************************
appserver01                : ok=5    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
controlplane01             : ok=5    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
controlplane02             : ok=5    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
controlplane03             : ok=5    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
toolserver01               : ok=5    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
workernode01               : ok=5    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
workernode02               : ok=5    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0

ops@ToolServer01:~/ansible$



A7) Verify từ Windows
ssh ops@10.118.0.2
ssh ops@10.118.0.8
Lưu ý: playbook trên idempotent (chạy lại không sao).

###
Evidence:
Trên máy Windows, sau khi kết nó6i VPN (dùng WireGuard), kiểm tra kết nối SSH:
C:\Users\Admin\Desktop\oceandigital\.ssh>ssh ops@10.118.0.2
Welcome to Ubuntu 22.04.4 LTS (GNU/Linux 5.15.0-113-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

 System information as of Tue Dec 23 07:54:22 UTC 2025

  System load:  0.02               Processes:             125
  Usage of /:   1.1% of 232.42GB   Users logged in:       0
  Memory usage: 4%                 IPv4 address for eth0: 165.227.45.55
  Swap usage:   0%                 IPv4 address for eth0: 10.20.0.5

Expanded Security Maintenance for Applications is not enabled.

77 updates can be applied immediately.
To see these additional updates run: apt list --upgradable

Enable ESM Apps to receive additional future security updates.
See https://ubuntu.com/esm or run: sudo pro status

New release '24.04.3 LTS' available.
Run 'do-release-upgrade' to upgrade to it.


*** System restart required ***

The programs included with the Ubuntu system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Ubuntu comes with ABSOLUTELY NO WARRANTY, to the extent permitted by
applicable law.

To run a command as administrator (user "root"), use "sudo <command>".
See "man sudo_root" for details.
