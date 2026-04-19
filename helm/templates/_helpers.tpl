{{/*
ITL ControlPlane Helm — Template helpers
*/}}

{{/* Expand the name of the chart */}}
{{- define "itl-controlplane.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully qualified app name */}}
{{- define "itl-controlplane.fullname" -}}
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

{{/* Chart label */}}
{{- define "itl-controlplane.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels */}}
{{- define "itl-controlplane.labels" -}}
helm.sh/chart: {{ include "itl-controlplane.chart" . }}
{{ include "itl-controlplane.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: itl-controlplane
{{- end }}

{{/* Selector labels */}}
{{- define "itl-controlplane.selectorLabels" -}}
app.kubernetes.io/name: {{ include "itl-controlplane.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* ServiceAccount name */}}
{{- define "itl-controlplane.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "itl-controlplane.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Image helper — resolves tag and registry override */}}
{{- define "itl-controlplane.image" -}}
{{- $reg := .Values.global.imageRegistry | default "" }}
{{- $repo := .repository }}
{{- $tag  := .tag | default $.Values.image.tag | default "latest" }}
{{- if $reg }}
{{- printf "%s/%s:%s" $reg (last (splitList "/" $repo)) $tag }}
{{- else }}
{{- printf "%s:%s" $repo $tag }}
{{- end }}
{{- end }}

{{/* PostgreSQL connection URL */}}
{{- define "itl-controlplane.postgresUrl" -}}
postgresql://{{ .Values.postgresql.auth.username }}:$(POSTGRES_PASSWORD)@{{ .Release.Name }}-postgresql:5432/{{ .Values.postgresql.auth.database }}
{{- end }}

{{/* Neo4j bolt URL */}}
{{- define "itl-controlplane.neo4jUrl" -}}
bolt://{{ .Release.Name }}-neo4j:7687
{{- end }}

{{/* Redis URL */}}
{{- define "itl-controlplane.redisUrl" -}}
redis://:$(REDIS_PASSWORD)@{{ .Release.Name }}-redis-master:6379/0
{{- end }}

{{/* RabbitMQ AMQP URL */}}
{{- define "itl-controlplane.rabbitmqUrl" -}}
amqp://{{ .Values.rabbitmq.auth.username }}:$(RABBITMQ_PASSWORD)@{{ .Release.Name }}-rabbitmq:5672/
{{- end }}

{{/* Keycloak URL */}}
{{- define "itl-controlplane.keycloakUrl" -}}
http://{{ .Release.Name }}-keycloak:8080
{{- end }}

{{/* Ingress host helper */}}
{{- define "itl-controlplane.ingressHost" -}}
{{- $sub := index . 0 -}}
{{- $domain := index . 1 -}}
{{- if $sub -}}
{{- printf "%s.%s" $sub $domain -}}
{{- else -}}
{{- $domain -}}
{{- end -}}
{{- end }}
