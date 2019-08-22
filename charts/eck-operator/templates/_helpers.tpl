{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "eck-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "eck-operator.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "eck-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create the image variable
*/}}
{{- define "eck-operator.image" -}}
{{- $eck := dict "value" "" -}}
{{- if .Values.imageInfo }}
{{- $_ := set $eck "value" .Values.imageInfo.registry -}}
{{- $force := default false .Values.imageInfo.force -}}
{{- if .Values.global -}}
{{- if and .Values.global.registry (eq $force false) -}}
{{- $_ := set $eck "value" .Values.global.registry -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if .Values.image -}}
{{ .Values.image }}
{{- else -}}
{{- if not (eq $eck.value "") -}}
{{ $eck.value }}/
{{- end -}}
{{ .Values.imageInfo.repository }}:{{ .Values.imageInfo.tag }}
{{- end -}}
{{- end -}}