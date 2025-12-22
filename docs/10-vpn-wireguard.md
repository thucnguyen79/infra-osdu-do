1) Mục tiêu

Dựng VPN WireGuard trên ToolServer01 để AdminPC truy cập an toàn vào VPC eth1 (10.118.0.0/20).

Sau bước này, các bước tiếp theo sẽ chuyển sang quản trị CP/Worker bằng IP eth1 (10.118.0.x) và dần siết public access.

2) Network plan

VPN subnet (WireGuard): 10.200.200.0/24

WG Server (ToolServer01/wg0): 10.200.200.1

AdminPC: 10.200.200.2

VPC cần truy cập: 10.118.0.0/20 (eth1)

WireGuard port: UDP 51820

Interfaces (theo Configuration.docx):

ToolServer01: eth0 (public), eth1 (VPC 10.118.0.5/20)

Ghi chú: Trên eth0 còn có IP 10.20.0.8/16. Không route dải này qua VPN mặc định (tránh conflict mạng nội bộ).

3) Triển khai trên ToolServer01
3.1 Cài đặt WireGuard

Mục đích: cài dịch vụ VPN và iptables để NAT/forward.

sudo apt update
sudo apt install -y wireguard iptables
wg --version


Evidence cần lưu: output wg --version

3.2 Bật IPv4 forwarding

Mục đích: cho phép route traffic từ wg0 → eth1 (VPC).

echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-wireguard.conf
sudo sysctl --system
sysctl net.ipv4.ip_forward


AC: net.ipv4.ip_forward = 1
Evidence: output sysctl net.ipv4.ip_forward

3.3 Xác nhận interface & IP (đối chiếu Configuration.docx)
ip -br a
ip route | head -n 30


AC: thấy eth1 có 10.118.0.5/20, eth0 có public IP.

Evidence: dán output 2 lệnh vào cuối file mục “Evidence”.

3.4 Tạo keypair cho WireGuard server
sudo -i
umask 077
wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
exit
sudo cat /etc/wireguard/server.pub


AC: có /etc/wireguard/server.key và /etc/wireguard/server.pub
Document: chỉ ghi server.pub, không ghi server.key.

3.5 Tạo cấu hình /etc/wireguard/wg0.conf

Mục đích: dựng interface wg0 và NAT sang VPC 10.118.0.0/20 qua eth1.

SERVER_KEY="$(sudo cat /etc/wireguard/server.key)"

sudo tee /etc/wireguard/wg0.conf > /dev/null << EOF
[Interface]
Address = 10.200.200.1/24
ListenPort = 51820
PrivateKey = $SERVER_KEY

# Forward VPN traffic to VPC (eth1: 10.118.0.0/20)
PostUp   = iptables -A FORWARD -i wg0 -d 10.118.0.0/20 -j ACCEPT; iptables -A FORWARD -o wg0 -s 10.118.0.0/20 -j ACCEPT; iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -d 10.118.0.0/20 -o eth1 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -d 10.118.0.0/20 -j ACCEPT; iptables -D FORWARD -o wg0 -s 10.118.0.0/20 -j ACCEPT; iptables -t nat -D POSTROUTING -s 10.200.200.0/24 -d 10.118.0.0/20 -o eth1 -j MASQUERADE
EOF

sudo chmod 600 /etc/wireguard/wg0.conf


AC: file tồn tại, permission 600.

Document (bản che key để lưu vào doc):

sudo sed 's/^PrivateKey.*/PrivateKey = ***REDACTED***/' /etc/wireguard/wg0.conf

3.6 Mở port VPN trên firewall (DigitalOcean + UFW nếu dùng)

DigitalOcean Firewall (bắt buộc):

Inbound: UDP 51820 → ToolServer01 (source: IP văn phòng/nhà anh hoặc tạm 0.0.0.0/0 cho POC)

Nếu UFW đang active:

sudo ufw status
sudo ufw allow 51820/udp


Phần rule này phải ghi vào docs/11-firewall-do.md.

3.7 Start WireGuard
sudo systemctl enable --now wg-quick@wg0
sudo systemctl status wg-quick@wg0 --no-pager | sed -n '1,25p'
sudo wg show
ip a show wg0


AC: wg0 có IP 10.200.200.1/24, service running.

4) Tạo client profile cho AdminPC
4.1 Generate keypair cho AdminPC (trên ToolServer01)
sudo -i
umask 077
wg genkey | tee /etc/wireguard/adminpc.key | wg pubkey > /etc/wireguard/adminpc.pub
exit
sudo cat /etc/wireguard/adminpc.pub


Document: chỉ ghi adminpc.pub (không ghi adminpc.key)

4.2 Add peer vào server
CLIENT_PUB="$(sudo cat /etc/wireguard/adminpc.pub)"
sudo wg set wg0 peer "$CLIENT_PUB" allowed-ips 10.200.200.2/32
sudo wg-quick save wg0
sudo wg show


AC: wg show thấy peer AllowedIPs 10.200.200.2/32

4.3 Tạo adminpc.conf để copy về máy anh
SERVER_PUB="$(sudo cat /etc/wireguard/server.pub)"
CLIENT_KEY="$(sudo cat /etc/wireguard/adminpc.key)"

cat > ~/adminpc.conf << EOF
[Interface]
PrivateKey = $CLIENT_KEY
Address = 10.200.200.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = 147.182.146.253:51820
AllowedIPs = 10.200.200.0/24, 10.118.0.0/20
PersistentKeepalive = 25
EOF

chmod 600 ~/adminpc.conf


Quan trọng: adminpc.conf chứa private key ⇒ KHÔNG commit.
Trong tài liệu chỉ lưu bản che key:

sed 's/^PrivateKey.*/PrivateKey = ***REDACTED***/' ~/adminpc.conf

4.4 Copy về AdminPC

Từ máy anh:

scp ops@147.182.146.253:/home/ops/adminpc.conf .

5) Kết nối VPN từ AdminPC & kiểm tra
5.1 Kết nối

Windows/macOS: WireGuard app → Import tunnel → Activate

Linux: sudo wg-quick up ./adminpc.conf

5.2 Test (bắt buộc)
ping 10.200.200.1
ping 10.118.0.5
ssh ops@10.118.0.2   # ControlPlane01 eth1


AC: ping OK, SSH private OK.

6) Evidence (dán output để audit/đối chiếu)

Dán các output sau (nguyên văn) vào cuối file:

ToolServer01

ip -br a
ip route | head -n 30
sudo wg show
sudo systemctl status wg-quick@wg0 --no-pager | sed -n '1,25p'


AdminPC

Kết quả ping 10.200.200.1

Kết quả ping 10.118.0.5

SSH ops@10.118.0.2 thành công (ghi timestamp)