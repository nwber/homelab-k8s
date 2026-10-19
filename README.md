# homelab-k8s

## Software

- Talos Linux
- Flux
- kube-prometheus-stack
- More on the way!

## Bootstrap (fresh cluster)

See the `homelab` repo for the Talos machine configs. On a bare cluster:

1. Install Cilium out-of-band before `flux bootstrap`: with `cni: none` and
   kube-proxy off, nothing can schedule — not even Flux — until a CNI is
   running (keep the values identical to `flux/cilium/cilium.yaml`).
2. `flux bootstrap` with `./flux` as the sync path is then enough:
   - Gateway API CRDs are vendored in `flux/gateway-api/crds/` and applied in
     the same revision as the `Gateway`/`HTTPRoute` objects that need them
     (see `flux/gateway-api/README.md`).
   - Manifests whose CRDs come from a HelmRelease (e.g. the `talos-metrics`
     ServiceMonitor) live outside `./flux` in `manifests/` and are applied by
     their own Kustomizations, which retry until the CRDs exist.

## Hardware

Each node is an Optiplex 3070 and currently has:

- i5-8500T
- 8GB DDR4 SODIMM
- 128GB NVMe SSD
- 1G NIC

This hardware was chosen because it's cheap(ish), very small, and the T processors have very low power draw.

Future upgrades:
- Data drive, because keeping OS + workloads on the same is bad 
  - 2.5" SATA because the host drive uses the only M.2 suitable for storage and these came with 2.5" caddies 
  - 256/512GB _with DRAM_
  - Samsung PM871b 256GB are [~$30/each](https://www.ebay.com/itm/117363618593?_skw=Samsung+PM871b+sata+256gb&itmmeta=01M4ZQA0YJ0XEDHAAYMSSHBQBV&hash=item1b536ab321:g:XqIAAeSwXyBqgnq~&itmprp=enc%3AAQALAAABACHNgUiiE%2FjQhlDTaMiAde%2BRuDbb8W%2FFEv%2B4h07raGm4e%2FaAyuii4OMGCebYSz4z4ZEk7UCDr6BewGBi95qI3cRwHQnYj0W13td8iUwRAKUr4ZQeJMeliGSQ%2BdiSsuKpTqkWu2AnHYkXutOfcMr5f9mbnsDJv7FvG6FUhXpP6GtnL7UkFbc175WsqHsVoD3%2FaglqIW8hcqqF7apUG%2BoS2dbAR%2BUCGsEsz%2BrLCKx%2FGgSDFQMoel1t7ycAw50rI4bWMwmVu2DsOX1%2BPEdRBdeiM130g%2FdNeCGrLr1BVoQCpCmDDa8fuUC7T1VKzeIM0%2FpvE2rK3Up%2BjLyOyZh%2F7eAS%2BDA%3D%7Ctkp%3ABFBMto-o96do)
- 2.5g NIC
  - M.2 A+E key 2.5g adapters exist, they're like [$10](https://www.aliexpress.us/item/3256810440018736.html?src=google&src=google&albch=shopping&acnt=179-224-6891&isdl=y&slnk=&plac=&mtctp=&albbt=Google_7_shopping&aff_platform=google&aff_short_key=_oFgTQeV&albagn=888888&ds_e_adid=&ds_e_matchtype=&ds_e_device=m&ds_e_network=x&ds_e_product_group_id=&ds_e_product_id=en3256810440018736&ds_e_product_merchant_id=5478332436&ds_e_product_country=US&ds_e_product_language=en&ds_e_product_channel=online&ds_e_product_store_id=&ds_url_v=2&albcp=23128330536&albag=&isSmbAutoCall=false&needSmbHouyi=false&gatewayAdapt=glo2usa) 
  - I'd also need to upgrade the switch because it's the cheapest one I could find at microcenter
- RAM
  - What am I, rich?
  - Seriously, 8GB sticks are only [~$30/each](https://www.ebay.com/itm/206556920695?_skw=8gb+ddr4+sodimm&itmmeta=01M4ZQ7345M6X9SA1ARCPGA1M0&hash=item3017c07b77:g:4DEAAeSw-0FqqCUZ&itmprp=enc%3AAQALAAAA0CHNgUiiE%2FjQhlDTaMiAde9wgOHpzP3F7medB0Vd5qSksc83iRN0l7rBZlf%2BXrkUV8Y8zqcgh0HxyaVgB57ytZQXAO1k3P1mSHNOFRqyKbia49KZz719ziqLDzWKdl257FnfDzplTt6cCa5s7BIhnarXqKdfxvvXorvmxNLAC8L6iaNRcYxDu7RZ5qDms3%2FxLXKvELu%2B2hTAR5A8KJY3U%2FcPu%2FmDF9HODhqLN4DS%2F3PxGiZn3TMcuK60BokjvgBh%2BDQ5DvpEsiaNFrligjzQPxk%3D%7Ctkp%3ABk9SR56ynPenaA) but I wouldn't upgrade until my worker's 24GB total is insufficient. I also have a laptop with 32+8GB sticks so I can harvest one (or both) of those for this
