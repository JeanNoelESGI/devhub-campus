{{- define "notif.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "notif.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "notif.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "notif.labels" -}}
{{/* TODO : 4 labels obligatoires. */}}
{{- end -}}

{{- define "notif.selectorLabels" -}}
{{/* TODO. */}}
{{- end -}}
