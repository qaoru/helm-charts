# unifi

![Version: 1.0.2](https://img.shields.io/badge/Version-1.0.2-informational?style=flat-square)
![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)
![AppVersion: 10.3.58-ls128](https://img.shields.io/badge/AppVersion-10.3.58-ls128-informational?style=flat-square)

The unifi software is a powerful, enterprise wireless software engine ideal for high-density client deployments requiring low latency and high uptime performance.

Runs the [linuxserver/unifi-network-application](https://hub.docker.com/r/linuxserver/unifi-network-application) container as a StatefulSet with persistent storage and MongoDB integration.

## Prerequisites

- Kubernetes >= 1.21
- Helm >= 3.0
- A running MongoDB instance accessible from the cluster
- MongoDB admin credentials stored in a Kubernetes Secret

## Installation

### 1. Create MongoDB credentials secret

The chart requires a secret containing MongoDB admin credentials for the init container to create the UniFi database user:

```bash
kubectl create secret generic unifi-db-credentials \
  --from-literal=admin-username=<your-mongo-admin-user> \
  --from-literal=admin-password=<your-mongo-admin-password>
```

### 2. Install the chart

```bash
helm install unifi oci://ghcr.io/qaoru/helm-charts/unifi --version 1.0.2 \
  --set database.host=<your-mongodb-host> \
  --set database.credentials.generate=true
```

Or with a local `values.yaml`:

```bash
helm install unifi oci://ghcr.io/qaoru/helm-charts/unifi --version 1.0.2 -f values.yaml
```

## Configuration

### MongoDB

The chart uses an init container (`mongo:7.0`) to automatically create the `unifi` database user and grant `dbOwner` roles on the required databases (`unifi`, `unifi_stat`, `unifi_audit`).

| Parameter | Description | Default |
|-----------|-------------|---------|
| `database.host` | MongoDB host | `"mongodb"` |
| `database.port` | MongoDB port | `27017` |
| `database.dbName` | Database name | `unifi` |
| `database.authSource` | Authentication source | `admin` |
| `database.credentials.generate` | Generate a secret with a random password | `false` |
| `database.credentials.secretName` | Secret name for DB credentials | `"unifi-db-credentials"` |
| `database.initCredentials.secretName` | Secret name for admin credentials | `"unifi-db-credentials"` |

### Services

Two service configurations are available:

- **internal** (ClusterIP, enabled by default) — exposes only the HTTPS UI (port 8443)
- **public** (LoadBalancer, disabled by default) — exposes all UniFi ports (HTTP inform, guest HTTP/HTTPS, speedtest, STUN, discovery, syslog)

### Ingress

Ingress is disabled by default. When enabled, it routes to the internal service on port 8443. TLS can be configured via the `ingress.tls` list.

### Network Policies

Supports both standard Kubernetes `NetworkPolicy` and `CiliumNetworkPolicy` (mutually exclusive). Select the flavor via `networkPolicy.flavor`: `kubernetes` or `cilium`.

### Persistence

Data is persisted at `/config` via a StatefulSet `volumeClaimTemplate` (default 5Gi). Set `persistence.enabled: false` to use an `emptyDir` instead.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for pod scheduling |
| containerSecurityContext | string | `nil` | Security context for the main container (defaults to none) |
| database | object | `{"authSource":"admin","credentials":{"generate":false,"passwordKey":"password","secretName":"unifi-db-credentials","usernameKey":"username"},"dbName":"unifi","host":"mongodb","initCredentials":{"passwordKey":"admin-password","secretName":"unifi-db-credentials","usernameKey":"admin-username"},"initImage":{"pullPolicy":"IfNotPresent","repository":"mongo","tag":"7.0"},"port":27017}` | MongoDB connection settings |
| env | object | `{"PGID":"1000","PUID":"1000","TZ":"Europe/Paris"}` | Environment variables for the UniFi container |
| extraEnv | list | `[]` | Additional environment variables as a list of {name, value} objects |
| extraVolumeMounts | list | `[]` | Extra volume mounts for the main container |
| extraVolumes | list | `[]` | Extra volumes for the pod |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"linuxserver/unifi-network-application","tag":null}` | Image configuration |
| ingress | object | `{"annotations":{"server-ssl":"true"},"className":"","enabled":false,"hosts":[{"host":"unifi.example.com","paths":[{"path":"/","pathType":"Prefix"}]}],"tls":[]}` | Ingress configuration |
| initContainerResources | string | `nil` | Resources for the init container (defaults to none) |
| initContainerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}` | Security context for the init container |
| networkPolicy | object | `{"cilium":{"egress":[{"toFQDNs":[{"matchName":"fw-update.ubnt.com"},{"matchName":"fw-download.ubnt.com"}]},{"toEndpoints":[{"matchLabels":{"k8s:io.kubernetes.pod.namespace":"kube-system","k8s:k8s-app":"kube-dns"}}],"toPorts":[{"ports":[{"port":"53","protocol":"UDP"},{"port":"53","protocol":"TCP"}],"rules":{"dns":[{"matchName":"fw-update.ubnt.com"},{"matchName":"fw-download.ubnt.com"}]}}]}],"ingress":[{"toPorts":[{"ports":[{"port":"http-inform"}]}]}]},"egress":{},"enabled":false,"flavor":"kubernetes","ingress":[{"ports":[{"port":"http-inform","protocol":"TCP"}]}]}` | Network policy configuration |
| nodeSelector | object | `{}` | Node selector for pod scheduling |
| persistence | object | `{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":true,"size":"5Gi","storageClass":""}` | Persistence configuration for /config |
| podAnnotations | object | `{}` | Additional pod annotations |
| podLabels | object | `{}` | Additional pod labels |
| podPorts | object | `{"discovery":{"containerPort":10001,"protocol":"UDP"},"guest-http":{"containerPort":8880,"protocol":"TCP"},"guest-https":{"containerPort":8843,"protocol":"TCP"},"http-inform":{"containerPort":8080,"protocol":"TCP"},"https-ui":{"containerPort":8443,"protocol":"TCP"},"speedtest":{"containerPort":6789,"protocol":"TCP"},"stun":{"containerPort":3478,"protocol":"UDP"},"syslog":{"containerPort":5514,"protocol":"UDP"}}` | Container port definitions |
| podSecurityContext | object | `{"fsGroup":1000,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":1000,"runAsUser":0}` | Pod-level security context |
| probes | object | `{"liveness":{"enabled":true,"failureThreshold":6,"initialDelaySeconds":20,"periodSeconds":15,"timeoutSeconds":5},"readiness":{"enabled":true,"failureThreshold":12,"initialDelaySeconds":20,"periodSeconds":10,"timeoutSeconds":5}}` | Liveness and readiness probe configuration |
| replicaCount | int | `1` | Number of replicas |
| resources | object | `{"limits":{"memory":"2Gi"},"requests":{"cpu":"200m","memory":"256Mi"}}` | Resource requests and limits |
| revisionHistoryLimit | int | `3` | Number of revisions to keep in history |
| serviceAccount | object | `{"annotations":{},"automount":false,"create":true,"name":""}` | Service account configuration |
| services | object | `{"internal":{"annotations":{},"enablePorts":{"discovery":false,"guest-http":false,"guest-https":false,"http-inform":false,"https-ui":true,"speedtest":false,"stun":false,"syslog":false},"enabled":true,"loadBalancerIP":"","type":"ClusterIP"},"public":{"annotations":{},"enablePorts":{"discovery":true,"guest-http":true,"guest-https":true,"http-inform":true,"https-ui":false,"speedtest":true,"stun":true,"syslog":true},"enabled":false,"loadBalancerIP":"","type":"LoadBalancer"}}` | Service definitions |
| tolerations | list | `[]` | Tolerations for pod scheduling |
