# unifi-helm-chart

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/qaoru/unifi-helm-chart?style=flat-square)](https://github.com/qaoru/unifi-helm-chart/releases)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue?style=flat-square)](./LICENSE)
[![Chart version](https://img.shields.io/badge/chart%20version-1.0.4-informational?style=flat-square)](https://github.com/qaoru/unifi-helm-chart/releases/tag/v1.0.4)

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
helm install unifi oci://ghcr.io/qaoru/helm-charts/unifi --version 1.0.4 \
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

## Contributing

Issues and pull requests are welcome. For non-trivial changes, please open an
issue first to discuss what you'd like to change.

## License

Distributed under the [Apache License 2.0](./LICENSE).