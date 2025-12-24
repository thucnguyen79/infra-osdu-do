# Issue: Step 4.2 pkgs.k8s.io key install fails due to /bin/sh (dash) pipefail

## Symptom
During canary run on ControlPlane01, task "Install Kubernetes apt key (pkgs.k8s.io)" failed with:
- /bin/sh: 1: set: Illegal option -o pipefail

## Root cause
Ansible `shell` module uses /bin/sh by default (dash on Ubuntu).
`dash` does not support `set -o pipefail`.

## Fix
Force the task to run with bash:
- Add `args: executable: /bin/bash` to the failing shell task.

## Evidence
- artifacts/step4-k8s-packages/run-canary.log (failed)
- artifacts/step4-k8s-packages/run-canary-2.log (after fix)
