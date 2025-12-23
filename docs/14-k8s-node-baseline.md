# Step 4.1 - Kubernetes Node Baseline (kubeadm prerequisites)

## Scope
Applies to:
- ControlPlane01-03
- WorkerNode01-02

Not applied to:
- AppServer01 (LB)
- ToolServer01 (management/VPN)

## Goals
- Disable swap
- Load kernel modules: overlay, br_netfilter
- sysctl: ip_forward=1, bridge-nf-call-iptables=1
- Install & configure containerd (SystemdCgroup=true)
- Provide evidence logs in artifacts/step4-node-baseline/

## Evidence
- artifacts/step4-node-baseline/run.log
- artifacts/step4-node-baseline/<node>/*


## Do bước này phức tạp nên sẽ ghi chú kỹ:
tep 4.1: “Kubernetes Node Baseline” (chuẩn bị cho kubeadm)

Theo chuẩn nội bộ, runtime containerd là lựa chọn approved/default 

K8s_Ecosystem_Internal_Standard

. Ta sẽ làm baseline cho nhóm k8s_cluster (ControlPlane + Worker) trước (chưa đụng AppServer01 LB).

4.1.0 Mục tiêu Step 4.1

Trên ControlPlane01-03 + WorkerNode01-02:

Tắt swap (kubelet yêu cầu)

Bật kernel modules: overlay, br_netfilter

Set sysctl: net.ipv4.ip_forward=1, bridge-nf-call-iptables=1

Cài & cấu hình containerd (SystemdCgroup=true)

Document đầy đủ + evidence + checklist

4.1.1 Tạo doc + checklist
A) Tạo file doc docs/14-k8s-node-baseline.md
cd /opt/infra-osdu-do

cat > docs/14-k8s-node-baseline.md << 'EOF'
# Step 4.1 - Kubernetes Node Baseline (kubeadm prerequisites)

## Scope
Applies to:
- ControlPlane01-03
- WorkerNode01-02

Not applied to:
- AppServer01 (LB)
- ToolServer01 (management/VPN)

## Goals
- Disable swap
- Load kernel modules: overlay, br_netfilter
- sysctl: ip_forward=1, bridge-nf-call-iptables=1
- Install & configure containerd (SystemdCgroup=true)
- Provide evidence logs in artifacts/step4-node-baseline/

## Evidence
- artifacts/step4-node-baseline/run.log
- artifacts/step4-node-baseline/<node>/*
EOF

B) Thêm Step 4 vào checklist
grep -q "## Step 4" docs/04-deploy-checklist.md || cat >> docs/04-deploy-checklist.md << 'EOF'

## Step 4 - Kubernetes prerequisites (node baseline)
### Step 4.1 Node baseline (CP/Worker)
- [ ] Swap disabled on all CP/Worker
- [ ] Kernel modules overlay, br_netfilter loaded
- [ ] sysctl configured for Kubernetes networking
- [ ] containerd installed & running (SystemdCgroup=true)
- [ ] Evidence stored in artifacts/step4-node-baseline/
EOF

4.1.2 Tạo playbook baseline: ansible/playbooks/20-k8s-node-baseline.yml
cd /opt/infra-osdu-do
mkdir -p artifacts/step4-node-baseline

cat > ansible/playbooks/20-k8s-node-baseline.yml << 'EOF'
---
- name: Step 4.1 - Kubernetes node baseline (kubeadm prerequisites)
  hosts: k8s_cluster
  become: true
  gather_facts: true

  vars:
    outdir: "/opt/infra-osdu-do/artifacts/step4-node-baseline/{{ inventory_hostname }}"
    modules_file: /etc/modules-load.d/k8s.conf
    sysctl_file: /etc/sysctl.d/99-kubernetes-cri.conf
    containerd_cfg: /etc/containerd/config.toml

  tasks:
    - name: Create evidence directory on ToolServer01
      file:
        path: "{{ outdir }}"
        state: directory
        mode: "0755"
      delegate_to: localhost
      become: false

    - name: Install required packages
      apt:
        name:
          - ca-certificates
          - curl
          - gnupg
          - lsb-release
          - apt-transport-https
          - containerd
        state: present
        update_cache: true

    # ---- Swap ----
    - name: Disable swap immediately
      command: swapoff -a
      changed_when: false

    - name: Comment swap entries in /etc/fstab (safe)
      replace:
        path: /etc/fstab
        regexp: '^([^#].*\s+swap\s+.*)$'
        replace: '# \1'

    - name: Capture swap status
      command: sh -c "swapon --show || true"
      register: sw
      changed_when: false

    - name: Save swapon status to artifacts
      copy:
        dest: "{{ outdir }}/swapon.txt"
        content: "{{ sw.stdout }}\n"
      delegate_to: localhost
      become: false

    # ---- Kernel modules ----
    - name: Ensure kernel modules config for Kubernetes
      copy:
        dest: "{{ modules_file }}"
        content: |
          overlay
          br_netfilter
        owner: root
        group: root
        mode: "0644"

    - name: Load overlay module
      modprobe:
        name: overlay
        state: present

    - name: Load br_netfilter module
      modprobe:
        name: br_netfilter
        state: present

    - name: Capture lsmod relevant
      command: sh -c "lsmod | egrep 'overlay|br_netfilter' || true"
      register: lsmod_out
      changed_when: false

    - name: Save lsmod to artifacts
      copy:
        dest: "{{ outdir }}/lsmod.txt"
        content: "{{ lsmod_out.stdout }}\n"
      delegate_to: localhost
      become: false

    # ---- Sysctl ----
    - name: Ensure sysctl params for Kubernetes
      copy:
        dest: "{{ sysctl_file }}"
        content: |
          net.bridge.bridge-nf-call-iptables  = 1
          net.bridge.bridge-nf-call-ip6tables = 1
          net.ipv4.ip_forward                 = 1
        owner: root
        group: root
        mode: "0644"

    - name: Apply sysctl
      command: sysctl --system
      changed_when: false

    - name: Capture sysctl values
      command: sh -c "sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables"
      register: sysctl_out
      changed_when: false

    - name: Save sysctl to artifacts
      copy:
        dest: "{{ outdir }}/sysctl.txt"
        content: "{{ sysctl_out.stdout }}\n"
      delegate_to: localhost
      become: false

    # ---- containerd ----
    - name: Ensure containerd config exists (generate default if missing)
      command: sh -c "test -f {{ containerd_cfg }} || (mkdir -p /etc/containerd && containerd config default > {{ containerd_cfg }})"
      changed_when: false

    - name: Set SystemdCgroup = true in containerd config
      replace:
        path: "{{ containerd_cfg }}"
        regexp: 'SystemdCgroup\s*=\s*false'
        replace: 'SystemdCgroup = true'

    - name: Restart containerd
      systemd:
        name: containerd
        state: restarted
        enabled: true

    - name: Capture containerd status
      command: sh -c "containerd --version && systemctl is-active containerd"
      register: ctd
      changed_when: false

    - name: Save containerd status to artifacts
      copy:
        dest: "{{ outdir }}/containerd.txt"
        content: "{{ ctd.stdout }}\n"
      delegate_to: localhost
      become: false
EOF

4.1.3 Chạy theo “canary” trước rồi rollout (đúng tinh thần safe-change)

Trên ToolServer01:

A) Canary: chỉ ControlPlane01
cd /opt/infra-osdu-do
source .venv/bin/activate
export ANSIBLE_CONFIG=/opt/infra-osdu-do/ansible/ansible.cfg

ansible-playbook ansible/playbooks/20-k8s-node-baseline.yml --limit ControlPlane01


Kiểm tra evidence:

ls -al artifacts/step4-node-baseline/ControlPlane01
cat artifacts/step4-node-baseline/ControlPlane01/swapon.txt
cat artifacts/step4-node-baseline/ControlPlane01/sysctl.txt
cat artifacts/step4-node-baseline/ControlPlane01/containerd.txt

B) Rollout: toàn bộ k8s_cluster
ansible-playbook ansible/playbooks/20-k8s-node-baseline.yml

4.1.4 Ghi log chạy + commit (document đầy đủ)

Tạo run log:

{
  echo "Step 4.1 run log ($(date))"
  ansible-playbook ansible/playbooks/20-k8s-node-baseline.yml
} | tee artifacts/step4-node-baseline/run.log


Tick checklist Step 4.1 (đổi [ ] thành [x] sau khi ok), rồi commit:

git add ansible/playbooks/20-k8s-node-baseline.yml docs/14-k8s-node-baseline.md \
        docs/04-deploy-checklist.md artifacts/step4-node-baseline
git commit -m "Step 4.1: Kubernetes node baseline (swap/sysctl/modules/containerd)"
git push origin main



### Fix modprobe issue in  ansible/ansible.cfg

Chuẩn repo-first thì bạn làm 3 việc: (1) khai báo collection trong ansible/requirements.yml → (2) cài collections vào thư mục trong repo → (3) gọi đúng FQCN community.general.modprobe trong playbook.

Dưới đây là các bước “đúng chuẩn” + lệnh copy/paste chạy luôn.

1) Tạo ansible/requirements.yml

Trong repo /opt/infra-osdu-do:

cat > ansible/requirements.yml <<'EOF'
---
collections:
  - name: community.general
EOF

2) Cài collection vào repo (không cài global)

Tạo thư mục collections và cài:

mkdir -p ansible/collections
ansible-galaxy collection install -r ansible/requirements.yml -p ansible/collections


Kiểm tra:

ansible-galaxy collection list | grep -E 'community\.general'
ls -la ansible/collections/ansible_collections/community/general >/dev/null && echo "OK: installed in repo"

3) Đảm bảo Ansible “nhìn thấy” collections trong repo

Mở ansible/ansible.cfg và thêm/đảm bảo có dòng sau trong [defaults]:

[defaults]
collections_paths = /opt/infra-osdu-do/ansible/collections:~/.ansible/collections:/usr/share/ansible/collections


Vì bạn đang export ANSIBLE_CONFIG=/opt/infra-osdu-do/ansible/ansible.cfg nên chỉ cần cấu hình ở đây là ổn.

4) Sửa playbook: đổi modprobe: thành community.general.modprobe:

Đoạn bạn paste sửa thành:

    - name: Load overlay module
      community.general.modprobe:
        name: overlay
        state: present

    - name: Load br_netfilter module
      community.general.modprobe:
        name: br_netfilter
        state: present


Bạn có thể dùng sed để sửa nhanh (ít sai):

sed -i 's/^\(\s*\)modprobe:/\1community.general.modprobe:/' ansible/playbooks/20-k8s-node-baseline.yml

5) Chạy lại “canary” (1 node trước)
source .venv/bin/activate
export ANSIBLE_CONFIG=/opt/infra-osdu-do/ansible/ansible.cfg
ansible-playbook ansible/playbooks/20-k8s-node-baseline.yml --limit ControlPlane01


Nếu OK rồi mới rollout:

ansible-playbook ansible/playbooks/20-k8s-node-baseline.yml --limit "controlplane:worker"

6) Commit repo-first (để người khác clone chạy y hệt)
git add ansible/requirements.yml ansible/ansible.cfg ansible/playbooks/20-k8s-node-baseline.yml
git commit -m "ansible: add requirements.yml and use community.general.modprobe"
git push

Lưu ý nhỏ

ansible/collections nên được commit hay không?

Thường không commit cả thư mục collections (nặng). Chỉ commit requirements.yml, và khi deploy thì chạy ansible-galaxy collection install ... để pull về.

Bạn có thể thêm .gitignore:

ansible/collections/