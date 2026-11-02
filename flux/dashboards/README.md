# Grafana dashboards

Dashboards migrated from the old homelab1 Grafana (Docker stack on
`192.168.1.250:3030`) as of 2026-11-02, loaded by the kube-prometheus-stack
sidecar (`label grafana_dashboard: "1"`, folder from the `grafana_folder`
annotation — enabled in the HelmRelease values).

Each ConfigMap holds one dashboard file; the sidecar watches every namespace,
so these must stay in `monitoring` (next to Grafana) and under `./flux` for
the root Kustomization to apply them.

## What was migrated

| Dashboard (uid preserved)      | Old folder | New folder | State here |
| :---                           | :---       | :---       | :--- |
| Aranet4                        | OpenCode   | OpenCode   | Data only once the aranet4 exporter is scraped by this Prometheus (BER-18) |
| homelab-k8s - Node Health      | Homelab    | Homelab    | Rewritten, works today |
| homelab-k8s - Container Metrics| Homelab    | Homelab    | Rewritten, works today |
| homelab1 - System Journal Logs | Homelab    | Homelab    | Empty: `{job="system-journal"}` does not exist. Fills when node logs are ingested (Alloy currently ships container stdout only) |
| OpenCode Telemetry             | OpenCode   | OpenCode   | Empty until OpenCode runs here and ships traces to Tempo |
| Shepherd - Dev / - Prod        | General    | Homelab    | Empty until Shepherd runs here; its OTLP-derived `job="shepherd-production"` metrics have no equivalent in this cluster yet |
| Tapo Plug Power                | General    | Homelab    | Empty until the Tapo exporter is in this Prometheus (BER-18) |

## Rewrites applied during import

- **Datasource refs** are deterministic: the old uids were remapped on export
  to the uids pinned in this repo (`prometheus` — the chart's datasource,
  `loki` — `flux/logging/grafana-datasource.yaml`, `tempo` —
  `flux/tempo/tempo-datasource.yaml`).
- **Node Health** was `homelab1 - Server Health`: every `job="node"` (the
  old standalone node exporter) is now `job="talos"` — the nodes expose
  node_exporter-compatible metrics on `:9100`, collected by the
  `talos-metrics` ServiceMonitor. The disk panel additionally excludes the
  Talos-internal mounts (`rootfs`/tmpfs on `/system`, `/etc`, `/.extra`, ...);
  the only real filesystem on each node is the xfs `/var` on the NVMe.
- **Container Metrics** was `homelab1 - Container Metrics` (cAdvisor from a
  standalone Linux host, one series per docker container named `name`).
  This cluster scrapes cAdvisor from the kubelet (`job="kubelet"`), where
  the container identity is `namespace`/`pod`/`container` — panels aggregate
  `sum by (namespace, container)` and legends show
  `{{namespace}}/{{container}}` so the visual shape matches the old one.
- Everything else was imported 1:1 (queries left as written for the old
  environment; see the table above for when they light up).

## Regenerating

The JSON in each ConfigMap was produced from the exported dashboard payload
(`GET /api/dashboards/uid/<uid>` against the old Grafana, minus `meta`, `id`,
`version`), with the remaps above applied in a one-off script. Regenerate a
dashboard only by re-running that path — hand-editing the JSON fragments is
how the folder/uid wiring gets lost.
