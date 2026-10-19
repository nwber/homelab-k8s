# Gateway API CRDs (vendored)

Standard-channel Gateway API CRDs, vendored verbatim so the **root**
Kustomization (`./flux`) applies them together with the `Gateway` and
`HTTPRoute` objects that depend on them.

- Source: `github.com/kubernetes-sigs/gateway-api`, `config/crd/standard/`
- Tag: **v1.6.3** — the version Cilium 1.20 supports (check Cilium's Gateway
  API compatibility before bumping)
- Do not edit these files; they are upstream copies.

## Why vendored

kustomize-controller applies a revision in stages: namespaces, CRDs and
ClusterRoles first — waiting for the CRDs to be `Established` — and only then
dry-runs and applies the remaining objects. With the CRDs inside the root
apply, the `Gateway` object validates on the same revision that installs its
CRDs, including on a fresh cluster. The Cilium HelmRelease gets the same
guarantee (its chart renders the `cilium` GatewayClass).

The previous setup (CRDs served by an upstream GitRepository reconciled by a
separate `gateway-api-crds` Kustomization) deadlocked a fresh cluster: the
root apply failed its dry-run on `Gateway` and never got far enough to create
the child Kustomization that would have installed the CRDs. See BER-137.

## Upgrading

1. Pick the tag supported by the installed Cilium.
2. Replace the files (all standard-channel CRDs; keep the same file names):

   ```sh
   tag=vX.Y.Z
   for f in crds/*.yaml; do
     curl -fsSL -o "$f" \
       "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/$tag/config/crd/standard/$(basename "$f")"
   done
   ```

3. `git diff` against the previous tag — every change comes from upstream.
4. Update the tag above, open a PR. CRD updates apply in place (no
   delete/recreate), so no special rollout ordering is needed.

> The experimental channel is intentionally not vendored — the standard
> channel is all Cilium 1.20 and this cluster need (Gateway/HTTPRoute).

## Migrating off the old upstream Kustomization (historical)

When the vendored files replaced the `gateway-api-crds` Kustomization
(2026-10-18, BER-137), the old Kustomization had to be removed without its
garbage collector deleting the CRDs (which would cascade-delete the
`Gateway`/`HTTPRoute` objects). The safe sequence was:

1. Add `spec.deletionPolicy: Orphan` to `flux/gateway-api/gateway-api-crds.yaml`,
   commit/push, and wait for the root Kustomization to reconcile.
2. Then remove the file and merge the rest.

Without step 1, deleting the child Kustomization deletes the CRDs; run
`flux reconcile kustomization flux-system --with-source` right after the
merge to re-create them immediately if that happens.
