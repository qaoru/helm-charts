{{/*
Common name. Uses the chart name so the Service DNS name (`open-terminal`) is
stable regardless of the release name -- Open WebUI points at
`http://open-terminal:8000`. Override with `.Values.nameOverride` if needed.
*/}}
{{- define "open-terminal.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "open-terminal.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "open-terminal.labels" -}}
helm.sh/chart: {{ include "open-terminal.chart" . }}
{{ include "open-terminal.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: open-terminal
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "open-terminal.selectorLabels" -}}
app.kubernetes.io/name: {{ include "open-terminal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}