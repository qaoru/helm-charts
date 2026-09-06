{{/*
Chart name and version as used in the chart label.
*/}}
{{- define "open-terminal.chart" -}}
{{- printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Workstation resource name: `open-terminal-<name>`. Used for the StatefulSet,
the ClusterIP Service (replicaCount == 1) and as the base of the headless
governing Service (`<name>-h`). The `name` is taken from the instance entry, so
each workstation's DNS name is stable and independent of the release name -- the
admin registers `http://open-terminal-<name>:8000` once in Open WebUI.
*/}}
{{- define "open-terminal.workstationName" -}}
{{- printf "open-terminal-%s" .inst.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels for a workstation.
*/}}
{{- define "open-terminal.workstationLabels" -}}
helm.sh/chart: {{ include "open-terminal.chart" . }}
{{ include "open-terminal.workstationSelectorLabels" . }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/part-of: open-terminal
{{- end -}}

{{/*
Selector labels for a workstation. The custom `open-terminal.qaoru.fr/workstation`
label makes each workstation's pods selectable independently of the others,
which the per-instance Services and CiliumNetworkPolicy rely on.
*/}}
{{- define "open-terminal.workstationSelectorLabels" -}}
app.kubernetes.io/name: open-terminal
app.kubernetes.io/instance: {{ .root.Release.Name }}
open-terminal.qaoru.fr/workstation: {{ .inst.name | quote }}
{{- end -}}