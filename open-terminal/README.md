# open-terminal

![Version: 0.1.1](https://img.shields.io/badge/Version-0.1.1-informational?style=flat-square)
![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)
![AppVersion: 0.12.3-slim](https://img.shields.io/badge/AppVersion-0.12.3-slim-informational?style=flat-square)

Single Open Terminal instance for Open WebUI, the agent execution sandbox, with optional Cilium air-gapped network isolation.

A single [Open Terminal](https://github.com/open-webui/open-terminal) instance --
the agent execution sandbox Open WebUI drives from chat: it runs commands,
manages files, and executes code. It gets the strongest containment the chart
ships with by default: a slim image, an ephemeral workspace, and an embedded
Cilium network policy that air-gaps it (egress default-deny, ingress only from
the configured client).

## What this chart deploys

- `Deployment` -- one `ghcr.io/open-webui/open-terminal` replica (the slim
  variant, pinned via `appVersion`) with an ephemeral `emptyDir` workspace at
  `/home/user`.
- `Service` -- `open-terminal` ClusterIP on `:8000` (same namespace as the
  release). Open WebUI reaches it at `http://open-terminal:8000`.
- `CiliumNetworkPolicy` -- (enabled by default) egress default-deny (air-gapped)
  and ingress only from the configured client pod on `:8000`.

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
helm install open-terminal oci://ghcr.io/qaoru/helm-charts/open-terminal --version 0.1.1
```

Or with a local `values.yaml`:

```bash
helm install open-terminal oci://ghcr.io/qaoru/helm-charts/open-terminal --version 0.1.1 -f values.yaml
```

## Isolation / security posture

| Layer | Choice |
| --- | --- |
| Image | slim variant (pinned via `appVersion`) -- no `sudo`, no runtime apt/pip/npm installs |
| Storage | ephemeral `emptyDir` -- nothing persists across restarts |
| Network | Cilium egress default-deny (air-gapped) + ingress only from the configured client |
| Capabilities | all dropped except `CHOWN`/`SETUID`/`SETGID` (needed by the entrypoint's `gosu` privilege drop); no privilege escalation; seccomp `RuntimeDefault` |
| Resources | CPU/memory requests+limits |

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
```

A pod with `runtimeClassName: kata` can fail container creation if it lands on a
node without the runtime, hence the node selector.

## Network policy

The embedded `CiliumNetworkPolicy` (enabled by default) air-gaps the agent:

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

Add the connection **manually** in the Open WebUI admin UI once
(`Settings` -> `Admin` -> `Integrations` -> `Open Terminal` -> `+`):

| Field | Value |
| --- | --- |
| URL | `http://open-terminal:8000` |
| API Key | `kubectl get secret open-terminal-api-key -o jsonpath='{.data.api-key}' \| base64 -d` |
| Auth Type | Bearer |
| Chat Uploads | Default |

Why manual and not an env var? Open WebUI keeps `terminal_server.connections` in
its Postgres `config` table (`ENABLE_PERSISTENT_CONFIG` defaults on), so the
`TERMINAL_SERVER_CONNECTIONS` env var only ever seeds a fresh DB -- on an
already-running instance the existing row wins and the env is ignored. Wiring it
via the admin UI is the path that actually works here, and it's the docs'
recommended approach.

To restrict which users may use the terminal, edit the connection's access
control in the same admin UI page.

## Verify

```bash
kubectl get deploy open-terminal
kubectl get svc open-terminal
# from the client pod, check Open Terminal is reachable:
kubectl exec deploy/<client> -- curl -s http://open-terminal:8000/health
# expect: {"status":"ok"}
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| apiKey | object | `{"existingSecret":"open-terminal-api-key","key":"api-key"}` | API key shared with Open WebUI (bearer auth). The owner creates the Secret (key `api-key`); this chart never holds the key value. |
| apiKey.existingSecret | string | `"open-terminal-api-key"` | Existing Secret holding the API key. |
| apiKey.key | string | `"api-key"` | Key inside the Secret. |
| containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"add":["CHOWN","SETUID","SETGID"],"drop":["ALL"]},"readOnlyRootFilesystem":false}` | Container security context. |
| env | object | `{"OPEN_TERMINAL_FILE_BROWSER_ROOT":"home"}` | Open Terminal app env (beyond OPEN_TERMINAL_API_KEY, which comes from the secret). host/port have NO env vars -- the app defaults to 0.0.0.0:8000, which is what we want. Slim has no runtime package installs and we rely on the Cilium egress default-deny for network isolation, so Open Terminal's own in-container iptables egress firewall (which would need NET_ADMIN) is unused. |
| env.OPEN_TERMINAL_FILE_BROWSER_ROOT | string | `"home"` | UI hint only (does not restrict commands): report /home/user as the root. |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"ghcr.io/open-webui/open-terminal","tag":null}` | Container image. `tag` defaults to the chart `appVersion` (a pinned `X.Y.Z-slim` variant tag, kept up to date by Renovate). |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.repository | string | `"ghcr.io/open-webui/open-terminal"` | Container image repository. |
| image.tag | string | `nil` | Container image tag (defaults to Chart appVersion). |
| networkPolicy | object | `{"enabled":true,"flavor":"cilium","ingress":{"fromName":"open-webui","fromNamespace":"","port":8000}}` | Embedded network isolation. Enabled by default with a Cilium egress default-deny (air-gapped) and ingress limited to the configured source. The agent can run commands, write files, and execute code, but cannot reach the internet, exfiltrate data, or talk to any other in-cluster service. Reply traffic for the allowed source -> :8000 flow is statefully permitted by Cilium, so the proxy keeps working under egress default-deny. Kubelet liveness/readiness probes on /health are auto-allowed by Cilium (reserved:host / local-host ingress), so they need no rule here. |
| networkPolicy.enabled | bool | `true` | Enable the embedded network policy. |
| networkPolicy.flavor | string | `"cilium"` | Network policy flavor. Only `cilium` is implemented. |
| networkPolicy.ingress | object | `{"fromName":"open-webui","fromNamespace":"","port":8000}` | Ingress rules: allow the configured source to reach the Open Terminal port. |
| networkPolicy.ingress.fromName | string | `"open-webui"` | `app.kubernetes.io/name` label of the allowed client pod. Defaults to `open-webui` (the Open WebUI deployment pattern). |
| networkPolicy.ingress.fromNamespace | string | `""` | Namespace of the allowed client pod (defaults to the release namespace when empty). |
| networkPolicy.ingress.port | int | `8000` | Port the client reaches (Open Terminal listening port). |
| nodeSelector | object | `{}` | Node selector for the pod. Empty/omitted by default. When using the `kata` RuntimeClass, pin to nodes labeled `katacontainers.io/kata-runtime=true` (where kata-deploy installed the runtime); a pod with `runtimeClassName: kata` can fail container creation if it lands on a node without the runtime. |
| podSecurityContext | object | `{"fsGroup":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context. The slim image starts as root only so its entrypoint can fix /home/user ownership, then drops to "user" (UID 1000) via gosu with NO sudo. We therefore do NOT set runAsNonRoot here (it would break the entrypoint's ownership fix / privilege drop). fsGroup: 1000 makes the emptyDir group-writable by the app even before the entrypoint chown runs. |
| replicaCount | int | `1` | Number of pod replicas. |
| resources | object | `{"limits":{"cpu":"1","memory":"1Gi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Container resource requests and limits. |
| runtimeClassName | string | `""` | Pod RuntimeClass (e.g. `kata` for a hardware-isolated VM with its own kernel). Empty/omitted by default. See README.md "Hardened deployment" for the kata setup. |
| workspace | object | `{"size":"1Gi"}` | Ephemeral workspace: emptyDir mounted at /home/user. `size` is a soft cap (sizeLimit triggers kubelet eviction when exceeded, not a hard quota). Nothing persists across pod restarts. |
| workspace.size | string | `"1Gi"` | emptyDir sizeLimit for the workspace. |