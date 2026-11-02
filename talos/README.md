# Talos

Talos cluster on a Dell OptiPlex micro control plane (i5-8500T, 8GB RAM). Kubernetes API endpoint: `https://192.168.1.235:6443`. As of 2026-10-10 it is **not** single-node: 1 control plane (`talos-7ts-vcs`, rename pending) + 3 workers, with Flux and workloads running.

> Migrated from the `homelab` repo (`~/git/homelab/talos`) on 2026-11-03. The
> cluster is unchanged; this directory is now the source of truth and where
> `scripts/gen-configs.sh` runs. Note the encryption convention differs from
> the Flux manifests in this repo: `talos/*.sops.yaml` are sops-encrypted
> **whole-document** (they have no `data`/`stringData` keys to target) — see
> the talos rule, which must stay first, in the repo-root `.sops.yaml`.

## Files

| File | Purpose |
| :--- | :--- |
| `controlplane.sops.yaml` | age-encrypted machine config for the control plane node (source of truth — keep in sync with the node) |
| `worker.sops.yaml` | age-encrypted machine config for worker nodes |
| `talosconfig.sops.yaml` | age-encrypted client config for `talosctl` (context `homelab` → 192.168.1.235) |

**These files contain cluster secrets (Talos/Kubernetes/etcd CA keys, service-account key, etcd encryption key, join tokens, cluster secret).** Only the `*.sops.yaml` (age-encrypted) copies are committed. Plaintext working copies (`controlplane.yaml`, `worker.yaml`, `talosconfig`, `secrets.yaml`) are gitignored — **never commit them plaintext**.

## Secrets (sops + age)

Encrypted with [sops](https://github.com/getsops/sops) using an age recipient declared in the repo-root `.sops.yaml`. The age **private** key lives outside the repo at `~/.config/sops/age/keys.txt` (override with `SOPS_AGE_KEY_FILE`). **Back that key up somewhere safe — losing it makes these files unrecoverable.**

```bash
export PATH="$HOME/.local/bin:$PATH"   # where sops/age are installed

# Decrypt to a gitignored working copy
sops --decrypt talos/controlplane.sops.yaml > talos/controlplane.yaml
sops --decrypt talos/worker.sops.yaml       > talos/worker.yaml
sops --decrypt talos/talosconfig.sops.yaml  > talos/talosconfig

# Edit secrets in place ($EDITOR), re-encrypts on save
sops talos/controlplane.sops.yaml

# After editing a plaintext working copy, re-encrypt it back
cp talos/controlplane.yaml talos/controlplane.sops.yaml
sops --encrypt --in-place talos/controlplane.sops.yaml
```

## Usage

Always point talosctl at the repo copy (or export `TALOSCONFIG`):

```bash
export TALOSCONFIG=$HOME/git/homelab-k8s/talos/talosconfig
talosctl --nodes 192.168.1.235 services
```

## Regenerating configs (secret rotation / rebootstrap)

Use `talos/scripts/gen-configs.sh` — it generates configs from the secrets bundle
(`talos/secrets.yaml`, gitignored; created fresh if absent), fixes the `HostnameConfig`
documents (a config-patch cannot remove the default `auto: stable`: having both `auto` and
`hostname` fails validation), sets the `talosconfig` endpoints, validates, and sops-encrypts
the results into `talos/*.sops.yaml`.

```bash
talos/scripts/gen-configs.sh                                                # reuse existing secrets
talosctl gen secrets -o talos/secrets.yaml && talos/scripts/gen-configs.sh  # rotate
```

`talos/patches/{controlplane,worker}.yaml` hold the install-disk customization (NVMe
`diskSelector` + `wipe: true`). Override hostnames/endpoint via env:
`CP_HOSTNAME=… WORKER_HOSTNAME=… ENDPOINT_IP=… talos/scripts/gen-configs.sh`.

Applying fresh secrets is **destructive**: the control plane is wiped and re-bootstrapped, and
workers must re-join under the new machine config (per-node hostname for
`homelab-k8s-worker-1`/`-2`).

> **Status (2026-10-10): rotation complete.** All four nodes were rebuilt on the fresh secrets
> (`homelab-k8s-cp-0` + `homelab-k8s-worker-0/1/2`), etcd re-bootstrapped, and Flux re-bootstrapped
> from `ssh://git@github.com/nwber/homelab-k8s` (path `./flux`); workloads reconciled. Every
> credential that leaked into git history is now invalid.

## Hardware note (2026-10-01)

**Bootstrap failure root cause:** Talos was installed to a **16 GB USB flash drive** ("Ultra Backup", `/dev/sda`) because the generated config had `diskSelector: disk.dev_path == "/dev/sda"`. etcd repeatedly logged `slow fdatasync` up to **7 s** per write (vs. 1 s budget); `talosctl image pull` trickled at ~19 KB/s; containerd CreateContainer went into a reserve-then-timeout loop against the same stick, so kube-apiserver never came up (6443 refused) and bootstrap never completed. Also confirmed healthy on the node itself: NTP, DNS, PCIe AER clean — no other hardware issue found on the node.

**Fix (done 2026-10-10):** install disk is the machine's 128 GB KIOXIA NVMe (`/dev/nvme0n1`) with `wipe: true`; re-bootstrapped successfully.

Separate/parallel observation: the Talos node is a Dell (MAC e4:54:e8:92:0c:88) — homelab1 itself has ~95k correctable PCIe AER RxErr on 00:1b.0→01:00.0 (Optane) over 10 days; unrelated to the Talos node but flagged here for awareness.

## Current state (2026-10-10)

- **Full secret rotation done** after the leaked plaintext configs ended up in git history: all
  four nodes (`homelab-k8s-cp-0`, `homelab-k8s-worker-0/1/2`) were wiped and rebuilt from the
  fresh secrets, and etcd was re-bootstrapped on the NVMe install disk.
- Install disk is the 128 GB KIOXIA NVMe (`/dev/nvme0n1`, `wipe: true`) — the USB-stick install
  problem (see Hardware note) is resolved.
- Flux was re-bootstrapped from `ssh://git@github.com/nwber/homelab-k8s` (`./flux`) using the
  deploy key recovered from the pre-wipe cluster; workloads (podinfo, flux-system) reconciled.

## Rename plan (all applied as of 2026-10-10)

Configs set static hostnames instead of `auto: stable`: controlplane →
`homelab-k8s-cp-0`, worker → `homelab-k8s-worker-0` (shared default).

Applied:

- `homelab-k8s-worker-0` — 192.168.1.236 (was `talos-cyy-rks`) — 2026-10-09
- `homelab-k8s-worker-1` — 192.168.1.91 (new node, per-node hostname patch) — 2026-10-09
- `homelab-k8s-worker-2` — 192.168.1.63 (was `talos-dwq-8ja`, per-node hostname patch) — 2026-10-09
- `homelab-k8s-cp-0` — 192.168.1.235 (was `talos-7ts-vcs`; renamed via wipe + re-bootstrap) — 2026-10-10

**Worker rebuild (after a secrets rotation):** the workers still trust the old CA, so reset them
with the *old* `talosconfig` (backup copy), then apply the new config unauthenticated:

```bash
TALOSCONFIG=<old-talosconfig> talosctl reset -n <ip> --graceful=false --reboot \
  --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL
talosctl apply-config --insecure -n <ip> --file talos/worker.yaml \
  --config-patch '{"apiVersion":"v1alpha1","kind":"HostnameConfig","hostname":"homelab-k8s-worker-1"}'
```

Wiping STATE+EPHEMERAL returns the node to maintenance mode. Do **not** use the default
`--wipe-mode all`, which wipes the whole system disk and leaves the node unbootable remotely.
(`worker.yaml` already carries a static `hostname`, so the per-node patch only overrides it.)

**Control-plane rename** required the wipe + re-bootstrap described above (etcd member name is
fixed at bootstrap). Cluster state in etcd is lost, so Flux/workloads are re-bootstrapped and
reconciled from git afterwards.
