# AGENTS.md

High level guidance:

- Above all else, do not lie. If you're unsure, give a 0-100% estimate of correctness.
- Do not take any actions that cause downtime, are destructive, or similar, without EXPLICIT approval from the user.
- All deployments and changes need to be done using configuration as code. One-off changes directly to the cluster are acceptable, but must be upstreamed afterwards.
- All changes must be tracked in git. After performing a user's request, you may stage the changes, but do not commit or push until the user has approved them.
- Changes should NEVER go directly to the `main` branch. Always open a well-named branch and create a PR to merge the changes into main.

## Talos

Refer to `talosctl --help` or `talosctl $command --help` for command guidance.

### Environment

- Talos is API-only — no SSH, no shell. Every operation goes through `talosctl`,
  authenticated with mutual TLS via a `talosconfig` client config.
- Cluster: one control plane + two workers, Talos v1.14.1, Kubernetes v1.37.0.
  API endpoint `https://192.168.1.235:6443`.
- Machine configs are **not** in this repo. They live in the `homelab` repo
  (`talos/controlplane.yaml`, `talos/worker.yaml`, `talos/talosconfig`), which is
  the source of truth for node-level config. This repo (`homelab-k8s`) is the
  Flux/GitOps repo and holds cluster workloads only.
- Always point `talosctl` at the repo copy:
  ```bash
  export TALOSCONFIG=$HOME/git/homelab/talos/talosconfig
  talosctl -n <node-ip> <command>
  ```

### Rules

- **Match versions.** Keep `talosctl` pinned to the Talos version (v1.14.1) and
  identical to the boot media. A mismatched client installs *its* version of
  Talos, not the media's.
- **Change config in git first.** Edit the machine config in the `homelab` repo,
  commit, then apply. Never hand-edit a live node.
- **Never assume a node's role or IP.** Hostnames are auto-generated and change
  on reinstall; read the IP off the console dashboard or find it with
  `nmap -sn 192.168.1.0/24`.
- **Verify the install disk before applying config.** On these machines `sda` is
  the 16 GB USB installer stick — far too slow for etcd/image I/O (it produced
  multi-second `slow fdatasync` warnings and a kube-apiserver that never
  started). Confirm `diskSelector` targets the NVMe:
  ```bash
  talosctl get disks --insecure -n <node-ip>   # expect nvme0n1, avoid sda
  ```
- **`--insecure` only works in maintenance mode.** A freshly booted installer
  sits in maintenance mode (API up, no config). Apply the config there:
  ```bash
  talosctl apply-config --insecure -n <node-ip> --file talos/worker.yaml
  ```
  Once installed and rebooted, drop `--insecure` and use the `talosconfig` certs.
- **`apply-config` on an installed node does not reinstall.** It only updates the
  running config. Reinstalling requires booting from the installer media again.
- **Bootstrap exactly once, control plane only.** `talosctl bootstrap` is a
  one-time, once-per-cluster operation on a single control-plane node. Running it
  again fails with `etcd data directory is not empty`.
- **Workers join automatically** once their config is applied — never bootstrap a
  worker.
- **Role labels can't be self-applied.** The NodeRestriction admission plugin
  rejects `node-role.kubernetes.io/*` written by the node's own kubelet. Set it
  with cluster-admin creds after the node joins:
  ```bash
  kubectl label node <node-name> node-role.kubernetes.io/worker=""
  ```
- **Secrets never go in this repo.** `controlplane.yaml`, `worker.yaml`, and
  `talosconfig` carry the cluster CA keys and tokens. They stay in the `homelab`
  repo and must not be committed unencrypted to anything public.
- **Keep the boundary clean.** Node/machine config is applied with `talosctl`
  from the `homelab` repo; workloads are delivered by Flux here. Don't manage node
  config through Flux.

### Health and diagnostics

```bash
talosctl -n <node-ip> health                # full health check
talosctl -n <node-ip> services              # service states + health
talosctl -n <node-ip> logs etcd             # etcd logs (watch for slow fdatasync)
talosctl -n <node-ip> logs kubelet
talosctl -n <node-ip> get SystemDisk        # confirm the install disk
talosctl -n <node-ip> get VolumeStatuses
talosctl kubeconfig --nodes 192.168.1.235   # refresh kubeconfig
kubectl get nodes -o wide
```

If a node is stuck after `apply-config`, check `get SystemDisk` and `logs etcd`
first — a slow install disk is the usual culprit.
