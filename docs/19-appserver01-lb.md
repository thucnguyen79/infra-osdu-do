# Step 7 — Self-managed Load Balancer on AppServer01 (HAProxy)

## Goal
Provide a stable private endpoint (AppServer01) for HTTP/HTTPS to Kubernetes ingress-nginx NodePorts.

Traffic flow:
ToolServer01/VPN -> AppServer01:80/443 -> WorkerNode01/02:30080/30443 -> ingress-nginx -> Ingress/Services

## Why HAProxy
- Simple, reliable
- Supports TCP passthrough for 443
- Easy health checks and evidence capture

## Precheck
Evidence:
- artifacts/step7-lb-appserver01/AppServer01/ss-80-443.txt
- artifacts/step7-lb-appserver01/AppServer01/backend-tcp-precheck.txt

## Implementation (repo-first)
- Ansible playbook: ansible/playbooks/31-appserver01-lb-haproxy.yml
- Template: ansible/templates/haproxy.cfg.j2

Backends:
- workernode01 10.118.0.6:30080/30443
- workernode02 10.118.0.7:30080/30443

Evidence:
- artifacts/step7-lb-appserver01/run-appserver01-haproxy.log
- artifacts/step7-lb-appserver01/AppServer01/haproxy-version.txt
- artifacts/step7-lb-appserver01/AppServer01/ss-80-443-after.txt
- artifacts/step7-lb-appserver01/AppServer01/haproxy-service.txt

## Verification
- TCP test to LB: artifacts/step7-lb-appserver01/lb-tcp-test.txt
- Echo via LB: artifacts/step7-lb-appserver01/echo-via-lb.txt

## Notes
- HTTPS is TCP passthrough; TLS termination remains in Kubernetes (cert-manager later).
- With LB in front, client IP may appear as AppServer01 unless PROXY protocol is enabled later.

## Issue
- Symptom: ToolServer01 timeout tới 10.118.0.8:80/443
- Root causes checked:
   - HAProxy running/listening (evidence: appserver01-ss-80-443.txt, haproxy-status.txt, configcheck.txt)
   - Local curl on AppServer01 (evidence: appserver01-curl-localhost.txt)
   - Host firewall UFW (evidence: appserver01-ufw*.txt)
   - DO Cloud Firewall inbound 80/443 missing for AppServer01 (screenshot evidence)
- Fix: allow inbound TCP 80/443 from 10.118.0.0/20 (private-only)
