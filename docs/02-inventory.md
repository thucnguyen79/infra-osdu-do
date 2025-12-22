# Inventory Droplets (DigitalOcean)

| Name | Role | Public IP | Private IP | OS | Size |
|---|---|---:|---:|---|---|
| ToolServer01 | VPN/Bastion/Management | 147.182.146.253 | 10.118.0.5 | Ubuntu 22.04 | 8GB/4vCPU/240GB |
| AppServer01 | Self-managed LB/Edge | 142.93.154.5 | 10.118.0.8 | Ubuntu 22.04 | 32GB/8vCPU/640GB |
| ControlPlane01 | K8s Control Plane | 165.227.45.55 | 10.118.0.2 | Ubuntu 22.04 | 8GB/4vCPU/240GB |
| ControlPlane02 | K8s Control Plane | 138.197.136.247 | 10.118.0.3 | Ubuntu 22.04 | 8GB/4vCPU/240GB |
| ControlPlane03 | K8s Control Plane | 159.89.121.113 | 10.118.0.4 | Ubuntu 22.04 | 8GB/4vCPU/240GB |
| WorkerNode01 | K8s Worker | 159.203.10.8 | 10.118.0.6 | Ubuntu 22.04 | 32GB/8vCPU/640GB |
| WorkerNode02 | K8s Worker | 138.197.165.20 | 10.118.0.7 | Ubuntu 22.04 | 32GB/8vCPU/640GB |
