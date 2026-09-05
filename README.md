# helm-charts

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue?style=flat-square)](./LICENSE)

A collection of [Helm](https://helm.sh) charts published two ways:

- **OCI** — Cosign-signed artifacts in the GitHub Container Registry:
  `oci://ghcr.io/qaoru/helm-charts/<chart>`.
- **HTTP(S)** — a classic Helm repository served via GitHub Pages at
  <https://qaoru.github.io/helm-charts> (add it with `helm repo add`, see
  [Install](#install) below).

## Charts

| Chart | Description | README |
| --- | --- | --- |
| [unifi](./unifi) | UniFi Network Application (linuxserver image) as a StatefulSet with MongoDB bootstrap, dual services, optional ingress, and network policies. | [unifi/README.md](./unifi/README.md) |
| [open-terminal](./open-terminal) | Single [Open Terminal](https://github.com/open-webui/open-terminal) instance (the agent execution sandbox for Open WebUI) with optional Cilium air-gapped network isolation. | [open-terminal/README.md](./open-terminal/README.md) |

## Install

Charts can be installed from either source.

### OCI (GHCR)

Install a specific version directly from the GitHub Container Registry, e.g.
for `unifi`:

```bash
helm install unifi oci://ghcr.io/qaoru/helm-charts/unifi --version 1.1.0
```

### HTTP(S) repository (GitHub Pages)

Add the repository once, then install/update charts by name:

```bash
helm repo add qaoru https://qaoru.github.io/helm-charts
helm repo update
helm install unifi qaoru/unifi --version 1.1.0
```

> The HTTP(S) repository requires GitHub Pages to be enabled on the
> `gh-pages` branch (Settings → Pages → Source: Deploy from a branch →
> `gh-pages` / root). The `index.yaml` is rebuilt automatically on each
> release by the `Release Charts` workflow.

See each chart's README for chart-specific prerequisites and values.

## Development

Lint a chart:

```bash
helm lint unifi/
helm lint open-terminal/
```

Render templates locally:

```bash
helm template unifi ./unifi --namespace default
helm template open-terminal ./open-terminal --namespace default
```

Each chart's `README.md` is generated from `README.md.gotmpl` using
[helm-docs](https://github.com/norwoodj/helm-docs). Regenerate a chart's docs
after editing its values or template:

```bash
helm-docs unifi/
helm-docs open-terminal/
```

A [pre-commit](https://pre-commit.com) hook is provided to keep chart docs in
sync locally (requires Docker):

```bash
pip install pre-commit
pre-commit install
```

## Releasing

Releases are automated via the `Release Charts` GitHub Actions workflow
(`.github/workflows/release.yaml`), run **per chart**:

1. **On push to `main`** — for each chart whose `version` and/or `appVersion`
   in `<chart>/Chart.yaml` changed compared to the previous state of the branch,
   the workflow regenerates that chart's `README.md` with helm-docs and, if only
   `appVersion` changed (e.g. a Renovate image-update PR) without a matching
   `version` bump, auto-bumps the chart patch `version` and adds an Artifact Hub
   changelog entry. It then creates the `<chart>-<version>` tag (e.g.
   `open-terminal-0.1.1`).
2. **On the resulting tag** (or a manually pushed `<chart>-<version>` tag) — the
   chart is linted, packaged, pushed and Cosign-signed to
   `ghcr.io/qaoru/helm-charts/<chart>`, Artifact Hub repository metadata is
   published, and a GitHub Release named `<chart>-<version>` with auto-generated
   notes is created. After all charts for a run are published, a final `pages`
   job rebuilds `index.yaml` from the GitHub Releases and pushes it to the
   `gh-pages` branch, updating the HTTP(S) Helm repository.

So the only manual step to cut a release is to bump `version` (and `appVersion`
as needed) in a chart's `Chart.yaml` and merge to `main`. Image-only updates are
handled automatically: [Renovate](./renovate.json) opens a PR bumping
`appVersion` + the Artifact Hub image annotation, and merging it triggers a
patch release for that chart.

## Contributing

Issues and pull requests are welcome. For non-trivial changes, please open an
issue first to discuss what you'd like to change.

## License

Distributed under the [Apache License 2.0](./LICENSE).