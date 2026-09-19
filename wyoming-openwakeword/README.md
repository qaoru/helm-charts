# wyoming-openwakeword

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square)
![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)
![AppVersion: 2.1.0](https://img.shields.io/badge/AppVersion-2.1.0-informational?style=flat-square)

Wyoming protocol server for openWakeWord wake word detection -- a single endpoint Home Assistant (or any Wyoming client) points at, with optional custom wake-word models fetched by an init container (community collection, GitHub releases, or any direct URL), and optional PVC persistence so models are not re-downloaded on every restart.

Runs the [rhasspy/wyoming-openwakeword](https://github.com/rhasspy/wyoming-openwakeword)
container as a StatefulSet. This is the wake word stage of a [Home Assistant
voice](https://www.home-assistant.io/voice_control/) pipeline: satellites
(Voice PE, ESPHome devices, ...) stream audio over the
[Wyoming protocol](https://github.com/rhasspy/wyoming) and this server answers
with wake word detections ([openWakeWord](https://github.com/dscripka/openWakeWord)).

## What this chart deploys

- `StatefulSet` -- the Wyoming server (TCP `10400`), with an optional
  `model-fetch` init container that downloads custom wake word models before
  the server starts. Idempotent: a model file that already exists is never
  re-downloaded, so with `persistence.enabled` models are fetched exactly once
  per volume (Kubernetes always runs init containers on every pod start -- the
  skip-if-present check is what makes that effectively "once"). Set
  `modelFetch.enabled: false` to skip the container entirely (pre-populated
  volume).
- `Service` (headless, governing) -- required by the StatefulSet for stable pod
  identity.
- `Service` (ClusterIP) -- the endpoint Home Assistant points at:
  `wyoming-openwakeword.<namespace>.svc:<port>`.
- Optional `NetworkPolicy` / `CiliumNetworkPolicy` (flavor `kubernetes` or
  `cilium`).

Custom models are not required: the built-in openWakeWord models (`okay_nabu`,
`hey_jarvis`, ...) are bundled in the server and load on client request, with
no download at runtime. The init container only runs when you list `models`.

## Prerequisites

- Kubernetes >= 1.21
- Helm >= 3.7 (OCI support)

## Installation

Built-in models only, no persistence (nothing is downloaded at all):

```bash
helm install wyoming-openwakeword oci://ghcr.io/qaoru/helm-charts/wyoming-openwakeword --version 0.1.0
```

Or with custom models from the community collection and a PVC so they are not
re-downloaded on every restart:

```yaml
models:
  - name: glados
    path: en/glados/glados.tflite           # inside modelsCollection
  - name: timer
    url: https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/timer_v0.1.tflite
  - name: tars
    path: en/TARS/TARS.tflite
    optional: true
persistence:
  enabled: true
```

```bash
helm install wyoming-openwakeword oci://ghcr.io/qaoru/helm-charts/wyoming-openwakeword --version 0.1.0 -f values.yaml
```

### 3. Connect Home Assistant

In Home Assistant (`Settings` -> `Devices & Services` -> `Add Integration` ->
`Wyoming`), point the integration at:

| Field | Value |
| --- | --- |
| Host | `wyoming-openwakeword.<namespace>.svc.cluster.local` |
| Port | `10400` (default) |

Your wake words (built-in + custom) appear in the Assist pipeline wake word
selection. The model name clients see is the `models[].name` filename stem
(an `_vX.Y` suffix is stripped by the server, so `hey_computer.tflite` is
`hey computer`).

## Model fetching details

- `models[].path` downloads from `<modelsCollection>/<path>` (spaces are
  percent-encoded automatically).
- `models[].url` downloads from any direct `.tflite` URL (`url` wins when
  both are set).
- Downloads are verified against `sha256` when set, saved atomically
  (`<name>.tflite.part` then rename), and skipped entirely when the target
  file already exists. A failed required model blocks the pod start; set
  `optional: true` to continue instead.
- The init container runs as non-root from a pinned `curlimages/curl` image.

Note (Kubernetes behavior, not chart-specific): `persistence.size` is part of
the StatefulSet `volumeClaimTemplate` and is **immutable after install** --
changing it on upgrade fails with `field is immutable`; pre-provision a bigger
volume instead.

## Where to get custom models

The server (via `pyopen-wakeword`) loads openWakeWord-format `.tflite` models
from `--custom-model-dir`. Sources (all verified to load in
`rhasspy/wyoming-openwakeword:2.1.0`):

| Source | How | Auth |
| --- | --- | --- |
| Built-in models (`okay_nabu`, `hey_jarvis`, `hey_mycroft`, `hey_rhasspy`, `alexa`) | Bundled in the image -- nothing to download | none |
| [fwartner/home-assistant-wakewords-collection](https://github.com/fwartner/home-assistant-wakewords-collection) -- 100+ community wake words (en, dk, fi, ru, zh) | `models[].path` (resolves against `modelsCollection`), e.g. `en/glados/glados.tflite` | none |
| [dscripka/openWakeWord releases](https://github.com/dscripka/openWakeWord/releases) -- upstream pretrained models (`timer`, `weather`, ...) | `models[].url` with the release asset URL, e.g. `https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/timer_v0.1.tflite` | none |
| Any other URL hosting an openWakeWord-format `.tflite` | `models[].url` | none |

## Network policy

Disabled by default. `networkPolicy.flavor: kubernetes` renders a standard
`NetworkPolicy`, `cilium` a `CiliumNetworkPolicy`:

- **ingress**: Wyoming clients only (defaults to pods labelled
  `app.kubernetes.io/name=home-assistant` in the release namespace, on the
  Wyoming port).
- **egress**: DNS to kube-dns, and HTTPS to anywhere when
  `networkPolicy.allowModelDownloads` is true (only the init container needs
  it). Extra rules can be appended via `networkPolicy.egress` /
  `networkPolicy.cilium.egress`.

## Persistence and replicas

With `persistence.enabled`, each replica provisions its **own** PVC
(per-ordinal `volumeClaimTemplate`) and fetches its own copy of the models --
`ReadWriteOnce` is fine at any replica count (the server only *reads* the
models; only the init container writes, once per volume). To fetch once and
share a single models volume across all replicas, use `ReadWriteMany` on a
shared filesystem. Without persistence, an ephemeral `emptyDir` means the
models re-download on every pod start.

## Security posture

- The server runs as UID/GID 1000, non-root, all capabilities dropped,
  read-only root filesystem, seccomp `RuntimeDefault`. It needs no privileges
  (it only reads its bundled models and venv, and writes nothing) -- override
  `containerSecurityContext` if your environment disagrees.
- The init container runs as non-root from the distroless-style
  `curlimages/curl` image, read-only root filesystem, all capabilities dropped.
- The Wyoming port has no HTTP endpoint; probes are `tcpSocket`.
- Detection state is per TCP connection, so `replicaCount` > 1 is safe.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity for the pod |
| containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Security context for the main server container. The upstream image has no USER directive and is root by default, but the server needs no privileges: it only reads its venv and bundled models and writes nothing. Running non-root is the safe default; override here if your environment disagrees. |
| debug | bool | `false` |  |
| env | object | `{}` | Environment variables for the server container |
| extraArgs | list | `[]` | Additional upstream CLI arguments (e.g. ["--zeroconf", "my-wake-word"]). Note: --custom-model-dir is managed by the chart; zeroconf discovery is rarely useful in Kubernetes (clients use the Service DNS name). |
| extraEnv | list | `[]` | Additional environment variables as a list of {name, value} objects |
| fullnameOverride | string | `""` | Fully override the resource name prefix |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"rhasspy/wyoming-openwakeword","tag":null}` | Container image. `tag` defaults to the chart `appVersion` (pinned to an upstream release tag, kept up to date by Renovate). |
| modelFetch | object | `{"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"enabled":true,"image":{"pullPolicy":"IfNotPresent","repository":"curlimages/curl","tag":"8.22.0"},"resources":{}}` | Init container that downloads custom wake word models into `modelsDir` before the server starts. Runs only when `models` is non-empty. |
| models | list | `[]` | Custom wake word models (.tflite) served by the server. Each entry is downloaded into `modelsDir` by the `model-fetch` init container (skipped when the file already exists -- combined with `persistence`, models are fetched once per volume, not per pod restart). Leave empty to serve only the built-in models. Each entry needs `name` and one of `path` (inside the community collection) or `url` (any direct .tflite URL). |
| modelsCollection | string | `"https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/main"` | Base URL for models[].path entries: the community wake word collection (https://github.com/fwartner/home-assistant-wakewords-collection). Override to point at a fork or mirror. |
| modelsDir | string | `"/data/models"` | Directory inside the pod where custom models are written and from where the server loads them (passed as `--custom-model-dir`). |
| modelsStorage | object | `{"size":"1Gi"}` | Models storage. Ephemeral emptyDir by default (models re-download on every pod start). Set `persistence.enabled` to back it with a StatefulSet volumeClaimTemplate PVC so models are fetched once and survive restarts. |
| nameOverride | string | `""` | Override the chart name (used in resource names) |
| networkPolicy | object | `{"allowModelDownloads":true,"cilium":{"egress":[],"ingress":[]},"egress":[],"enabled":false,"flavor":"kubernetes","ingress":[{"from":[{"podSelector":{"matchLabels":{"app.kubernetes.io/name":"home-assistant"}}}],"ports":[{"port":10400,"protocol":"TCP"}]}]}` | Network policy configuration |
| nodeSelector | object | `{}` | Node selector for the pod |
| persistence | object | `{"accessMode":"ReadWriteOnce","enabled":false,"size":"2Gi","storageClass":""}` | Persistent storage for custom models. When enabled, a StatefulSet volumeClaimTemplate provisions a PVC per replica (ReadWriteOnce is fine: the server only READS the models, but each replica fetches its own copy -- use ReadWriteMany on a shared filesystem to fetch once and share across replicas). |
| podAnnotations | object | `{}` | Additional pod annotations |
| podLabels | object | `{}` | Additional pod labels |
| podSecurityContext | object | `{"fsGroup":1000,"fsGroupChangePolicy":"OnRootMismatch","seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context. fsGroup makes the models volume group-writable by the server and the init container. |
| probes | object | `{"liveness":{"enabled":true,"failureThreshold":6,"initialDelaySeconds":10,"periodSeconds":15,"timeoutSeconds":3},"readiness":{"enabled":true,"failureThreshold":12,"initialDelaySeconds":5,"periodSeconds":10,"timeoutSeconds":3}}` | Liveness and readiness probe configuration (tcpSocket on the Wyoming port: the Wyoming protocol has no HTTP health endpoint). |
| refractorySeconds | float | `2` | Seconds before the same wake word can trigger again. Upstream default 2. |
| replicaCount | int | `1` | Number of replicas. Each replica serves its own clients; detection state is per connection, so scaling is safe. Keep 1 unless you run several voice pipelines. NOTE: with `persistence.enabled`, each replica provisions its own PVC (per-ordinal volumeClaimTemplate) and fetches its own copy of the models; to share a single models volume across replicas use `ReadWriteMany`. |
| resources | object | `{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Resource requests and limits. openWakeWord inference is modest (a few hundred MiB); models are small (0.5-2 MiB each). |
| revisionHistoryLimit | int | `3` | Number of revisions to keep in history |
| service | object | `{"annotations":{},"port":10400,"type":"ClusterIP"}` | Wyoming service configuration. Point the Home Assistant Wyoming integration at `<service>:<port>` (host = release-namespace-qualified DNS name). |
| serviceAccount | object | `{"annotations":{},"automount":false,"create":true,"name":""}` | Service account configuration |
| threshold | float | `0.5` | Wake word threshold, 0.0-1.0 (higher = fewer false activations). Upstream default 0.5. |
| tolerations | list | `[]` | Tolerations for the pod |
| triggerLevel | int | `1` | Number of activations required before a detection is reported. Upstream default 1. |