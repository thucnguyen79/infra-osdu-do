# DigitalOcean Firewall - Step 2 (WireGuard)

## Inbound rules
- UDP 51820 -> ToolServer01 (147.182.146.253)
  - Source: <YOUR_PUBLIC_IP>/32 (khuyến nghị) hoặc 0.0.0.0/0 (POC tạm)

## Notes
- Không mở public SSH cho ControlPlane/Worker.
- SSH (22) của ToolServer01 nên allowlist theo IP quản trị.
- Bước 3 sẽ siết tiếp firewall cho toàn cụm.
