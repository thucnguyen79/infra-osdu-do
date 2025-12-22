# Inventory Droplets (DigitalOcean)

| Name | Role | eth0 (Public + 10.20/16) | eth1 (VPC 10.118/20) | OS | Size |
|---|---|---|---|---|---|
| ToolServer01 | VPN/Bastion/Management | 147.182.146.253/20 ; 10.20.0.8/16 | 10.118.0.5/20 | Ubuntu 22.04 | 8GB/4vCPU/240GB |
| AppServer01 | Self-managed LB/Edge | 142.93.154.5/20 ; 10.20.0.11/16 | 10.118.0.8/20 | Ubuntu 22.04 | 32GB/8vCPU/640GB |
| ControlPlane01 | K8s Control Plane | 165.227.45.55/20 ; 10.20.0.5/16 | 10.118.0.2/20 | Ubuntu 22.04 | 8GB/4vCPU/240GB |
| ControlPlane02 | K8s Control Plane | 138.197.136.247/20 ; 10.20.0.6/16 | 10.118.0.3/20 | Ubuntu 22.04 | 8GB/4vCPU/240GB |
| ControlPlane03 | K8s Control Plane | 159.89.121.113/20 ; 10.20.0.7/16 | 10.118.0.4/20 | Ubuntu 22.04 | 8GB/4vCPU/240GB |
| WorkerNode01 | K8s Worker | 159.203.10.8/20 ; 10.20.0.9/16 | 10.118.0.6/20 | Ubuntu 22.04 | 32GB/8vCPU/640GB |
| WorkerNode02 | K8s Worker | 138.197.165.20/20 ; 10.20.0.10/16 | 10.118.0.7/20 | Ubuntu 22.04 | 32GB/8vCPU/640GB |

