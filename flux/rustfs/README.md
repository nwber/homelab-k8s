# RustFS

S3-compatible object storage (rustfs.io), deployed with the upstream Helm
chart from <https://charts.rustfs.com>.

- `rustfs.yaml` — Namespace, HelmRepository, HelmRelease
- `rustfs-credentials.sops.yaml` — root credentials, SOPS-encrypted
- `rustfs-gateway.yaml` — the Gateway that fronts the S3 endpoint
- `rustfs-httproute.yaml` — routes for the S3 endpoint and the admin console

## Topology

Three pods, one per worker, one drive each (`replicaCount: 3`,
`drivesPerNode: 1`). The chart's required pod anti-affinity
(`kubernetes.io/hostname`) keeps one pod per node; the control plane is
tainted, so three workers is exactly what fits.

Each pod gets one 20Gi PVC from the `local-path` class. The storage class is
node-local: **a PVC is pinned to the node its pod first ran on**. If a pod is
evicted and rescheduled elsewhere, its claim stays bound to the old node and
the pod stays `Pending` — it cannot reattach the drive. Recovering means
moving the data back by hand (or accepting the loss of that pod's data and
letting the remaining two pods re-form the cluster with reduced redundancy).

The drives are erasure-coded, so the cluster survives the loss of one node.
With three drives the usable capacity is roughly two thirds of the raw
60Gi.

## Access

| What | Where |
|------|-------|
| S3 endpoint (in-cluster) | `http://rustfs-svc.rustfs.svc.cluster.local:9000` |
| S3 endpoint (LAN) | `http://192.168.1.245:9000` |
| Admin console (LAN) | `http://192.168.1.245:9000/rustfs/console/` |

The LAN address is the RustFS Gateway IP (`rustfs-gateway.yaml`), announced
on the LAN via Cilium's LB IPAM (L2 ARP). It is not a hostname yet: DNS for
the Gateway IP does not exist (BER-134), so the routes deliberately omit
`hostnames:` and match any `Host` header.

The console is served from the S3 port under a path prefix because **Cilium
builds one route table per Gateway** and merges routes with identical
matches into a single weighted cluster. Two routes on "/" (S3 and console)
would answer each other's requests at random. The console's own API calls
(`/rustfs/admin/v3/...`) are served by both ports, so they fall through to
the S3 route and still reach the admin API.

RustFS could not join the shared `homelab` Gateway for the same reason: that
Gateway already carries Grafana's catch-all on "/", and a second "/" route
would be merged into it.

## Credentials

The root access key and secret key live in
`rustfs-credentials.sops.yaml`, encrypted with the repo's age key (see
`.sops.yaml`). The chart refuses to render with the well-known
`rustfsadmin`/`rustfsadmin` pair, so the Secret is what makes the release
installable at all.

Read them with:

```sh
sops -d flux/rustfs/rustfs-credentials.sops.yaml
```

They are also the source of the internode RPC secret: RustFS derives it from
the credential pair, and refuses to derive it from the default credentials.

## Logging

`config.rustfs.obs_log_directory` is empty, which puts RustFS in
stdout-only mode: `kubectl logs` and the Polylane agent see the logs, and
there is no second PVC per pod. `obs_environment` stays `development` for
the same reason — `production` means file-only logging, which with no log
directory would leave the pods silent.
