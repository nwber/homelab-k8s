#!/usr/bin/env bash
#
# Regenerate the Talos machine configs + talosconfig from the secrets bundle and
# sops-encrypt them into talos/*.sops.yaml.
#
#   talos/scripts/gen-configs.sh
#
# If talos/secrets.yaml is missing, a fresh secrets bundle is generated (rotation).
# Plaintext working copies land in talos/ (gitignored); only the *.sops.yaml files
# are committed.
#
# Requires: talosctl, sops, python3, and the age key at ~/.config/sops/age/keys.txt.
#
# NOTE: hostnames are applied post-generation because a config-patch cannot remove
# the default `auto: stable` from the HostnameConfig document (having both `auto`
# and `hostname` fails validation).
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/.local/bin:$PATH"

ENDPOINT_IP="${ENDPOINT_IP:-192.168.1.235}"
CP_HOSTNAME="${CP_HOSTNAME:-homelab-k8s-cp-0}"
WORKER_HOSTNAME="${WORKER_HOSTNAME:-homelab-k8s-worker-0}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

if [ ! -f talos/secrets.yaml ]; then
    echo "no talos/secrets.yaml — generating a fresh secrets bundle (rotation)"
    talosctl gen secrets -o talos/secrets.yaml
fi

talosctl gen config homelab "https://${ENDPOINT_IP}:6443" \
    --with-secrets talos/secrets.yaml \
    --config-patch @talos/patches/controlplane.yaml \
    --config-patch-control-plane @talos/patches/controlplane-only.yaml \
    --config-patch-worker @talos/patches/worker.yaml \
    --output "$OUT" --output-types controlplane,worker,talosconfig

python3 - "$OUT" "$ENDPOINT_IP" "$CP_HOSTNAME" "$WORKER_HOSTNAME" <<'PY'
import re, sys
out, endpoint, cp, worker = sys.argv[1:5]

def set_hostname(path, hostname):
    text = open(path).read()
    pat = re.compile(r'(?ms)^apiVersion: v1alpha1\nkind: HostnameConfig\n(?:.*?)(?=^---|\Z)')
    new, n = pat.subn(f"apiVersion: v1alpha1\nkind: HostnameConfig\nhostname: {hostname}\n", text)
    assert n == 1, f"{path}: expected 1 HostnameConfig, found {n}"
    open(path, "w").write(new)

def set_endpoints(path, ip):
    text = open(path).read()
    pat = re.compile(r'(?m)^        endpoints: \[\]\n')
    new, n = pat.subn(f"        endpoints:\n            - {ip}\n        nodes:\n            - {ip}\n", text)
    assert n == 1, f"{path}: expected empty endpoints, found {n}"
    open(path, "w").write(new)

set_hostname(f"{out}/controlplane.yaml", cp)
set_hostname(f"{out}/worker.yaml", worker)
set_endpoints(f"{out}/talosconfig", endpoint)
PY

talosctl validate --config "$OUT/controlplane.yaml" --mode metal
talosctl validate --config "$OUT/worker.yaml" --mode metal

cp "$OUT/controlplane.yaml" talos/controlplane.yaml
cp "$OUT/worker.yaml"       talos/worker.yaml
cp "$OUT/talosconfig"       talos/talosconfig

cp talos/controlplane.yaml talos/controlplane.sops.yaml
cp talos/worker.yaml       talos/worker.sops.yaml
cp talos/talosconfig       talos/talosconfig.sops.yaml
sops --encrypt --in-place talos/controlplane.sops.yaml
sops --encrypt --in-place talos/worker.sops.yaml
sops --encrypt --in-place talos/talosconfig.sops.yaml

echo "regenerated: talos/{controlplane,worker,talosconfig}.sops.yaml"
