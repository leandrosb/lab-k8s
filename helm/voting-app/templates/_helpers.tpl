{{/*
Nome base do chart.
*/}}
{{- define "voting-app.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Nome completo, prefixado pelo Release, para permitir múltiplas instalações
(ex.: staging e prod) no mesmo cluster sem colisão de nomes.
*/}}
{{- define "voting-app.fullname" -}}
{{- if .Release.Name -}}
{{- printf "%s-%s" .Release.Name (include "voting-app.name" .) | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "voting-app.name" . -}}
{{- end -}}
{{- end -}}

{{/*
Labels comuns aplicadas em todos os recursos.
*/}}
{{- define "voting-app.labels" -}}
app.kubernetes.io/part-of: {{ include "voting-app.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}
