---
name: Drain & Shutdown Node
description: Drain and power off a Talos Kubernetes node. Use when asked to shut down or power off a cluster node.
---

# Drain & shutdown a node

1. **Verify the node exists**: `kubectl get nodes -o wide`. Never assume node names or IPs; look them up.
2. **DOUBLE-CHECK with the user before shutting down**: reply with the node name, its IP, and what will be affected, then wait for explicit confirmation. Do not proceed on an ambiguous name.
3. Drain: `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=5m`. If PDB-blocked pods fail, report and ask — never add `--force` without approval.
4. Shutdown: `TALOSCONFIG=$HOME/git/homelab/talos/talosconfig talosctl -n <node-ip> shutdown`
5. Verify: `kubectl get nodes` shows the node `NotReady,SchedulingDisabled`. Power back on physically; the node rejoins automatically, then `kubectl uncordon <node>`.
