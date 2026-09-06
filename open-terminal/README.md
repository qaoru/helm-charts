# open-terminal

![Version: 0.2.2](https://img.shields.io/badge/Version-0.2.2-informational?style=flat-square)
![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)
![AppVersion: 0.12.3-slim](https://img.shields.io/badge/AppVersion-0.12.3-slim-informational?style=flat-square)

Multiple Open Terminal workstations for Open WebUI -- the agent execution sandbox Open WebUI drives from chat -- each a stateful, individually-addressable endpoint with optional Cilium air-gapped network isolation and optional persistent workspace.

One or more [Open Terminal](https://github.com/open-webui/open-terminal) instances
-- the agent execution sandbox Open WebUI drives from chat: it runs commands,
manages files, and executes code. Each instance is a **workstation**: a single
stateful, individually-addressable endpoint a chat session binds to for its
lifetime. By default each workstation gets the strongest containment the chart
ships with: a slim image, an ephemeral workspace, and an embedded Cilium
network policy that air-gaps it (egress default-deny, ingress only from the
configured client).

## Why "workstations" (not replicas behind one Service)

Open Terminal is a **stateful, in-process server**. Per-session cwd, background
command jobs, and interactive PTY terminals all live in pod memory (keyed by
the `x-session-id` header / server-generated IDs), with **no shared/external
store**. So multiple replicas behind a single `Service` are *not* safe: a
request that load-balances to a different pod loses the cwd, 404s background
jobs, and reconnects the terminal WebSocket into a fresh empty shell. K8s
`sessionAffinity: ClientIP` does not fix this -- a pod restart nukes the
in-memory session, and behind the Open WebUI backend proxy every request
shares one client IP.

The upstream project's own guidance is the same shape: for multi-tenant use it
points to a companion project that provisions a **separate container per
user**. This chart follows that model at the Helm level: each `instances[]`
entry is one workstation (exactly one pod) with its own StatefulSet + Services +
NetworkPolicy, addressed by a stable DNS name. A workstation is intentionally a
single replica -- there is no safe way to scale one Open Terminal instance
horizontally, and `replicas` is fixed at 1. To run several workstations, add
several `instances[]` entries.

## What this chart deploys (per `instances[]` entry)

- `StatefulSet` -- `open-terminal-<name>`, a single pod running the slim image
  variant (pinned via `appVersion`) with the workspace at `/home/user`.
  Ephemeral `emptyDir` by default, or a per-pod PVC via `volumeClaimTemplates`
  when `persistence.enabled` is set.
- `Service` (headless, governing) -- `open-terminal-<name>-h`, required by the
  StatefulSet for stable pod identity. Not used for addressing (one pod only).
- `Service` (ClusterIP) -- `open-terminal-<name>`, the single endpoint Open
  WebUI points at: `http://open-terminal-<name>:8000`.
- `CiliumNetworkPolicy` -- (enabled by default) egress default-deny
  (air-gapped) and ingress only from the configured client pod on `:8000`.

## Addressing a workstation from Open WebUI

Every workstation is a single pod, addressed by its ClusterIP Service:

```
http://open-terminal-<name>:8000
```

Multiple workstations = multiple `instances[]` entries (each with its own
`name`), not replicas.

## Prerequisites

- Kubernetes (Cilium required for the embedded network policy)
- Helm >= 3.7 (OCI support)
- An existing `Secret` holding the Open Terminal API key (key `api-key`)

## Installation

### 1. Create the API key secret

The chart references an existing secret and never holds the key value:

```bash
kubectl create secret generic open-terminal-api-key \
  --from-literal=api-key=<your-api-key>
```

### 2. Install the chart

```bash
helm install open-terminal oci://ghcr.io/qaoru/helm-charts/open-terminal --version 0.2.2
```

Or with a local `values.yaml`:

```bash
helm install open-terminal oci://ghcr.io/qaoru/helm-charts/open-terminal --version 0.2.2 -f values.yaml
```

### 3. Deploy several workstations

```yaml
instances:
  - name: qa          # http://open-terminal-qa:8000
    env:
      OPEN_TERMINAL_FILE_BROWSER_ROOT: home

  - name: data        # http://open-terminal-data:8000  (persistent)
    persistence:
      enabled: true
      size: 20Gi
      storageClass: nfs

  - name: hardened    # http://open-terminal-hardened:8000
    image:
      tag: 0.12.3     # non-slim variant (runtime package installs)
    runtimeClassName: kata
    nodeSelector:
      katacontainers.io/kata-runtime: "true"
```

To run N workstations, add N entries -- each gets its own name, config, and
URL. (Do not try to scale a single workstation with replicas; Open Terminal is
stateful and per-session state lives in pod memory.)

## Isolation / security posture

| Layer | Choice |
| --- | --- |
| Image | slim variant (pinned via `appVersion`) -- no `sudo`, no runtime apt/pip/npm installs |
| Storage | ephemeral `emptyDir` by default (nothing persists across restarts); optional per-pod PVC via `persistence` |
| Network | Cilium egress default-deny (air-gapped) + ingress only from the configured client |
| Capabilities | all dropped except `CHOWN`/`SETUID`/`SETGID` (needed by the entrypoint's `gosu` privilege drop); no privilege escalation; seccomp `RuntimeDefault` |
| Resources | CPU/memory requests+limits per instance |

The slim image starts as root only so its entrypoint can `chown` the workspace
to UID 1000, then drops to `user` (UID 1000) via `gosu` with no sudo. We
therefore do **not** set `runAsNonRoot` at the pod level and keep
`CAP_CHOWN`/`CAP_SETUID`/`CAP_SETGID`; everything else is dropped.

## Hardened deployment (kata runtime)

By default the chart runs on the host kernel. To run the agent in a
hardware-isolated VM with its own kernel, set a `kata` `RuntimeClass` and pin
to nodes where the runtime is installed (e.g. by
[kata-deploy](https://github.com/kata-containers/kata-containers), which labels
KVM-capable workers `katacontainers.io/kata-runtime=true`):

```yaml
runtimeClassName: kata
nodeSelector:
  katacontainers.io/kata-runtime: "true"

instances:
  - name: hardened      # inherits chart-wide kata
  - name: plain         # overrides to run on the host kernel instead
    runtimeClassName: ""
    nodeSelector: {}
```

A pod with `runtimeClassName: kata` can fail container creation if it lands on a
node without the runtime, hence the node selector.

`runtimeClassName` and `nodeSelector` follow the **omit = inherit, present =
override** rule: an instance that omits them inherits the chart-wide value,
while an instance that sets them (including an explicit empty `""` / `{}`)
overrides the chart-wide value for that workstation. So you can set `kata`
chart-wide and drop it from a single instance with `runtimeClassName: ""` +
`nodeSelector: {}`, as above.

## Network policy

The embedded `CiliumNetworkPolicy` per instance (enabled by default) air-gaps
the agent:

- **egress**: fully denied. The agent can run commands, write files, and execute
  code, but cannot reach the internet, exfiltrate data, or talk to any other
  in-cluster service. Reply traffic for the allowed client -> `:8000` flow is
  statefully permitted by Cilium, so the proxy keeps working.
- **ingress**: only the configured client pod may reach `:8000`. Defaults to the
  `open-webui` app in the release namespace; change `networkPolicy.ingress` for a
  different source.

To let the agent reach the network (e.g. install packages), widen `egress` in
the policy **and** switch the image to a tag that supports runtime installs --
that is a deliberate, conscious loosening of the sandbox. Disable the embedded
policy entirely with `networkPolicy.enabled: false` (e.g. to manage isolation
elsewhere).

## One-time setup (Open WebUI)

Add **each** workstation connection **manually** in the Open WebUI admin UI
once (`Settings` -> `Admin` -> `Integrations` -> `Open Terminal` -> `+`):

| Field | Value |
| --- | --- |
| URL | `http://open-terminal-<name>:8000` (see the addressing table above) |
| API Key | `kubectl get secret <secret> -o jsonpath='{.data.<key>}' \| base64 -d` |
| Auth Type | Bearer |
| Chat Uploads | Default |

Why manual and not an env var? Open WebUI keeps `terminal_server.connections` in
its Postgres `config` table (`ENABLE_PERSISTENT_CONFIG` defaults on), so the
`TERMINAL_SERVER_CONNECTIONS` env var only ever seeds a fresh DB -- on an
already-running instance the existing row wins and the env is ignored. Wiring it
via the admin UI is the path that actually works here, and it's the docs'
recommended approach.

To restrict which users may use a workstation, edit the connection's access
control in the same admin UI page.

## Verify

```bash
kubectl get sts -l app.kubernetes.io/part-of=open-terminal
kubectl get svc -l app.kubernetes.io/part-of=open-terminal
# from the client pod, check a workstation is reachable:
kubectl exec deploy/<client> -- curl -s http://open-terminal-<name>:8000/health
# expect: {"status":"ok"}
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| apiKey | object | `{"existingSecret":"open-terminal-api-key","key":"api-key"}` | API key shared with Open WebUI (bearer auth). The owner creates the Secret (key `api-key`); this chart never holds the key value. An instance may override `apiKey` to use a dedicated secret per workstation. |
| apiKey.existingSecret | string | `"open-terminal-api-key"` | Existing Secret holding the API key. |
| apiKey.key | string | `"api-key"` | Key inside the Secret. |
| containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"add":["CHOWN","SETUID","SETGID"],"drop":["ALL"]},"readOnlyRootFilesystem":false}` | Container security context (chart-wide; not overridable per instance). |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"ghcr.io/open-webui/open-terminal","tag":null}` | Container image. `tag` defaults to the chart `appVersion` (a pinned `X.Y.Z-slim` variant tag, kept up to date by Renovate). An instance may override `image` (e.g. a custom tag for a specific workstation) and the per-instance value is merged over these defaults. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.repository | string | `"ghcr.io/open-webui/open-terminal"` | Container image repository. |
| image.tag | string | `nil` | Container image tag (defaults to Chart appVersion). |
| instances | list | `[{"apiKey":{},"env":{"OPEN_TERMINAL_FILE_BROWSER_ROOT":"home"},"image":{},"name":"default","networkPolicy":{"enabled":true,"flavor":"cilium","ingress":{"fromName":"open-webui","fromNamespace":"","port":8000}},"persistence":{"accessMode":"ReadWriteOnce","enabled":false,"mountPath":"/home/user","size":"10Gi","storageClass":""},"resources":{"limits":{"cpu":"1","memory":"1Gi"},"requests":{"cpu":"100m","memory":"256Mi"}},"workspace":{"size":"1Gi"}}]` | Workstations to deploy. `name` is required and must be DNS-safe (it becomes part of every resource name and the Service DNS name). At least one instance is required. |
| instances[0].apiKey | object | `{}` | API key override (merged over the chart-wide `apiKey`). Omit to share one secret across all workstations; set to a dedicated secret for this workstation. |
| instances[0].env | object | `{"OPEN_TERMINAL_FILE_BROWSER_ROOT":"home"}` | Open Terminal app env for this workstation (beyond OPEN_TERMINAL_API_KEY, which comes from the secret). host/port have NO env vars -- the app defaults to 0.0.0.0:8000, which is what we want. Slim has no runtime package installs and we rely on the Cilium egress default-deny for network isolation, so Open Terminal's own in-container iptables egress firewall (which would need NET_ADMIN) is unused. |
| instances[0].env.OPEN_TERMINAL_FILE_BROWSER_ROOT | string | `"home"` | UI hint only (does not restrict commands): report /home/user as the root. |
| instances[0].image | object | `{}` | Container image override (merged over the chart-wide `image`). Omit to inherit; set `tag` to pin a specific variant per workstation. |
| instances[0].name | string | `"default"` | Workstation name (DNS-safe). Becomes `open-terminal-<name>` in all resource names and the Service DNS name Open WebUI points at. |
| instances[0].networkPolicy | object | `{"enabled":true,"flavor":"cilium","ingress":{"fromName":"open-webui","fromNamespace":"","port":8000}}` | Embedded network isolation for this workstation. Enabled by default with a Cilium egress default-deny (air-gapped) and ingress limited to the configured source. The agent can run commands, write files, and execute code, but cannot reach the internet, exfiltrate data, or talk to any other in-cluster service. Reply traffic for the allowed source -> :8000 flow is statefully permitted by Cilium, so the proxy keeps working under egress default-deny. Kubelet liveness/readiness probes on /health are auto-allowed by Cilium (reserved:host / local-host ingress), so they need no rule here. |
| instances[0].networkPolicy.enabled | bool | `true` | Enable the embedded network policy. |
| instances[0].networkPolicy.flavor | string | `"cilium"` | Network policy flavor. Only `cilium` is implemented. |
| instances[0].networkPolicy.ingress | object | `{"fromName":"open-webui","fromNamespace":"","port":8000}` | Ingress rules: allow the configured source to reach the Open Terminal port. |
| instances[0].networkPolicy.ingress.fromName | string | `"open-webui"` | `app.kubernetes.io/name` label of the allowed client pod. Defaults to `open-webui` (the Open WebUI deployment pattern). |
| instances[0].networkPolicy.ingress.fromNamespace | string | `""` | Namespace of the allowed client pod (defaults to the release namespace when empty). |
| instances[0].networkPolicy.ingress.port | int | `8000` | Port the client reaches (Open Terminal listening port). |
| instances[0].persistence | object | `{"accessMode":"ReadWriteOnce","enabled":false,"mountPath":"/home/user","size":"10Gi","storageClass":""}` | Persistent workspace. When enabled, a StatefulSet volumeClaimTemplate provisions a PVC per pod (one per replica ordinal), so stateful workstations keep their /home/user across restarts and rolling updates. Disabled by default (ephemeral sandbox). |
| instances[0].persistence.accessMode | string | `"ReadWriteOnce"` | Access mode. `ReadWriteOnce` for a single-node workstation; use `ReadWriteMany` only with a shared filesystem (NFS, etc.); a workstation is one pod, so a single PVC writer is the only mode. |
| instances[0].persistence.enabled | bool | `false` | Provision a PVC for the workspace. |
| instances[0].persistence.mountPath | string | `"/home/user"` | Where the workspace is mounted. Open Terminal expects /home/user (single-user mode) or /home (multi-user mode). Change only if you run OPEN_TERMINAL_MULTI_USER=true, which needs the `latest` image. |
| instances[0].persistence.size | string | `"10Gi"` | PVC size. |
| instances[0].persistence.storageClass | string | `""` | StorageClass (empty = cluster default). |
| instances[0].resources | object | `{"limits":{"cpu":"1","memory":"1Gi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Container resource requests and limits. |
| instances[0].workspace | object | `{"size":"1Gi"}` | Workspace storage at /home/user. When `persistence.enabled` is false an ephemeral emptyDir is used (sizeLimit is a soft cap: it triggers kubelet eviction when exceeded, not a hard quota; nothing persists across pod restarts). When true a StatefulSet volumeClaimTemplate provisions a PVC per pod. |
| instances[0].workspace.size | string | `"1Gi"` | emptyDir sizeLimit for the workspace (used when persistence is off). |
| nodeSelector | object | `{}` | Node selector applied to every instance that does not set its own `nodeSelector`. When using the `kata` RuntimeClass, pin to nodes labeled `katacontainers.io/kata-runtime=true` (where kata-deploy installed the runtime); a pod with `runtimeClassName: kata` can fail container creation if it lands on a node without the runtime. An instance may override this (including setting `nodeSelector: {}` to drop a chart-wide pin). |
| podSecurityContext | object | `{"fsGroup":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context (chart-wide; not overridable per instance). The slim image starts as root only so its entrypoint can fix /home/user ownership, then drops to "user" (UID 1000) via gosu with NO sudo. We therefore do NOT set runAsNonRoot here (it would break the entrypoint's ownership fix / privilege drop). fsGroup: 1000 makes the workspace group-writable by the app even before the entrypoint chown runs. |
| runtimeClassName | string | `""` | Pod RuntimeClass (e.g. `kata` for a hardware-isolated VM with its own kernel). Empty/omitted by default. See README.md "Hardened deployment" for the kata setup. An instance may override this (including setting it to `""` to drop a chart-wide kata setting for that workstation). |