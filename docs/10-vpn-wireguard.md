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
VPC_IF=eth1

###
Evidence:
ops@ToolServer01:~$ ip -br a
lo               UNKNOWN        127.0.0.1/8 ::1/128
eth0             UP             147.182.146.253/20 10.20.0.8/16 fe80::1468:42ff:fec7:8c83/64
eth1             UP             10.118.0.5/20 fe80::3c18:aaff:fe36:ccd1/64


3) Triển khai trên ToolServer01
3.1 Cài đặt WireGuard

Mục đích: cài dịch vụ VPN và iptables để NAT/forward.

sudo apt update
sudo apt install -y wireguard iptables
wg --version

###
Evidence cần lưu: output wg --version
ops@ToolServer01:~$ wg --version
wireguard-tools v1.0.20210914 - https://git.zx2c4.com/wireguard-tools/
ops@ToolServer01:~$ date
Tue Dec 23 11:12:48 +07 2025

3.2 Bật IPv4 forwarding

Mục đích: cho phép route traffic từ wg0 → eth1 (VPC).

echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-wireguard.conf
sudo sysctl --system
sysctl net.ipv4.ip_forward
AC: net.ipv4.ip_forward = 1

###
Evidence: output sysctl net.ipv4.ip_forward
ops@ToolServer01:~$ sysctl net.ipv4.ip_forward
net.ipv4.ip_forward = 1


3.3 Xác nhận interface & IP (đối chiếu Configuration.docx)
ip -br a
ip route | head -n 30


AC: thấy eth1 có 10.118.0.5/20, eth0 có public IP.

###
Evidence: dán output 2 lệnh vào cuối file mục “Evidence”.
ops@ToolServer01:~$ ip -br a
lo               UNKNOWN        127.0.0.1/8 ::1/128
eth0             UP             147.182.146.253/20 10.20.0.8/16 fe80::1468:42ff:fec7:8c83/64
eth1             UP             10.118.0.5/20 fe80::3c18:aaff:fe36:ccd1/64
ops@ToolServer01:~$ ip route | head -n 30
default via 147.182.144.1 dev eth0 proto static
10.20.0.0/16 dev eth0 proto kernel scope link src 10.20.0.8
10.118.0.0/20 dev eth1 proto kernel scope link src 10.118.0.5
147.182.144.0/20 dev eth0 proto kernel scope link src 147.182.146.253

3.4 Tạo keypair cho WireGuard server
sudo -i
umask 077
wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
exit
sudo cat /etc/wireguard/server.pub


AC: có /etc/wireguard/server.key và /etc/wireguard/server.pub
Document: chỉ nên ghi server.pub, không ghi server.key.

###
Evidence: 

ops@ToolServer01:~$ sudo ls /etc/wireguard/ | grep server.*
server.key
server.pub
ops@ToolServer01:~$ sudo cat /etc/wireguard/server.pub
HeNep2YOAfLYsE//D6iojN8peBZAy0AEDUQPYXp6cn4=
ops@ToolServer01:~$ sudo cat /etc/wireguard/server.key
yBtcWYwVLzi++KyxxTVHWTaVifmCxpp0CWJueggePEU=


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

###
Evidence

ops@ToolServer01:~$ sudo ls -al /etc/wireguard/ | grep wg0.*
-rw-------  1 root root  587 Dec 23 11:27 wg0.conf
ops@ToolServer01:~$ sudo sed 's/^PrivateKey.*/PrivateKey = ***REDACTED***/' /etc/wireguard/wg0.conf
[Interface]
Address = 10.200.200.1/24
ListenPort = 51820
PrivateKey = ***REDACTED***

# Forward VPN traffic to VPC (eth1: 10.118.0.0/20)
PostUp   = iptables -A FORWARD -i wg0 -d 10.118.0.0/20 -j ACCEPT; iptables -A FORWARD -o wg0 -s 10.118.0.0/20 -j ACCEPT; iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -d 10.118.0.0/20 -o eth1 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -d 10.118.0.0/20 -j ACCEPT; iptables -D FORWARD -o wg0 -s 10.118.0.0/20 -j ACCEPT; iptables -t nat -D POSTROUTING -s 10.200.200.0/24 -d 10.118.0.0/20 -o eth1 -j MASQUERADE

3.6 Mở port VPN trên firewall (DigitalOcean + UFW nếu dùng)

DigitalOcean Firewall (bắt buộc):

Inbound: UDP 51820 → ToolServer01 (source: IP văn phòng/nhà anh hoặc tạm 0.0.0.0/0 cho POC)

3.6.1 Thực hiện trên Panel của DigitalOcean
A) Xác định “Source CIDR” (IP văn phòng/nhà)
Ở mạng văn phòng/nhà (đúng nơi bạn sẽ kết nối VPN), chạy:
curl -4 ifconfig.me
Ví dụ ra 1.2.3.4 → Source CIDR nên dùng: 1.2.3.4/32 (chỉ 1 IP).
Nếu văn phòng bạn có dải IP public (CIDR) do ISP cấp thì dùng đúng CIDR đó.
( Văn phòng ESS: IP là 14.161.30.130)
B) Vào DO Console để tạo/chỉnh Firewall
DigitalOcean Console → Networking → Firewalls
Chọn firewall hiện có đang gắn với ToolServer01, hoặc tạo mới (Create Firewall). DigitalOcean cho phép tạo/chỉnh inbound/outbound rule theo port/protocol và source/destination. 

Tài liệu DigitalOcean
Ở mục Inbound Rules → New rule
Type/Protocol: UDP
Port: 51820 (WireGuard default) 
DigitalOcean
Sources: chọn IP Address / CIDR → nhập x.x.x.x/32 (khuyến nghị), không nên để 0.0.0.0/0 nếu bạn biết IP nguồn.
Ở mục Apply to Droplets / Droplets: chọn ToolServer01 (đúng droplet nhận VPN)
Save / Apply


Lưu ý: nhớ giữ rule SSH (TCP 22) theo IP của bạn để tránh tự khóa đường SSH nếu firewall này đang “deny by default”.

###
Evidence:
Firewall: VPCFirewall01 trên DigitalOcean Networking Firewall

3.6.2. Thực hiện trên ToolServer01
Kiểm tra trên máy ToolServer01
sudo ufw status verbose
Nếu Status: active thì mở đúng UDP 51820 (khuyến nghị giới hạn theo IP nguồn giống DO Firewall):
Cho phép từ IP văn phòng/nhà:
sudo ufw allow from x.x.x.x/32 to any port 51820 proto udp
Hoặc tạm thời mở mọi IP (ít khuyến nghị):
sudo ufw allow 51820/udp
(UFW cho phép mở port theo allow <port>/<proto> như trên. DigitalOcean)

Kiểm tra lại:
sudo ufw status numbered

###
Evidence:
Do ToolServer01 không active firewall nên không setup rule thêm

3.7 Start WireGuard
sudo systemctl enable --now wg-quick@wg0
sudo systemctl status wg-quick@wg0 --no-pager | sed -n '1,25p'
sudo wg show
ip a show wg0


AC: wg0 có IP 10.200.200.1/24, service running.

###
Evidence:
ops@ToolServer01:~$ sudo systemctl enable --now wg-quick@wg0
Created symlink /etc/systemd/system/multi-user.target.wants/wg-quick@wg0.service → /lib/systemd/system/wg-quick@.service.
ops@ToolServer01:~$ sudo systemctl status wg-quick@wg0 --no-pager | sed -n '1,25p'
● wg-quick@wg0.service - WireGuard via wg-quick(8) for wg0
     Loaded: loaded (/lib/systemd/system/wg-quick@.service; enabled; vendor preset: enabled)
     Active: active (exited) since Tue 2025-12-23 13:20:50 +07; 12s ago
       Docs: man:wg-quick(8)
             man:wg(8)
             https://www.wireguard.com/
             https://www.wireguard.com/quickstart/
             https://git.zx2c4.com/wireguard-tools/about/src/man/wg-quick.8
             https://git.zx2c4.com/wireguard-tools/about/src/man/wg.8
    Process: 48768 ExecStart=/usr/bin/wg-quick up wg0 (code=exited, status=0/SUCCESS)
   Main PID: 48768 (code=exited, status=0/SUCCESS)
        CPU: 37ms

Dec 23 13:20:50 ToolServer01 systemd[1]: Starting WireGuard via wg-quick(8) for wg0...
Dec 23 13:20:50 ToolServer01 wg-quick[48768]: [#] ip link add wg0 type wireguard
Dec 23 13:20:50 ToolServer01 wg-quick[48768]: [#] wg setconf wg0 /dev/fd/63
Dec 23 13:20:50 ToolServer01 wg-quick[48768]: [#] ip -4 address add 10.200.200.1/24 dev wg0
Dec 23 13:20:50 ToolServer01 wg-quick[48768]: [#] ip link set mtu 1420 up dev wg0
Dec 23 13:20:50 ToolServer01 wg-quick[48768]: [#] iptables -A FORWARD -i wg0 -d 10.118.0.0/20 -j ACCEPT; iptables -A FORWARD -o wg0 -s 10.118.0.0/20 -j ACCEPT; iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -d 10.118.0.0/20 -o eth1 -j MASQUERADE
Dec 23 13:20:50 ToolServer01 systemd[1]: Finished WireGuard via wg-quick(8) for wg0.
ops@ToolServer01:~$ sudo wg show
interface: wg0
  public key: HeNep2YOAfLYsE//D6iojN8peBZAy0AEDUQPYXp6cn4=
  private key: (hidden)
  listening port: 51820
ops@ToolServer01:~$ ip a show wg0
4: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN group default qlen 1000
    link/none
    inet 10.200.200.1/24 scope global wg0
       valid_lft forever preferred_lft forever


4) Tạo client profile cho AdminPC
4.1 Generate keypair cho AdminPC (trên ToolServer01)
sudo -i
umask 077
wg genkey | tee /etc/wireguard/adminpc.key | wg pubkey > /etc/wireguard/adminpc.pub
exit
sudo cat /etc/wireguard/adminpc.pub


Document: chỉ ghi adminpc.pub (không ghi adminpc.key)

###
Evidence:
ops@ToolServer01:~$ sudo cat /etc/wireguard/adminpc.pub
E392oDinMky+oF338ylcNJh3YCBU72zXlM81pc8Ybj8=
ops@ToolServer01:~$ sudo cat /etc/wireguard/adminpc.key
2DgvMIyXBrs6PlsOiHWKxLddTv7SQgOyF6+C5j5r50w=


4.2 Add peer vào server
CLIENT_PUB="$(sudo cat /etc/wireguard/adminpc.pub)"
sudo wg set wg0 peer "$CLIENT_PUB" allowed-ips 10.200.200.2/32
sudo wg-quick save wg0
sudo wg show

AC: wg show thấy peer AllowedIPs 10.200.200.2/32

###
Evidence:
ops@ToolServer01:~$ sudo wg show
interface: wg0
  public key: HeNep2YOAfLYsE//D6iojN8peBZAy0AEDUQPYXp6cn4=
  private key: (hidden)
  listening port: 51820

peer: E392oDinMky+oF338ylcNJh3YCBU72zXlM81pc8Ybj8=
  allowed ips: 10.200.200.2/32


4.3 Tạo adminpc.conf để copy về máy laptop
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

###
Evidence:
ops@ToolServer01:~$ sed 's/^PrivateKey.*/PrivateKey = ***REDACTED***/' ~/adminpc.conf
[Interface]
PrivateKey = ***REDACTED***
Address = 10.200.200.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = HeNep2YOAfLYsE//D6iojN8peBZAy0AEDUQPYXp6cn4=
Endpoint = 147.182.146.253:51820
AllowedIPs = 10.200.200.0/24, 10.118.0.0/20
PersistentKeepalive = 25


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

###
Evidence:
C:\Users\Admin>ping 10.200.200.1

Pinging 10.200.200.1 with 32 bytes of data:
Reply from 10.200.200.1: bytes=32 time=236ms TTL=64
Reply from 10.200.200.1: bytes=32 time=237ms TTL=64
Reply from 10.200.200.1: bytes=32 time=236ms TTL=64
Reply from 10.200.200.1: bytes=32 time=235ms TTL=64

Ping statistics for 10.200.200.1:
    Packets: Sent = 4, Received = 4, Lost = 0 (0% loss),
Approximate round trip times in milli-seconds:
    Minimum = 235ms, Maximum = 237ms, Average = 236ms

C:\Users\Admin>ping 10.118.0.5

Pinging 10.118.0.5 with 32 bytes of data:
Reply from 10.118.0.5: bytes=32 time=234ms TTL=64
Reply from 10.118.0.5: bytes=32 time=235ms TTL=64
Reply from 10.118.0.5: bytes=32 time=238ms TTL=64
Reply from 10.118.0.5: bytes=32 time=237ms TTL=64

Ping statistics for 10.118.0.5:
    Packets: Sent = 4, Received = 4, Lost = 0 (0% loss),
Approximate round trip times in milli-seconds:
    Minimum = 234ms, Maximum = 238ms, Average = 236ms


PS C:\Users\Admin\Desktop\oceandigital> ssh root@10.118.0.2
root@10.118.0.2's password:
Welcome to Ubuntu 22.04.4 LTS (GNU/Linux 5.15.0-113-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

 System information as of Tue Dec 23 07:05:01 UTC 2025

  System load:  0.0                Processes:             121
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
Last login: Mon Dec 22 09:14:51 2025 from 14.161.30.130