{{/*
Expand the name of the chart.
*/}}
{{- define "foundry-local.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "foundry-local.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "foundry-local.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "foundry-local.labels" -}}
helm.sh/chart: {{ include "foundry-local.chart" . }}
{{ include "foundry-local.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "foundry-local.selectorLabels" -}}
app.kubernetes.io/name: {{ include "foundry-local.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Foundry selector labels
*/}}
{{- define "foundry-local.foundry.selectorLabels" -}}
{{ include "foundry-local.selectorLabels" . }}
app.kubernetes.io/component: foundry
{{- end }}

{{/*
Open WebUI selector labels
*/}}
{{- define "foundry-local.openwebui.selectorLabels" -}}
{{ include "foundry-local.selectorLabels" . }}
app.kubernetes.io/component: open-webui
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "foundry-local.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "foundry-local.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the namespace
*/}}
{{- define "foundry-local.namespace" -}}
{{- if .Values.namespaceOverride }}
{{- .Values.namespaceOverride }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Detect deployment type based on explicit override, model name, and BYO configuration
*/}}
{{- define "foundry-local.foundry.type" -}}
{{- if .Values.foundry.deploymentType -}}
{{/* Use explicit deployment type override */}}
{{- .Values.foundry.deploymentType -}}
{{- else if .Values.foundry.byo.enabled -}}
{{/* Auto-detect for BYO deployments based on model pattern */}}
{{- if or (contains "gpu" .Values.foundry.model) (contains "cuda" .Values.foundry.model) (regexMatch ".*:(7b|8b|13b|70b)" .Values.foundry.model) -}}
gpu-oras
{{- else -}}
cpu-oras
{{- end -}}
{{- else if or (contains "gpu" .Values.foundry.model) (contains "cuda" .Values.foundry.model) (regexMatch ".*:(7b|8b|13b|70b)" .Values.foundry.model) -}}
{{/* Auto-detect for catalog deployments */}}
gpu
{{- else -}}
cpu
{{- end -}}
{{- end -}}

{{/*
Foundry image
*/}}
{{- define "foundry-local.foundry.image" -}}
{{- $type := include "foundry-local.foundry.type" . -}}
{{- $imageConfig := index .Values.foundry.images $type -}}
{{- if .Values.global.imageRegistry }}
{{- printf "%s/%s:%s" .Values.global.imageRegistry $imageConfig.repository $imageConfig.tag }}
{{- else }}
{{- printf "%s:%s" $imageConfig.repository $imageConfig.tag }}
{{- end }}
{{- end }}

{{/*
Foundry resources based on detected type
*/}}
{{- define "foundry-local.foundry.resources" -}}
{{- $type := include "foundry-local.foundry.type" . -}}
{{- toYaml (index .Values.foundry.resources $type) }}
{{- end }}

{{/*
Foundry security context based on detected type
*/}}
{{- define "foundry-local.foundry.securityContext" -}}
{{- $type := include "foundry-local.foundry.type" . -}}
{{- toYaml (index .Values.foundry.securityContext $type) }}
{{- end }}

{{/*
Foundry environment variables based on detected type
*/}}
{{- define "foundry-local.foundry.envVars" -}}
{{- $type := include "foundry-local.foundry.type" . -}}
{{- $commonEnvVars := .Values.foundry.extraEnvVars | default list -}}
{{- $typeEnvVars := list -}}
{{- if eq $type "gpu" -}}
{{- $typeEnvVars = .Values.foundry.gpuEnvVars | default list -}}
{{- else if eq $type "gpu-oras" -}}
{{- $typeEnvVars = .Values.foundry.gpuOrasEnvVars | default list -}}
{{- else if eq $type "cpu" -}}
{{- $typeEnvVars = .Values.foundry.cpuEnvVars | default list -}}
{{- else if eq $type "cpu-oras" -}}
{{- $typeEnvVars = .Values.foundry.cpuOrasEnvVars | default list -}}
{{- end -}}
{{- $allEnvVars := concat $commonEnvVars $typeEnvVars -}}
{{- if $allEnvVars -}}
{{- toYaml $allEnvVars -}}
{{- else -}}
[]
{{- end -}}
{{- end }}

{{/*
Foundry node selector based on detected type
*/}}
{{- define "foundry-local.foundry.nodeSelector" -}}
{{- $type := include "foundry-local.foundry.type" . -}}
{{- $nodeSelector := dict -}}

{{/* Start with base nodeSelector */}}
{{- if or (eq $type "gpu") (eq $type "gpu-oras") -}}
{{- if .Values.foundry.gpu.nodeSelector -}}
{{- $nodeSelector = .Values.foundry.gpu.nodeSelector | deepCopy -}}
{{- end -}}
{{- else -}}
{{/* CPU and CPU-ORAS use the same node selector */}}
{{- if .Values.foundry.nodeSelector -}}
{{- $nodeSelector = .Values.foundry.nodeSelector | deepCopy -}}
{{- end -}}
{{- end -}}

{{/* Add global node selection if specified */}}
{{- if .Values.foundry.targetNode -}}
{{- $_ := set $nodeSelector "kubernetes.io/hostname" .Values.foundry.targetNode -}}
{{- end -}}

{{/* Add global nodeSelector overlay */}}
{{- if .Values.foundry.globalNodeSelector -}}
{{- range $key, $value := .Values.foundry.globalNodeSelector -}}
{{- $_ := set $nodeSelector $key $value -}}
{{- end -}}
{{- end -}}

{{- if $nodeSelector -}}
{{- toYaml $nodeSelector -}}
{{- else -}}
{}
{{- end -}}
{{- end }}

{{/*
OpenWebUI node selector with global overrides
*/}}
{{- define "foundry-local.openwebui.nodeSelector" -}}
{{- $nodeSelector := dict -}}

{{/* Start with OpenWebUI specific nodeSelector */}}
{{- if .Values.openWebUI.nodeSelector -}}
{{- $nodeSelector = .Values.openWebUI.nodeSelector | deepCopy -}}
{{- end -}}

{{/* Add global node selection if specified */}}
{{- if .Values.foundry.targetNode -}}
{{- $_ := set $nodeSelector "kubernetes.io/hostname" .Values.foundry.targetNode -}}
{{- end -}}

{{/* Add global nodeSelector overlay */}}
{{- if .Values.foundry.globalNodeSelector -}}
{{- range $key, $value := .Values.foundry.globalNodeSelector -}}
{{- $_ := set $nodeSelector $key $value -}}
{{- end -}}
{{- end -}}

{{- if $nodeSelector -}}
{{- toYaml $nodeSelector -}}
{{- else -}}
{}
{{- end -}}
{{- end }}

{{/*
Foundry tolerations based on detected type
*/}}
{{- define "foundry-local.foundry.tolerations" -}}
{{- $type := include "foundry-local.foundry.type" . -}}
{{- if or (eq $type "gpu") (eq $type "gpu-oras") -}}
{{- if .Values.foundry.gpu.tolerations -}}
{{- toYaml .Values.foundry.gpu.tolerations -}}
{{- else -}}
[]
{{- end -}}
{{- else -}}
{{/* CPU and CPU-ORAS use the same tolerations */}}
{{- if .Values.foundry.tolerations -}}
{{- toYaml .Values.foundry.tolerations -}}
{{- else -}}
[]
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Open WebUI image
*/}}
{{- define "foundry-local.openwebui.image" -}}
{{- printf "%s:%s" .Values.openWebUI.image.repository .Values.openWebUI.image.tag }}
{{- end }}

{{/*
Foundry service name
*/}}
{{- define "foundry-local.foundry.serviceName" -}}
{{- include "foundry-local.fullname" . }}-foundry
{{- end }}

{{/*
Open WebUI service name
*/}}
{{- define "foundry-local.openwebui.serviceName" -}}
{{- include "foundry-local.fullname" . }}-openwebui
{{- end }}

{{/*
Foundry deployment name
*/}}
{{- define "foundry-local.foundry.deploymentName" -}}
{{- include "foundry-local.fullname" . }}-foundry
{{- end }}

{{/*
Open WebUI deployment name
*/}}
{{- define "foundry-local.openwebui.deploymentName" -}}
{{- include "foundry-local.fullname" . }}-openwebui
{{- end }}