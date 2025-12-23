# DigitalOcean Firewall - Step 3.1.2 (Harden Public Access)

## 1. Goal
- Disable public SSH access for AppServer01, ControlPlane01-03, WorkerNode01-02.
- Keep ToolServer01 as the only public admin entrypoint (SSH allowlist + WireGuard UDP 51820).
- Operate the cluster via private eth1 (VPC 10.118.0.0/20) + VPN.

## 2. Network assumptions
- VPC (eth1): 10.118.0.0/20
- ToolServer01 (eth1): 10.118.0.5
- Reason for allowing SSH only from 10.118.0.5/32:
  - AdminPC traffic enters via WireGuard and is NATed on ToolServer01.
  - Nodes see source as ToolServer01 private IP (10.118.0.5).

## 3. Firewall sets

### 3.1 FW-TOOLSERVER01
**Applied to**
- ToolServer01 (Public: 147.182.146.253, Private eth1: 10.118.0.5)

**Inbound rules**
- UDP 51820 from <YOUR_PUBLIC_IP>/32  (WireGuard)
- TCP 22 from <YOUR_PUBLIC_IP>/32     (SSH admin allowlist)

**Outbound rules**
- Default allow all (DigitalOcean default)

**Notes**
- This firewall is the only public-facing admin entry point.

### 3.2 FW-CLUSTER-NODES
**Applied to**
- AppServer01 (eth1: 10.118.0.8)
- ControlPlane01-03 (eth1: 10.118.0.2-4)
- WorkerNode01-02 (eth1: 10.118.0.6-7)

**Inbound rules**
- TCP 22 from 10.118.0.5/32 (ToolServer01 only)

**Outbound rules**
- Default allow all (DigitalOcean default)

**Notes**
- Public SSH is disabled by design.
- Kubernetes east-west traffic stays within VPC and is not restricted here (Step 5+ will address policies if needed).

## 4. Droplet mapping (eth1)
| Name | eth1 (VPC) |
|---|---:|
| ToolServer01 | 10.118.0.5 |
| AppServer01 | 10.118.0.8 |
| ControlPlane01 | 10.118.0.2 |
| ControlPlane02 | 10.118.0.3 |
| ControlPlane03 | 10.118.0.4 |
| WorkerNode01 | 10.118.0.6 |
| WorkerNode02 | 10.118.0.7 |

## 5. Verification (Evidence)
### 5.1 From AdminPC (expected FAIL)
- SSH to public IP of CP/Worker/AppServer01 must be blocked:
  - ssh ops@165.227.45.55  (ControlPlane01 public)
  - ssh ops@159.203.10.8   (WorkerNode01 public)
  - ssh ops@142.93.154.5   (AppServer01 public)
Result:
- Expected: timeout / blocked (cannot connect)

### 5.2 From VPN/private (expected OK)
- SSH to private eth1 must work:
  - ssh ops@10.118.0.2
  - ssh ops@10.118.0.6
Result:
- Expected: success

### 5.3 Screenshots
Stored in:
- artifacts/step3-firewall/screenshots/
Files:
- FW-TOOLSERVER01-rules.png
- FW-TOOLSERVER01-droplets.png
- FW-CLUSTER-NODES-rules.png
- FW-CLUSTER-NODES-droplets.png
