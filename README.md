# unifi-helm-chart

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/qaoru/unifi-helm-chart?style=flat-square)](https://github.com/qaoru/unifi-helm-chart/releases)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue?style=flat-square)](./LICENSE)
[![Chart version](https://img.shields.io/badge/chart%20version-1.1.0-informational?style=flat-square)](https://github.com/qaoru/unifi-helm-chart/releases/tag/v1.1.0)

A Helm chart for deploying the [UniFi Network Application](https://ui.com) as a
StatefulSet on Kubernetes. It runs the
[`linuxserver/unifi-network-application`](https://hub.docker.com/r/linuxserver/unifi-network-application)
container and bootstraps the required MongoDB user/databases via an init
container.

## Highlights

- **StatefulSet** with persistent `/config` storage (`volumeClaimTemplate`,
  default 5Gi), or `emptyDir` when persistence is disabled.
- **MongoDB bootstrap** — an init container (`mongo`) creates the UniFi database
  user and grants `dbOwner` on `unifi`, `unifi_stat`, and `unifi_audit`.
- **Two services** — an internal `ClusterIP` (HTTPS UI only, on by default) and
  an optional public `LoadBalancer` exposing all UniFi ports (inform, guest
  HTTP/HTTPS, speedtest, STUN, discovery, syslog).
- **Optional ingress** routing to the internal service on port 8443.
- **Network policies** — your choice of standard Kubernetes `NetworkPolicy` or
  `CiliumNetworkPolicy`, with sensible defaults for UniFi's required egress.
- **Service account** with `automountServiceAccountToken: false`.
- **Secret management** — optionally generate the UniFi DB credentials secret
  with a random password; admin credentials supplied via an existing secret.
- **Cosign-signed OCI releases** published to GHCR via GitHub Actions.

## Quick start

Install the latest published version from the GitHub Container Registry:

```bash
helm install unifi oci://ghcr.io/qaoru/helm-charts/unifi --version 1.1.0 \
  --set database.host=<your-mongodb-host> \
  --set database.credentials.generate=true
```

You'll also need a secret with MongoDB **admin** credentials (used by the init
container to create the UniFi database user):

```bash
kubectl create secret generic unifi-db-credentials \
  --from-literal=admin-username=<your-mongo-admin-user> \
  --from-literal=admin-password=<your-mongo-admin-password>
```

For the full list of values (services, ingress, network policies, probes,
resources, security contexts, etc.), see the
[chart README](./unifi/README.md).

## Prerequisites

- Kubernetes >= 1.21
- Helm >= 3.7 (OCI support)
- A running MongoDB instance reachable from the cluster, with admin credentials
  stored in a Kubernetes `Secret`

## Development

Lint the chart:

```bash
helm lint unifi/
```

Render templates locally:

```bash
helm template unifi ./unifi --namespace default
```

The chart's `README.md` is generated from `README.md.gotmpl` using
[helm-docs](https://github.com/norwoodj/helm-docs). Regenerate it after editing
values or the template:

```bash
helm-docs unifi/
```

A [pre-commit](https://pre-commit.com) hook is provided to keep the chart docs
in sync locally (requires Docker):

```bash
pip install pre-commit
pre-commit install
```

## Releasing

Releases are automated via the `Release Chart` GitHub Actions workflow
(`.github/workflows/release.yaml`):

1. **On push to `main`** — if the `version` and/or `appVersion` in
   `unifi/Chart.yaml` changed compared to the previous state of the branch, the
   workflow regenerates `unifi/README.md` with helm-docs, bumps the hardcoded
   version references in the top-level `README.md`, and commits the docs. If
   only `appVersion` changed (e.g. a Renovate image-update PR) without a
   matching `version` bump, it also auto-bumps the chart patch `version` and
   adds an Artifact Hub changelog entry. It then creates the `v<version>` tag.
2. **On the resulting tag** (or a manually pushed `v*.*.*` tag) — the chart is
   linted, packaged, pushed and Cosign-signed to GHCR, Artifact Hub metadata is
   published, and a GitHub Release with auto-generated notes is created.

So the only manual step to cut a release is to bump `version` (and `appVersion`
as needed) in `unifi/Chart.yaml` and merge to `main`. Image-only updates are
handled automatically: [Renovate](./renovate.json) opens a PR bumping
`appVersion` + the Artifact Hub image annotation, and merging it triggers a
patch release.

## Contributing

Issues and pull requests are welcome. For non-trivial changes, please open an
issue first to discuss what you'd like to change.

## License

Distributed under the [Apache License 2.0](./LICENSE).