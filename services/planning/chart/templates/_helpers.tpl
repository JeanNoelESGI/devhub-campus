{{- define "planning.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "planning.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "planning.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "planning.labels" -}}
{{/* TODO : 4 labels obligatoires (cf. polycopié). */}}
{{- end -}}

{{- define "planning.selectorLabels" -}}
{{/* TODO : sélecteur stable. */}}
{{- end -}}
