# Step 2.9+ - Repo-first Ansible Setup
2.9.1 Goal, struture strategy
## Goal
- Run Ansible from /opt/infra-osdu-do
- Use ONLY private eth1 (10.118.0.0/20)
- Keep legacy bootstrap playbook but managed in repo

## Repo structure
- ansible/ansible.cfg
- ansible/hosts.ini (ops, private IPs)
- ansible/playbooks/bootstrap-ops.yml
- ansible/files/ops_ansible.pub (public key for ToolServer01)
- ansible/files/ops_adminpc.pub (public key for Admin PC)
- ansible/legacy/* (old files for reference)

## SSH key strategy
- Private key stays on ToolServer01: ~/.ssh/id_ed25519_ansible (DO NOT COMMIT)
- Public key is committed: ansible/files/ops_ansible.pub
- One-time distribution of ops_ansible.pub to all nodes

2.9.2 (Tool) Cài Ansible trên ToolServer01 (khuyến nghị dùng Python venv)
Mục đích: Cài Ansible “sạch”, dễ quản lý version, không làm bẩn system Python.
Trên ToolServer01:
sudo apt update
sudo apt install -y python3-venv python3-pip openssh-client sshpass
Tạo venv ngay trong repo:
cd /opt/infra-osdu-do
python3 -m venv .venv
source .venv/bin/activate

pip install --upgrade pip
pip install ansible-core

ansible --version
✅ AC: ansible --version chạy được.
Document cần ghi
•	File: docs/12-ansible-inventory.md (tạo ở bước 2.9.5)
•	Ghi lại:
o	ansible --version
o	đường dẫn venv: /opt/infra-osdu-do/.venv
________________________________________
2.9.3 (Config) Tạo ansible/ansible.cfg
Mục đích: Mọi lệnh ansible chạy chuẩn mà không phải gõ -i mỗi lần, default user ops, giảm hỏi host key trong POC.
Tạo file:
cd /opt/infra-osdu-do

cat > ansible/ansible.cfg << 'EOF'
[defaults]
inventory = ./ansible/hosts.ini
remote_user = ops
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
interpreter_python = auto_silent
forks = 20
timeout = 30

[ssh_connection]
pipelining = True
EOF
✅ AC: file tồn tại, nội dung đúng.
Lưu ý bảo mật
•	host_key_checking = False phù hợp POC/triển khai nhanh. Khi lên UAT/Prod sẽ bật lại.
________________________________________
2.9.4 (Inventory) Chuẩn hóa ansible/hosts.ini dùng IP eth1 (10.118.0.x)
Mục đích: Mọi node được quản trị qua private eth1.
Ghi đè file ansible/hosts.ini theo IP đã cung cấp:
cd /opt/infra-osdu-do

cat > ansible/hosts.ini << 'EOF'
[lb]
AppServer01 ansible_host=10.118.0.8

[tool]
ToolServer01 ansible_host=10.118.0.5

[controlplane]
ControlPlane01 ansible_host=10.118.0.2
ControlPlane02 ansible_host=10.118.0.3
ControlPlane03 ansible_host=10.118.0.4

[worker]
WorkerNode01 ansible_host=10.118.0.6
WorkerNode02 ansible_host=10.118.0.7

[all:vars]
ansible_user=ops
ansible_python_interpreter=/usr/bin/python3
EOF
✅ AC: Không còn IP public trong inventory; chỉ 10.118.0.x.
________________________________________
2.9.5 (Test) Kiểm tra SSH private từ ToolServer01 → các node
Dù AdminPC SSH được qua VPN, Ansible sẽ chạy trên ToolServer01 nên cần đảm bảo ToolServer01 SSH qua eth1 được.
2.9.5.1 Test SSH manual nhanh
Trên ToolServer01:
ssh -o StrictHostKeyChecking=no ops@10.118.0.2 "hostname; ip -br a | head -n 5"
✅ AC: ra hostname ControlPlane01 và thấy eth1 10.118.0.2/20.
2.9.5.2 Test Ansible ping
Trên ToolServer01 (đang activate venv):
cd /opt/infra-osdu-do
source .venv/bin/activate

ANSIBLE_CONFIG=ansible/ansible.cfg ansible all -m ping
✅ AC: tất cả host SUCCESS => {"ping": "pong"}
Nếu muốn test thêm:
ANSIBLE_CONFIG=ansible/ansible.cfg ansible all -a "hostname"
ANSIBLE_CONFIG=ansible/ansible.cfg ansible all -a "ip -br a"


## Evidence
### Inventory
(paste) ansible/hosts.ini
ops@ToolServer01:/opt/infra-osdu-do$ cat ansible/hosts.ini
[tool]
ToolServer01 ansible_host=10.118.0.5

[lb]
AppServer01 ansible_host=10.118.0.8

[controlplane]
ControlPlane01 ansible_host=10.118.0.2
ControlPlane02 ansible_host=10.118.0.3
ControlPlane03 ansible_host=10.118.0.4

[worker]
WorkerNode01 ansible_host=10.118.0.6
WorkerNode02 ansible_host=10.118.0.7

[k8s_cluster:children]
controlplane
worker

[all:vars]
ansible_user=ops
ansible_python_interpreter=/usr/bin/python3


### Ansible config
(paste) ansible/ansible.cfg

ops@ToolServer01:/opt/infra-osdu-do$ cat ansible/ansible.cfg
[defaults]
private_key_file = /home/ops/.ssh/id_ed25519_ansible
inventory = ./hosts.ini
remote_user = ops
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
interpreter_python = auto_silent
forks = 20
timeout = 30

[ssh_connection]
pipelining = True


### Ping all nodes
Command:
ANSIBLE_CONFIG=ansible/ansible.cfg ansible all -m ping
Result:
(paste output)
ops@ToolServer01:/opt/infra-osdu-do$ ANSIBLE_CONFIG=ansible/ansible.cfg ansible all -m ping
ToolServer01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
WorkerNode02 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
ControlPlane03 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
ControlPlane02 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
ControlPlane01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
WorkerNode01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
AppServer01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}


## Fix: inventory path in ansible.cfg
Issue:
- Ansible tried to load: /opt/infra-osdu-do/ansible/ansible/hosts.ini (wrong path)

Root cause:
- ansible.cfg is located under ansible/
- inventory was set to ./ansible/hosts.ini, so it became ansible/ansible/hosts.ini

Fix:
- Set inventory = ./hosts.ini (relative to ansible.cfg)
or
- Set inventory = /opt/infra-osdu-do/ansible/hosts.ini (absolute)

Evidence:
- (paste) ANSIBLE_CONFIG=/opt/infra-osdu-do/ansible/ansible.cfg ansible --version
- (paste) ANSIBLE_CONFIG=/opt/infra-osdu-do/ansible/ansible.cfg ansible all -m ping



*** Để khỏi quên cho các lệnh về sau (khuyến nghị)

Để khỏi phải gõ ANSIBLE_CONFIG=... mỗi lần, ta có thể export môi trường khi làm việc:

cd /opt/infra-osdu-do
source .venv/bin/activate
export ANSIBLE_CONFIG=/opt/infra-osdu-do/ansible/ansible.cfg


Sau đó chạy gọn:

ansible all -m ping
## Evidence - Ansible working (Tue Dec 23 16:53:38 +07 2025)

### ansible --version
ansible [core 2.17.14]
  config file = /opt/infra-osdu-do/ansible/ansible.cfg
  configured module search path = ['/home/ops/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /opt/infra-osdu-do/.venv/lib/python3.10/site-packages/ansible
  ansible collection location = /home/ops/.ansible/collections:/usr/share/ansible/collections
  executable location = /opt/infra-osdu-do/.venv/bin/ansible
  python version = 3.10.12 (main, Nov  4 2025, 08:48:33) [GCC 11.4.0] (/opt/infra-osdu-do/.venv/bin/python3)
  jinja version = 3.1.6
  libyaml = True

### ansible all -m ping
ToolServer01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
WorkerNode02 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
ControlPlane01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
ControlPlane03 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
ControlPlane02 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
WorkerNode01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
AppServer01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
