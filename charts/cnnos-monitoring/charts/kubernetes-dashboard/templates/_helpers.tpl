{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "kubernetes-dashboard.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" | lower -}}
{{- end -}}

{{- define "kubernetes-dashboard.metricsName" -}}
{{- default (printf "%s-%s" .Chart.Name "metrics") .Values.metricsnameOverride | trunc 63 | trimSuffix "-" | lower -}}
{{- end -}}

{{- define "kubernetes-dashboard.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else -}}
{{- template "kubernetes-dashboard.fullname" . }}
{{- end -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "kubernetes-dashboard.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" | lower -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" | lower -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" | lower -}}
{{- end -}}
{{- end -}}
{{- end -}}


{{- define "kubernetes-dashboard.metricsFullName" -}}
{{- if .Values.fullnameOverride -}}
{{- printf "%s-%s" .Values.fullnameOverride "metrics" | trunc 63 | trimSuffix "-" | lower -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- printf "%s-%s" .Release.Name "metrics" | trunc 63 | trimSuffix "-" | lower -}}
{{- else -}}
{{- printf "%s-%s-%s" .Release.Name $name "metrics" | trunc 63 | trimSuffix "-" | lower -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kubernetes-dashboard.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Defining image based on the global registry value from toplevel charts values.yaml file
*/}}
{{- define "kubernetes-dashboard.image" -}}
{{- $hostreg := dict "value" .Values.dashboard.imageInfo.registry -}}
{{- $force := default false .Values.dashboard.imageInfo.force -}}
{{- if .Values.global -}}
{{- if and .Values.global.registry (eq $force false) -}}
{{- $_ := set $hostreg "value" .Values.global.registry -}}
{{- end -}}
{{- end -}}
{{- if .Values.dashboard.image -}}
{{ .Values.dashboard.image }}
{{- else -}}
{{ $hostreg.value }}/{{ .Values.dashboard.imageInfo.repository }}:{{ .Values.dashboard.imageInfo.tag }}
{{- end -}}
{{- end -}}

{{/*
Defining image based on the global registry value from toplevel charts values.yaml file
*/}}
{{- define "kubernetes-dashboard.metricsImage" -}}
{{- $hostreg := dict "value" .Values.metrics.imageInfo.registry -}}
{{- $force := default false .Values.metrics.imageInfo.force -}}
{{- if .Values.global -}}
{{- if and .Values.global.registry (eq $force false) -}}
{{- $_ := set $hostreg "value" .Values.global.registry -}}
{{- end -}}
{{- end -}}
{{- if .Values.metrics.image -}}
{{ .Values.metrics.image }}
{{- else -}}
{{ $hostreg.value }}/{{ .Values.metrics.imageInfo.repository }}:{{ .Values.metrics.imageInfo.tag }}
{{- end -}}
{{- end -}}