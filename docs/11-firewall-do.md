# DigitalOcean Firewall (Step 3.1)

## Firewall Sets

### FW-TOOLSERVER01 (ToolServer01)
Inbound:
- UDP 51820 from <YOUR_PUBLIC_IP>/32  (WireGuard)
- TCP 22 from <YOUR_PUBLIC_IP>/32     (SSH admin allowlist)
Notes:
- ToolServer01 is the only public entrypoint for admin via VPN.

### FW-CLUSTER-NODES (ControlPlane01-03, WorkerNode01-02, AppServer01)
Inbound:
- TCP 22 from 10.118.0.5/32          (SSH from ToolServer01 only)
- (Optional for later) TCP 6443 from 10.118.0.8/32  (if AppServer01 LB forwards to CP)
Notes:
- No public SSH allowed.
- All Kubernetes east-west traffic will be within VPC 10.118.0.0/20 (managed separately if needed).

## Droplet Mapping
- ToolServer01: 10.118.0.5
- AppServer01: 10.118.0.8
- ControlPlane01: 10.118.0.2
- ControlPlane02: 10.118.0.3
- ControlPlane03: 10.118.0.4
- WorkerNode01: 10.118.0.6
- WorkerNode02: 10.118.0.7

## Evidence
- Add screenshots or rule export from DO Console after applying.
