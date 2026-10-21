# Tailscale operator

The Tailscale Kubernetes operator, installed by Flux. It joins the tailnet on
its own and manages the `tailscale.com` CRDs and the Tailscale proxies the
cluster asks for later on (ingress, egress, subnet routers/exit nodes).

What lands in the cluster:

- `tailscale` namespace
- `operator` Deployment + ServiceAccount (the chart's historical default
  names — the chart sets `fullnameOverride` to nothing on purpose, see
  `templates/_helpers.tpl`)
- RBAC for the operator and for the proxies it creates
- `tailscale` IngressClass
- The `tailscale.com` CRDs (`Connector`, `ProxyClass`, `ProxyGroup`,
  `DNSConfig`, `Recorder`, `Tailnet`, …), installed by the chart itself

The OAuth client credentials are **not** in this directory in plaintext: they
live in the SOPS-encrypted `operator-oauth.sops.yaml` Secret.

## Prerequisites (Tailscale admin console)

These are one-time steps in the tailnet's admin console; nothing in this repo
can do them for you.

1. **Tags** — in [Access controls](https://console.tailscale.com/admin/acls/file),
   add:

   ```json
   "tagOwners": {
     "tag:k8s-operator": [],
     "tag:k8s": ["tag:k8s-operator"],
   },
   ```

   The operator device is tagged `tag:k8s-operator` and owns `tag:k8s`, which
   is what it puts on the proxies it creates.

2. **OAuth client** — in [Trust credentials](https://console.tailscale.com/admin/settings/trust-credentials),
   create an OAuth client with `write` scope for:

   - `General/Services` (tagged `tag:k8s-operator`)
   - `Devices/Core` (tagged `tag:k8s-operator`)
   - `Keys/AuthKeys` (tagged `tag:k8s-operator`)

   The operator uses it to register itself in the tailnet and to mint the auth
   keys the proxies use.

3. **Credentials in git** — put the client ID and secret into the encrypted
   Secret:

   ```sh
   sops flux/tailscale/operator-oauth.sops.yaml
   ```

   Fill in `stringData.client_id` and `stringData.client_secret`, save. The
   `data`/`stringData` values are the only thing SOPS encrypts, so the file
   stays readable by kustomize and Flux.

   The Secret must be named `operator-oauth`: that is the name the chart
   mounts (`<fullname>-oauth`, and the chart's default `fullname` is
   `operator`). If the chart's `fullnameOverride`/`nameOverride` ever change,
   the Secret name has to change with them.

## Validation

```sh
kubectl -n tailscale get pods
kubectl -n tailscale logs deploy/operator
```

The operator registers a device named `tailscale-operator` (tagged
`tag:k8s-operator`) in the tailnet — it shows up on the
[Machines](https://console.tailscale.com/admin/machines) page once the pod is
running. Until the Secret has valid credentials the pod stays in
`CreateContainerConfigError`/crash-loop, which is expected.

## Cluster-specific notes

**Cilium.** The operator's compatibility guide asks for the socket load
balancer to be bypassed in pod namespaces when Cilium runs in kube-proxy
replacement mode, because socket-level load balancing skips the netfilter
hooks the Tailscale firewall installs. This cluster already runs with that
socket LB off (`bpf-lb-sock=false`, `bpf-lb-sock-hostns-only=true` in the
`cilium-config` ConfigMap — the chart's `socketLB.enabled` default), so no
Cilium change is needed.

**Talos.** The nodes are Talos, which is API-only and does not run a shell;
the operator only needs the usual Kubernetes APIs, so that is not a problem.
Kernel-mode proxies (the ones the operator creates for `Connector` subnet
routers and exit nodes) need `/dev/net/tun`: the `tun` driver is present in
the Talos kernel (`/proc/misc` lists `200 tun`), and the proxy containers run
privileged, so they can create the device node themselves. Ingress proxies run
in userspace mode by default and need no TUN device at all.

**Subnet routes.** A `Connector` that advertises a route needs that route
approved in the tailnet admin console (or an auto-approver rule for the
connector's tag), and the clients using the route need to accept it.

## CRDs and where custom resources go

The chart installs the `tailscale.com` CRDs as part of the release, so a
`Connector` (or any other operator CR) cannot live in `./flux`: on a fresh
cluster the root apply would fail its dry-run with "no matches for kind
Connector" before the HelmRelease ever runs. Such manifests belong in
`./manifests/tailscale/`, applied by their own Kustomization that retries
until the CRDs exist — the same pattern as `manifests/talos-metrics/`.

## Upgrading

1. Bump `spec.chart.spec.version` in `flux/tailscale/tailscale-operator.yaml`
   to the new chart version (check `helm search repo tailscale`).
2. Refresh both image digests in the same file (the chart's `appVersion` is
   the image tag):

   ```sh
   docker buildx imagetools inspect tailscale/k8s-operator:v1.104.1
   docker buildx imagetools inspect tailscale/tailscale:v1.104.1
   ```

3. Merge, then watch the rollout:

   ```sh
   flux get helmrelease tailscale-operator --watch
   ```
