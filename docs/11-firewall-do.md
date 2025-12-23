# DigitalOcean Firewall - VPN (WireGuard)

## Droplet
- Name: ToolServer01
- Public IP: 147.182.146.253

## Rule (Inbound)
- Protocol: UDP
- Port: 51820
- Source CIDR: x.x.x.x/32   (Office/Home public IP)
- Target: ToolServer01
- Purpose: Allow WireGuard VPN handshake/traffic

## Notes
- Prefer restricting source CIDR (avoid 0.0.0.0/0).
- Ensure SSH (TCP 22) remains allowed from admin IPs.
- If UFW is enabled on the droplet, allow UDP 51820 there as well.
