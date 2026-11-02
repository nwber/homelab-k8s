# AGENTS.md

High level guidance:

- Above all else, do not lie. If you're unsure, give a 0-100% estimate of correctness.
- Do not take any actions that cause downtime, are destructive, or similar, without EXPLICIT approval from the user.
- All deployments and changes need to be done using configuration as code. One-off changes directly to the cluster are acceptable, but must be upstreamed afterwards.
- All changes must be tracked in git. After performing a user's request, you may stage the changes, but do not commit or push until the user has approved them.
- Changes should NEVER go directly to the `main` branch. Work on a well-named branch and open a PR to merge into `main`. A branch represents a *change set*, not a single request: all changes related to a change set stay on one branch — if you're already on a suitable working branch, keep making related changes there instead of opening a new branch per request.

## Talos

Refer to `talosctl --help` or `talosctl $command --help` for command guidance.

### Environment

- Talos is API-only — no SSH, no shell. Every operation goes through `talosctl`,
  authenticated with mutual TLS via a `talosconfig` client config.
- Cluster: one control plane + three workers, Talos v1.14.1, Kubernetes v1.37.0.
  API endpoint `https://192.168.1.235:6443`. Current nodes: `homelab-k8s-cp-0`,
  `homelab-k8s-worker-0`, `homelab-k8s-worker-1`, `homelab-k8s-worker-2`.
- Machine config source of truth lives in **this repo** under `talos/`:
  sops+age-encrypted `talos/{controlplane,worker,talosconfig}.sops.yaml`
  (migrated from the `homelab` repo on 2026-11-03). Decrypt to the gitignored
  plaintext working copies before applying — `talos/README.md` is the runbook.
  `gen-configs.sh` regenerates them from `talos/secrets.yaml` (also gitignored).
- This repo (`homelab-k8s`) is the Flux/GitOps repo; `flux/` holds workloads
  and `talos/` holds node-level config — applied manually with `talosctl`,
  never by Flux.
- Always point `talosctl` at the repo copy:
  ```bash
  export TALOSCONFIG=$HOME/git/homelab-k8s/talos/talosconfig
  talosctl -n <node-ip> <command>
  ```

### Rules

- **Match versions.** Keep `talosctl` pinned to the Talos version (v1.14.1) and
  identical to the boot media. A mismatched client installs *its* version of
  Talos, not the media's.
- **Change config in git first.** Decrypt/edit/plain-copy the machine config
  under `talos/` here, commit the re-encrypted `*.sops.yaml` copy, then apply.
  Never hand-edit a live node.
- **`worker.yaml` is worker-0's config, not a template for all workers.** It
  carries `hostname: homelab-k8s-worker-0`. Workers 1 and 2 have their own
  hostnames applied out-of-band, and that fact is not recorded in this repo.
  Applying the same file to every worker makes them all register as
  `homelab-k8s-worker-0`: the node identities collide, the kubelet stops
  posting node status and the lease update fights (hit 2026-10-17 during the
  Cilium CNI swap). Rewrite the hostname per node — the same way
  `gen-configs.sh` does — before applying. See BER-136.
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
- **Pod Security defaults to `baseline`, not "off".** The Talos
  `KubeAdmissionControlConfig` sets cluster-wide `enforce: baseline`,
  `warn: restricted` for every namespace without an explicit label (only
  `kube-system` is exempt). A namespace that needs a hostPath volume or runs as
  root must opt up explicitly:
  ```yaml
  metadata:
    labels:
      pod-security.kubernetes.io/enforce: privileged
  ```
  `monitoring` and `logging` do exactly this. Without the label the pods are
  never created — the DaemonSet/Deployment reports `FailedCreate: violates
  PodSecurity "baseline:latest"` while the HelmRelease sits at `Stalled`.
- **Secrets go in sops-encrypted, or not at all.** `talos/*.sops.yaml` carry
  the cluster CA keys, join tokens, and the client certs. They are encrypted
  **whole-document** by the talos rule in `.sops.yaml` (which must stay first —
  the generic Flux rule would match nothing in a Talos config and silently
  leave the file plaintext). The decrypted working copies
  (`controlplane.yaml`, `worker.yaml`, `talosconfig`, `secrets.yaml`) are
  gitignored and must never be committed.
- **Keep the boundary clean.** `talos/` is applied manually with `talosctl`
  (machine configs are Talos documents, not Flux manifests); workloads are
  delivered by Flux from `./flux`. Don't manage node config through Flux.

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
