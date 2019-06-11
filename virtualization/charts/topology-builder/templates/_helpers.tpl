{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "current.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "current.fullname" -}}
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
{{- define "current.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}


{{- define "topology-builder.readme" -}}
{{- $vms := dict -}}
{{ range $name, $vm := .Values.vms }}
{{- $vminfo := dict }}
{{- $vmname := printf "%s-%s" $.Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- $_ := set $vminfo "vmname" $vmname }}
{{- $_ := set $vminfo "namespace" $.Release.Namespace }}
{{- $_ := set $vminfo "releasename" $.Release.Name -}}
{{- $_ := set $vms $vmname $vminfo -}}
{{- end -}}
{{- $info := dict -}}
{{- $_ := set $info "vms" $vms -}}
{{- $_ := set $info "namespace" $.Release.Namespace }}
{{- $_ := set $info "releasename" $.Release.Name -}}
{{- $_ := set $info "configmapname" (printf "%s-%s" .Release.Name "topology" | trunc 63 | trimSuffix "-" ) -}}
{{- $bold := "\x1b[1m" }}
{{- $normal := "\x1b[0m" }}
{{- $blue := "\x1b[34m" }}
{{- $red := "\x1b[31m" }}
{{- $nocolor := "\x1b[0m" }}
# Topology Information for {{ $info.releasename }}
## Accessing README
{{ $bold }}{{ $blue }}kubectl --namespace {{ $info.namespace }} get configmap {{ $info.configmapname }} -o='go-template={{`{{` }} index .data "README.MD" {{ `}}`}}'{{ $nocolor }}{{ $normal }}

## Overall Topology
### Controlling VMS
Start all:
{{ $bold }}{{ $blue }}eval "`kubectl --namespace {{ $info.namespace }} get configmap {{ $info.configmapname }} -o='go-template={{ `{{` }}index .data "topology-helper.sh"{{ `}}` }}'`"{{ $nocolor }}{{ $normal }}
{{ $bold }}{{ $blue }}vm-topology start {{ $info.namespace }} {{ $info.releasename }}{{ $nocolor }}{{ $normal }}

Stop all:
{{ $bold }}{{ $blue }}eval "`kubectl --namespace {{ $info.namespace }} get configmap {{ $info.configmapname }} -o='go-template={{ `{{` }}index .data "topology-helper.sh"{{ `}}` }}'`"{{ $nocolor }}{{ $normal }}
{{ $bold }}{{ $blue }}vm-topology stop {{ $info.namespace }} {{ $info.releasename }}{{ $nocolor }}{{ $normal }}

Restart all:
{{ $bold }}{{ $blue }}eval "`kubectl --namespace {{ $info.namespace }} get configmap {{ $info.configmapname }} -o='go-template={{ `{{` }}index .data "topology-helper.sh"{{ `}}` }}'`"{{ $nocolor }}{{ $normal }}
{{ $bold }}{{ $blue }}vm-topology restart {{ $info.namespace }} {{ $info.releasename }}{{ $nocolor }}{{ $normal }}

### Update all kubeconfig contexts for all VMS
{{ $bold }}{{ $blue }}eval "`kubectl --namespace {{ $info.namespace }} get configmap {{ $info.configmapname }} -o='go-template={{ `{{` }}index .data "topology.updatekubeconfigs"{{ `}}` }}'`"{{ $nocolor }}{{ $normal }}

### Remove all kubeconfig contexts for all VMS
{{ $bold }}{{ $blue }}eval "`kubectl --namespace {{ $info.namespace }} get configmap {{ $info.configmapname }} -o='go-template={{ `{{` }}index .data "topology.cleanupkubeconfigs"{{ `}}` }}'`"{{ $nocolor }}{{ $normal }}

## Nodes

{{- range $name, $vm := $vms }}
{{- $vmname := $vm.vmname }}
### {{ $vmname }}

#### VM control
Start:
{{ $bold }}{{ $blue }}virtctl start {{ $vm.vmname }}{{ $nocolor }}{{ $normal }}
Stop:
{{ $bold }}{{ $blue }}virtctl stop {{ $vm.vmname }}{{ $nocolor }}{{ $normal }}
Console:
{{ $bold }}{{ $blue }}virtctl console {{ $vm.vmname }}{{ $nocolor }}{{ $normal }}

#### VM debugging
VM Status:
{{ $bold }}{{ $blue }}kubectl describe vm {{ $vm.vmname }}{{ $nocolor }}{{ $normal }}
VMI Status:
{{ $bold }}{{ $blue }}kubectl describe vmi -l "snaproute.com/device-name={{ $vm.vmname }}"{{ $nocolor }}{{ $normal }}
VMI Pod:
{{ $bold }}{{ $blue }}kubectl describe pod -l "snaproute.com/device-name={{ $vm.vmname }}"{{ $nocolor }}{{ $normal }}

#### Environment script (can be sourced to change current KUBECONFIG)
{{ $bold }}{{ $blue }}eval "`kubectl --namespace {{ $info.namespace }} get configmap {{ $info.configmapname }} -o='go-template={{ `{{` }}index .data "{{ $vm.vmname }}.env"{{ `}}` }}'`"{{ $nocolor }}{{ $normal }}
{{ $bold }}{{ $blue }}serviceinfo-update "{{ .namespace }}" "{{ .vmname }}"{{ $nocolor }}{{ $normal }}

{{ $bold }}{{ $blue }}export SERVICE_IP=${SERVICE_IP}{{ $nocolor }}{{ $normal }}
{{ $bold }}{{ $blue }}export API_PORT=${API_PORT}{{ $nocolor }}{{ $normal }}
{{ $bold }}{{ $blue }}export SSH_PORT=${SSH_PORT}{{ $nocolor }}{{ $normal }}

#### SSH to switch
{{ $bold }}{{ $blue }}eval "`kubectl --namespace {{ .namespace }} get configmap {{ $vm.configmapname }} -o='go-template={{ `{{` }}index .data "topology-helper.sh"{{ `}}` }}'`"{{ $nocolor }}{{ $normal }}
{{ $bold }}{{ $blue }}serviceinfo-update "{{ $vm.namespace }}" "{{ $vm.vmname }}"{{ $nocolor }}{{ $normal }}
{{ $bold }}{{ $blue }}ssh root@${SERVICE_IP} -p ${SSH_PORT}{{ $nocolor }}{{ $normal }}

#### API access to switch (available after ONIE installation of CNNOS completes)
{{ $bold }}{{ $blue }}eval "`kubectl --namespace {{ .namespace }} get configmap {{ $info.configmapname }} -o='go-template={{ `{{` }}index .data "{{ $vm.vmname }}.env"{{ `}}` }}'`"{{ $nocolor }}{{ $normal }}
{{ $bold }}{{ $blue }}kubectl config set-context {{ $vmname }} --cluster {{ $vmname }} --user admin@{{ $vmname }}{{ $nocolor }}{{ $normal }}
{{ end }}
{{ end -}}

{{- define "topology-builder.node.env" -}}
#!/bin/bash
# source this file for ease of updating your kubeconfig with context to the target device
eval "`kubectl --namespace {{ .namespace }} get configmap {{ .configmapname }} -o='go-template={{ `{{` }}index .data "topology-helper.sh"{{ `}}` }}'`"
NAMESPACE="{{ .namespace }}"
VM_NAME="{{ .vmname }}"
serviceinfo-update "${NAMESPACE}" "${VM_NAME}"
kubeconfig-update "${VM_NAME}" "${SERVICE_IP}" "${SSH_PORT}" "${API_PORT}"
{{ end -}}

{{- define "topology-builder.topology.updatekubeconfigs" -}}
#!/bin/bash
# source this file for ease of updating your kubeconfig with contexts of all vm nodes
eval "`kubectl --namespace {{ .namespace }} get configmap {{ .configmapname }} -o='go-template={{ `{{` }}index .data "topology-helper.sh"{{ `}}` }}'`"

{{ range $_, $vm := .vms }}
NAMESPACE="{{ $vm.namespace }}"
VM_NAME="{{ $vm.vmname }}"
serviceinfo-update "${NAMESPACE}" "${VM_NAME}"
kubeconfig-update "${VM_NAME}" "${SERVICE_IP}" "${SSH_PORT}" "${API_PORT}"

{{ end }}

{{ end -}}

{{- define "topology-builder.topology.cleanupkubeconfigs" -}}
#!/bin/bash
# source this file for ease of updating your kubeconfig with contexts of all vm nodes
eval "`kubectl --namespace {{ .namespace }} get configmap {{ .configmapname }} -o='go-template={{ `{{` }}index .data "topology-helper.sh"{{ `}}` }}'`"

{{ range $_, $vm := .vms }}
NAMESPACE="{{ $vm.namespace }}"
VM_NAME="{{ $vm.vmname }}"
serviceinfo-update "${NAMESPACE}" "${VM_NAME}"
CLEANUP=true kubeconfig-update "${VM_NAME}" "${SERVICE_IP}" "${SSH_PORT}" "${API_PORT}"

{{ end }}

{{ end -}}


{{- define "topology-builder.kubeconfigupdate" -}}
function vm-topology() {
    HELP="\
    usage:
      $0 <start|stop|restart|console> <namespace> <topology-name> \
      or \
      $0 <start|stop|restart|console> <namespace> <topology-name> <vm> \
    "
    ACTION=$1
    shift
    NAMESPACE=$1
    shift
    TOPOLOGY=$1
    shift
    VM=$1
    shift

    if [[ -z "${ACTION}" ]]; then
        >&2 echo "${HELP}"
        >&2 echo "missing action of either start, stop, restart, console"
    fi
    if [[ -z "${NAMESPACE}" ]]; then
        >&2 echo "${HELP}"
        >&2 echo "missing namespace"
    fi
    if [[ -z "${TOPOLOGY}" ]]; then
        >&2 echo "${HELP}"
        >&2 echo "missing topology-name"
    fi

    if [[ "$VM" == "" ]]; then
        VMS=$(kubectl get vms -l "snaproute.com/topology=${TOPOLOGY}" -o="jsonpath={.items[*].metadata.name}")
    else
        VMS=$VM
    fi

    case $ACTION in
    start)
        ;;
    stop)
        ;;
    restart)
        ;;
    console)
        ;;
    *)
        >&2 echo "invalid action"
        exit 1
        ;;
    esac

    for vm in $VMS; do
        virtctl --namespace ${NAMESPACE} ${ACTION} ${vm}
    done
}

function serviceinfo-update() {
    NAMESPACE=$1
    shift
    SERVICE_NAME=$1
    shift
    SERVICE_TYPE=$(kubectl --namespace ${NAMESPACE} get services ${SERVICE_NAME} -o jsonpath="{.spec.type}")

    if [[ "${SERVICE_TYPE}" == "NodePort" ]]; then
        SERVICE_IP=$(kubectl --namespace ${NAMESPACE} get pods ${SERVICE_NAME} -o jsonpath="{.status.hostIP}")
        API_PORT=$(kubectl --namespace ${NAMESPACE} get services ${SERVICE_NAME} -o jsonpath="{.spec.ports[?(@.name=='kube-api')].nodePort}")
        SSH_PORT=$(kubectl --namespace ${NAMESPACE} get services ${SERVICE_NAME} -o jsonpath="{.spec.ports[?(@.name=='ssh')].nodePort}")
    else
        CLUSTER_IP=$(kubectl --namespace ${NAMESPACE} get services ${SERVICE_NAME} -o jsonpath="{.spec.clusterIP}")
        SERVICE_IP=$(kubectl --namespace ${NAMESPACE} get services ${SERVICE_NAME} -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
        API_PORT=$(kubectl --namespace ${NAMESPACE} get services ${SERVICE_NAME} -o jsonpath="{.spec.ports[?(@.name=='kube-api')].port}")
        SSH_PORT=$(kubectl --namespace ${NAMESPACE} get services ${SERVICE_NAME} -o jsonpath="{.spec.ports[?(@.name=='ssh')].port}")
    fi
    >&2 echo "updated service variables - SERVICE_IP ${SERVICE_IP}, API_PORT=${API_PORT}, SSH_PORT=${SSH_PORT}"
}

function kubeconfig-update() {
    CACHE=~/.snapl
    IGNORE_SSH="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    if [[ -z "${UPDATE_KUBECONFIG}" ]]; then
        UPDATE_KUBECONFIG=true
    fi

    USER="root"
    if [[ -n $TARGET_USER ]]; then
        USER=$TARGET_USER
    fi
    PASSWORD=""
    if [[ -n $TARGET_PASSWORD ]]; then
        PASSWORD=$TARGET_PASSWORD
    fi
    KUBEPATH="/mnt/state/kubernetes/admin.conf"
    if [[ -n $TARGET_KUBEPATH ]]; then
        KUBEPATH=$TARGET_KUBEPATH
    fi

    # function arguments
    SWITCH_NAME=$1
    if [[ "${SWITCH_NAME}" == "" ]]; then
        >&2 echo "SWITCH_NAME must be provided as first argument"
        return 1
    fi
    shift

    SWITCH_IP=$1
    if [[ "${SWITCH_IP}" == "" ]]; then
        >&2 echo "SWITCH_IP must be provided as second argument"
        return 1
    fi
    shift

    SWITCH_SSH_PORT=$1
    if [[ "${SWITCH_SSH_PORT}" == "" ]]; then
        SWITCH_SSH_PORT=22
    fi
    shift

    SWITCH_API_PORT=$1
    shift

    TARGET_PATH=${CACHE}/${SWITCH_IP}-${SWITCH_SSH_PORT}
    TARGET=${TARGET_PATH}/admin.conf
    if [[ "${CLEANUP}" == "true" ]]; then
        rm -rf ${TARGET_PATH} &> /dev/null
    else
        nc -z ${SWITCH_IP} ${SWITCH_SSH_PORT} &> /dev/null
        if [[ "$?" != "0" ]]; then
            >&2 echo "${SWITCH_IP} is not reachable on ssh port (${SWITCH_SSH_PORT}).  Check that the device is running."
            return 1
        fi
        mkdir -p ${CACHE}/${SWITCH_IP}-${SWITCH_SSH_PORT}

        if [[ ! ${SKIP_COPY} ]]; then
            CMD="sshpass -p \"${PASSWORD}\" scp -P ${SWITCH_SSH_PORT} ${IGNORE_SSH} ${USER}@${SWITCH_IP}:${KUBEPATH} ${TARGET}"
            if [[ $KUBECONFIG_DEBUG ]]; then
                >&2 echo "${CMD}"
            fi
            CMD_OUTPUT=$(${CMD})
            if [[ "$?" != "0" ]]; then
                >&2 echo "could not copy kubeconfig from ${SWITCH_IP}:${KUBEPATH} to ${TARGET}.  Check that the device bootstrapping is complete."
                >&2 echo "error:"
                >&2 echo "${CMD_OUTPUT}"
                return 1
            fi
        fi

        local api_port=$(cat $TARGET | egrep -o "server: .*" | sed 's#.*:##')
        if [[ "${SWITCH_API_PORT}" == "" ]]; then
            SWITCH_API_PORT=${api_port}
        fi

        sed -i 's/certificate-authority-data:.*/insecure-skip-tls-verify: true/' $TARGET &> /dev/null
        sed -i "s#server: .*#server: https://${SWITCH_IP}:${SWITCH_API_PORT}#" ${TARGET} &> /dev/null
    fi

    >&2 echo "Updated kubeconfig profile at $TARGET"

    CLUSTER_NAME=${SWITCH_NAME}
    CONTEXT_NAME=admin@${CLUSTER_NAME}
    CREDENTIALS_NAME=${CONTEXT_NAME}
    DEFAULT_KUBECONFIG=~/.kube/config

    KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config delete-cluster ${CLUSTER_NAME} &> /dev/null || true
    KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config unset users.${CREDENTIALS_NAME} &> /dev/null || true
    KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config delete-context ${CONTEXT_NAME} &> /dev/null || true

    if [[ "${CLEANUP}" == "true" ]]; then
        >&2 echo "Removed cluster/credentials/context in kubeconfig: ${DEFAULT_KUBECONFIG}"
        return 1
    fi

    KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config set-cluster ${CLUSTER_NAME} --server=https://${SWITCH_IP}:${SWITCH_API_PORT} --insecure-skip-tls-verify=true &> /dev/null

    KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config set-credentials ${CREDENTIALS_NAME} &> /dev/null
    KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config set users."${CREDENTIALS_NAME}".client-certificate-data \
        $(KUBECONFIG=$TARGET kubectl config view -o jsonpath='{.users[?(@.name == "kubernetes-admin")].user.client-certificate-data}' --raw=true) \
        &> /dev/null
    KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config set users."${CREDENTIALS_NAME}".client-key-data \
        $(KUBECONFIG=$TARGET kubectl config view -o jsonpath='{.users[?(@.name == "kubernetes-admin")].user.client-key-data}' --raw=true) \
        &> /dev/null

    KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config set-context ${CONTEXT_NAME} \
        --cluster ${CLUSTER_NAME} \
        --user ${CREDENTIALS_NAME} \
        &> /dev/null

    >&2 echo "Updated cluster/credentials/context in kubeconfig: ${DEFAULT_KUBECONFIG}"
    >&2 echo "context: ${CONTEXT_NAME}"
    >&2 echo "cluster: ${CLUSTER_NAME}"
    >&2 echo "credentials: ${CREDENTIALS_NAME}"
    >&2 echo
    echo "kubectl config use-context ${CONTEXT_NAME}"
    >&2 echo
}
{{ end -}}
