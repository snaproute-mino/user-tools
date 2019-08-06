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
{{- $_ := set $vminfo "topologyname" $.Release.Name -}}
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
    local switch_name=${1:-}
    local switch_ip=${2:-}
    local switch_ssh_port=${3:-}
    local switch_api_port=${4:-}

    if [[ "${switch_name}" == "" ]]; then
        >&2 echo "switch_name must be provided as first argument"
        return 1
    fi
    if [[ "${switch_ip}" == "" ]]; then
        >&2 echo "switch_ip must be provided as second argument"
        return 1
    fi
    if [[ "${switch_ssh_port}" == "" ]]; then
        switch_ssh_port=22
    fi

    local cache=~/.snapl
    local ignore_ssh="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    if [[ "${UPDATE_KUBECONFIG:-}" == "" ]]; then
        local UPDATE_KUBECONFIG=true
    fi
    local user="root"
    if [[ "${TARGET_USER:-}" != "" ]]; then
        user=$TARGET_USER
    fi
    local password=""
    if [[ "${TARGET_PASSWORD:-}" != "" ]]; then
        password=$TARGET_PASSWORD
    fi
    local kubepath="/mnt/state/kubernetes/admin.conf"
    if [[ "${TARGET_KUBEPATH:-}" != "" ]]; then
        kubepath=$TARGET_KUBEPATH
    fi

    local target_path=${cache}/${switch_ip}-${switch_ssh_port}
    local target=${target_path}/admin.conf
    if [[ "${CLEANUP:-}" == "true" ]]; then
        rm -rf ${target_path} &> /dev/null
    else
        nc -z ${switch_ip} ${switch_ssh_port} &> /dev/null
        if [[ "$?" != "0" ]]; then
            >&2 echo "${switch_ip} is not reachable on ssh port (${switch_ssh_port}).  Check that the device is running."
            return 1
        fi
        mkdir -p ${cache}/${switch_ip}-${switch_ssh_port}

        if [[ "${SKIP_COPY:-}" == "" || "${SKIP_COPY:-}" == "false" ]]; then
            export SSHPASS=${password}
            local cmd="sshpass -e scp -P ${switch_ssh_port} ${ignore_ssh} ${user}@${switch_ip}:${kubepath} ${target}"
            if [[ "${KUBECONFIG_DEBUG:-}" == "true" ]]; then
                >&2 echo "${cmd}"
            fi
            local cmd_output=$(${cmd})
            if [[ "$?" != "0" ]]; then
                >&2 echo "could not copy kubeconfig from ${switch_ip}:${kubepath} to ${target}.  Check that the device bootstrapping is complete."
                >&2 echo "error:"
                >&2 echo "${cmd_output}"
                return 1
            fi
        fi

        local api_port=$(cat $target | egrep -o "server: .*" | sed 's#.*:##')
        if [[ "${switch_api_port}" == "" ]]; then
            switch_api_port=${api_port}
        fi

        sed -i 's/certificate-authority-data:.*/insecure-skip-tls-verify: true/' $target &> /dev/null
        sed -i "s#server: .*#server: https://${switch_ip}:${switch_api_port}#" ${target} &> /dev/null
    fi

    >&2 echo "Updated kubeconfig profile at $target"

    local cluster_name=${switch_name}
    local context_name=admin@${cluster_name}
    local credentials_name=${context_name}
    local default_kubeconfig=~/.kube/config

    KUBECONFIG=${default_kubeconfig} kubectl config delete-cluster ${cluster_name} &> /dev/null || true
    KUBECONFIG=${default_kubeconfig} kubectl config unset users.${credentials_name} &> /dev/null || true
    KUBECONFIG=${default_kubeconfig} kubectl config delete-context ${context_name} &> /dev/null || true

    if [[ "${CLEANUP:-}" == "true" ]]; then
        >&2 echo "Removed cluster/credentials/context in kubeconfig: ${default_kubeconfig}"
        return 1
    fi

    KUBECONFIG=${default_kubeconfig} kubectl config set-cluster ${cluster_name} --server=https://${switch_ip}:${switch_api_port} --insecure-skip-tls-verify=true &> /dev/null

    KUBECONFIG=${default_kubeconfig} kubectl config set-credentials ${credentials_name} &> /dev/null
    KUBECONFIG=${default_kubeconfig} kubectl config set users."${credentials_name}".client-certificate-data \
        $(KUBECONFIG=$target kubectl config view -o jsonpath='{.users[?(@.name == "kubernetes-admin")].user.client-certificate-data}' --raw=true) \
        &> /dev/null
    KUBECONFIG=${default_kubeconfig} kubectl config set users."${credentials_name}".client-key-data \
        $(KUBECONFIG=$target kubectl config view -o jsonpath='{.users[?(@.name == "kubernetes-admin")].user.client-key-data}' --raw=true) \
        &> /dev/null

    KUBECONFIG=${default_kubeconfig} kubectl config set-context ${context_name} \
        --cluster ${cluster_name} \
        --user ${credentials_name} \
        &> /dev/null

    >&2 echo "Updated cluster/credentials/context in kubeconfig: ${default_kubeconfig}"
    >&2 echo "context: ${context_name}"
    >&2 echo "cluster: ${cluster_name}"
    >&2 echo "credentials: ${credentials_name}"
    >&2 echo
    >&2 echo "kubectl config use-context ${context_name}"
}

function topology-kubeconfig-update() {
    NAMESPACE=${1:-}
    TOPOLOGY=${2:-}
    VM_NAME=${3:-}

    if [[ "${VM_NAME}" == "" ]]; then
        VMS=$(kubectl get vms -l "snaproute.com/topology=${TOPOLOGY}" -o="jsonpath={.items[*].metadata.name}")
    else
        VMS=$VM_NAME
    fi

    >&2 echo "topology-kubeconfig-update: retrieving kubeconfigs for namespace: ${NAMESPACE}, vms: ${VMS}"
    for vm in $VMS; do
        serviceinfo-update "${NAMESPACE}" "${vm}"
        kubeconfig-update "${vm}" "${SERVICE_IP}" "${SSH_PORT}" "${API_PORT}"
        RET=$?
        if [[ ${RET} -ne 0 ]]; then
            return ${RET}
        fi
    done

    return 0
}

function topology-kubefed-join() {
    HOST_CLUSTER_CONTEXT=${1:-}
    NAMESPACE=${2:-}
    TOPOLOGY=${3:-}
    VM_NAME=${4:-}

    if [[ "${VM_NAME}" == "" ]]; then
        VMS=$(kubectl get vms -l "snaproute.com/topology=${TOPOLOGY}" -o="jsonpath={.items[*].metadata.name}")
    else
        VMS=$VM_NAME
    fi
    HOST_CLUSTER_VM="${TOPOLOGY}-ubuntu"
    >&2 echo "topology-kubefed-join: joining cnnos nodes for namespace: ${NAMESPACE}, vms: ${VMS}"
    for vm in $VMS; do
        if [[ "$vm" == "${HOST_CLUSTER_VM}" ]]; then
            continue
        fi

        kubefedctl join \
        ${vm} \
        --cluster-context=admin@${vm} \
        --host-cluster-context=${HOST_CLUSTER_CONTEXT} \
        --host-cluster-name=cnnos-cluster

        RET=$?
        if [[ ${RET} -ne 0 ]]; then
            return ${RET}
        fi
    done

    return 0
}


function topology-health() {
    NAMESPACE=${1:-}
    TOPOLOGY=${2:-}
    VM_NAME=${3:-}

    if [[ "${VM_NAME}" == "" ]]; then
        VMS=$(kubectl get vms -l "snaproute.com/topology=${TOPOLOGY}" -o="jsonpath={.items[*].metadata.name}")
    else
        VMS=$VM_NAME
    fi

    >&2 echo "topology-health: checking namespace: ${NAMESPACE}, vms: ${VMS}"
    for vm in $VMS; do
        node-health "${NAMESPACE}" "${vm}"
        RET=$?
        if [[ ${RET} -ne 0 ]]; then
            return ${RET}
        fi
    done

    return 0
}

function node-health() {
    NAMESPACE=${1:-}
    VM_NAME=${2:-}

    serviceinfo-update "${NAMESPACE}" "${VM_NAME}"
    >&2 echo "node-health: checking ${NAMESPACE}/${VM_NAME} at https://${SERVICE_IP}:${API_PORT}/healthz"
    RESP=$(curl -kf https://${SERVICE_IP}:${API_PORT}/healthz)
    RET=$?
    if [[ ${RET} -ne 0 || "$RESP" != "ok" ]]; then
        return 1
    else
        return 0
    fi
}

function topology-wait-health() {
    NAMESPACE=${1:-}
    TOPOLOGY=${2:-}
    VM_NAME=${3:-}

    if [[ "${WAIT_TIME:-}" == "" ]]; then
        WAIT_TIME="300"
    fi
    if [[ "${INTERVAL:-}" == "" ]]; then
        INTERVAL="10"
    fi

    iterations=$(( WAIT_TIME / INTERVAL ))
    i="0"
    cluster_healthy=false
    while [[ $i -lt ${iterations} ]]; do
        i=$[$i+1]
        echo "waiting for cnnos nodes to come online"
        set +e
        topology-health "${NAMESPACE}" "${TOPOLOGY}"
        RET=$?
        set -e
        if [[ ${RET} -eq 0 ]]; then
            cluster_healthy=true
            break
        fi
        sleep ${INTERVAL}
    done

    if [[ "${cluster_healthy}" == "true" ]]; then
        echo "cluster is healthy"
    else
        echo "cnnos nodes are not healthy (apiserver not reachable on all nodes)"
        return 1
    fi
    
    return 0
}

{{ end -}}
