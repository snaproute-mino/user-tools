#!/bin/bash

set -euxo pipefail

function __set_variables {
    FAILED_VALIDATION=false

    OS=`uname | tr '[:upper:]' '[:lower:]'`
    OS_DISTRIBUTOR=`lsb_release -is`
    HOSTNAME=`hostname`
    DEFAULT_INTERFACE="$(awk '$2 == 00000000 { print $1 }' /proc/net/route)"
    DEFAULT_INTERFACE_IP=`ip addr show dev "${DEFAULT_INTERFACE}" | awk '$1 == "inet" && $3 == "brd" { sub("/.*", "", $2); print $2 }'`
    ADDITIONAL_FILES_PATH_PREPEND=""
    if [[ "${FULL_INSTALL:-}" == "" ]]; then
        FULL_INSTALL=false
    fi

    __set_bootstrapper_defaults
    __set_minikube_defaults
    __set_cluster_defaults
    __set_ha_defaults
    __set_kubernetes_defaults
    __set_cni_defaults
    __set_kubefed_defaults
    __set_kubevirt_defaults
    __set_metallb_defaults
    __set_helm_defaults
}

function sudocmd {
    CMD="$@"

    local OUTPUT=$(sudo bash -c "${CMD}")
    if [[ "$DEBUG" == "true" ]]; then
        echo "${OUTPUT}" 1>&2
    fi
}

### BOOTSTRAPPER CONFIGURATION

IFS='' read -r -d '\0' BOOTSTRAPPER_HELP <<"EOL"
DEBUG
  Description: specifies whether verbose logging should occur
  Default: ${DEFAULT_DEBUG}
  Example: DEBUG=true
  Current: DEBUG=${DEBUG}

BOOTSTRAPPER
  Description: specifies the bootstrapper to run (either minikube or kubeadm)
  Default: ${DEFAULT_BOOTSTRAPPER}
  Example: BOOTSTRAPPER=kubeadm
  Current: BOOTSTRAPPER=${BOOTSTRAPPER}

BOOTSTRAPPER_DOCKER_REGISTRY
  Description: specifies the docker registry to use by default for all required images (except k8s)
  Default: ${DEFAULT_BOOTSTRAPPER_DOCKER_REGISTRY}
  Example: BOOTSTRAPPER_DOCKER_REGISTRY=docker.io/snaproute
  Current: BOOTSTRAPPER_DOCKER_REGISTRY=${BOOTSTRAPPER_DOCKER_REGISTRY}

DEPENDENCIES_ONLY
  Description: specifies the host names to include in HA provisioning (required if KUBERNETES_CONTROLPLANE_ENDPOINT is set)
  Default: ${DEFAULT_DEPENDENCIES_ONLY}
  Example: DEPENDENCIES_ONLY=true
  Current: DEPENDENCIES_ONLY=${DEPENDENCIES_ONLY}
\0
EOL

function __set_bootstrapper_defaults {
    local DEFAULT_DEBUG=false
    local DEFAULT_BOOTSTRAPPER=minikube
    local DEFAULT_BOOTSTRAPPER_DOCKER_REGISTRY=repo.snaproute.com
    local DEFAULT_DEPENDENCIES_ONLY=false

    if [[ "${DEBUG:-}" == "" ]]; then
        DEBUG=${DEFAULT_DEBUG}
    fi
    if [[ "${BOOTSTRAPPER:-}" == "" ]]; then
        BOOTSTRAPPER=${DEFAULT_BOOTSTRAPPER}
    fi
    if [[ "${BOOTSTRAPPER_DOCKER_REGISTRY:-}" == "" ]]; then
        BOOTSTRAPPER_DOCKER_REGISTRY=${DEFAULT_BOOTSTRAPPER_DOCKER_REGISTRY}
    fi
    if [[ "${DEPENDENCIES_ONLY:-}" == "" ]]; then
        DEPENDENCIES_ONLY=${DEFAULT_DEPENDENCIES_ONLY}
    fi

    DEFAULTS_BOOTSTRAPPER=$( eval "echo -e \"${BOOTSTRAPPER_HELP//\"/\\\"}\"" )
}

### linux dependencies

function linux_kvm2_install {
    echo "Installing kvm2"
    sudocmd DEBIAN_FRONTEND=noninteractive \
        apt-get -yq install qemu-kvm libvirt-bin virtinst
    
    sudocmd systemctl enable libvirtd.service
    sudocmd systemctl start libvirtd.service
    set +e
    sudocmd groupadd libvirt
    set -e
    sudocmd usermod -a -G libvirt $(whoami)

    linux_kvm2_enable_nested_virtualization
}

function linux_kvm2_enable_nested_virtualization {
    echo "Enabling nested virtualization in kvm2"
    sudocmd modprobe -r kvm_intel
    sudocmd sed -i "s/#options kvm_intel nested=1/options kvm_intel nested=1/" /etc/modprobe.d/qemu-system-x86.conf
    sudocmd modprobe kvm_intel
}

function linux_docker_install {
    echo "Installing docker"

    sudocmd mkdir -p ${ADDITIONAL_FILES_PATH_PREPEND}/etc/docker/ || true
    sudocmd systemctl stop docker.service
    echo -e "${DOCKER_CONF}" | sudo tee ${ADDITIONAL_FILES_PATH_PREPEND}/etc/docker/daemon.json > /dev/null
    sudocmd DEBIAN_FRONTEND=noninteractive \
        apt-get -yq install docker.io

    sudocmd systemctl enable docker.service
    sudocmd systemctl start docker.service
    sudocmd groupadd docker || true
    sudocmd usermod -aG docker $(whoami) || true
}

IFS='' read -r -d '\0' DOCKER_CONF <<"EOL"
{
"exec-opts": ["native.cgroupdriver=systemd"],
"log-driver": "json-file",
"log-opts": {
"max-size": "100m"
},
"storage-driver": "overlay2"
}
\0
EOL

### darwin dependencies

function darwin_homebrew_install {
    if [[ ! -f $(which brew || true) || "${FULL_INSTALL}" == "true" ]]; then
        echo "Installing homebrew"
        /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi
    brew update > /dev/null
}

function darwin_virtualbox_install {
    if [[ ! -f $(which vboxmanage || true) || "${FULL_INSTALL}" == "true" ]]; then
        echo "Install virtualbox (may require approving permissions for kernel extensions)"
        brew cask install virtualbox
    fi
}

### CLUSTER CONFIGURATION

IFS='' read -r -d '\0' CLUSTER_HELP <<"EOL"
CLUSTER_CONTROLPLANE_ENDPOINT
  Description: specifies the IP:port for k8s cluster (must be set to intended VIP if deploying HA cluster)
  Default: ${DEFAULT_CLUSTER_CONTROLPLANE_ENDPOINT} (derived from default interface ip)
  Example: CLUSTER_CONTROLPLANE_ENDPOINT=172.17.0.1:443
  Current: CLUSTER_CONTROLPLANE_ENDPOINT=${CLUSTER_CONTROLPLANE_ENDPOINT}

CLUSTER_ID
  Description: used to assign subnets for use by provisioned applications (k8s/metallb)
  Default: ${DEFAULT_CLUSTER_ID} (dynamically assigned by using last octet of KUBERNETES_CONTROLPLANE_ENDPOINT, 10.x.0.0/16)
  Example: CLUSTER_ID=20
  Current: CLUSTER_ID=${CLUSTER_ID}

CLUSTER_LB_VM_CIDR
  Description: specifies cidr address to use for metallb external services (vm pool)
  Default: ${DEFAULT_CLUSTER_LB_VM_CIDR} (dynamically assigned by using CLUSTER_ID, 10.x.0.0/18)
  Example: CLUSTER_LB_VM_CIDR=10.20.0.0/18
  Current: CLUSTER_LB_VM_CIDR=${CLUSTER_LB_VM_CIDR}

CLUSTER_LB_DEFAULT_CIDR
  Description: specifies cidr address to use for metallb external services (general pool)
  Default: ${DEFAULT_CLUSTER_LB_DEFAULT_CIDR} (dynamically assigned by using CLUSTER_ID, 10.x.64.0/18)
  Example: CLUSTER_LB_DEFAULT_CIDR=10.20.64.0/18
  Current: CLUSTER_LB_DEFAULT_CIDR=${CLUSTER_LB_DEFAULT_CIDR}

CLUSTER_POD_CIDR
  Description: specifies cidr address to use for k8s pods (if not overridden by KUBERNETES_POD_CIDR)
  Default: ${DEFAULT_CLUSTER_POD_CIDR} (dynamically assigned by using CLUSTER_ID, 10.x.128.0/18)
  Example: CLUSTER_POD_CIDR=10.20.128.0/18
  Current: CLUSTER_POD_CIDR=${CLUSTER_POD_CIDR}

CLUSTER_SERVICE_CIDR
  Description: specifies cidr address to use for k8s pods (if not overridden by KUBERNETES_SERVICE_CIDR)
  Default: ${DEFAULT_CLUSTER_SERVICE_CIDR} (dynamically assigned by using CLUSTER_ID, 10.x.192.0/18)
  Example: CLUSTER_SERVICE_CIDR=10.20.192.0/18
  Current: CLUSTER_SERVICE_CIDR=${CLUSTER_SERVICE_CIDR}
\0
EOL

function __set_cluster_defaults {
    local DEFAULT_CLUSTER_CONTROLPLANE_ENDPOINT="${DEFAULT_INTERFACE_IP}:6443"
    local DEFAULT_CLUSTER_ID=${DEFAULT_INTERFACE_IP##*.}
    if [[ "${CLUSTER_CONTROLPLANE_ENDPOINT:-}" == "" ]]; then
        CLUSTER_CONTROLPLANE_ENDPOINT=${DEFAULT_CLUSTER_CONTROLPLANE_ENDPOINT}
    fi
    if [[ "${CLUSTER_ID:-}" == "" ]]; then
        CLUSTER_ID=${DEFAULT_CLUSTER_ID}
    fi
    local DEFAULT_CLUSTER_LB_VM_CIDR=10.${CLUSTER_ID}.0.0/18
    local DEFAULT_CLUSTER_LB_DEFAULT_CIDR=10.${CLUSTER_ID}.64.0/18
    local DEFAULT_CLUSTER_POD_CIDR=10.${CLUSTER_ID}.128.0/18
    local DEFAULT_CLUSTER_SERVICE_CIDR=10.${CLUSTER_ID}.192.0/18


    if [[ "${CLUSTER_LB_VM_CIDR:-}" == "" ]]; then
        CLUSTER_LB_VM_CIDR=${DEFAULT_CLUSTER_LB_VM_CIDR}
    fi
    if [[ "${CLUSTER_LB_DEFAULT_CIDR:-}" == "" ]]; then
        CLUSTER_LB_DEFAULT_CIDR=${DEFAULT_CLUSTER_LB_DEFAULT_CIDR}
    fi
    if [[ "${CLUSTER_POD_CIDR:-}" == "" ]]; then
        CLUSTER_POD_CIDR=${DEFAULT_CLUSTER_POD_CIDR}
    fi
    if [[ "${CLUSTER_SERVICE_CIDR:-}" == "" ]]; then
        CLUSTER_SERVICE_CIDR=${DEFAULT_CLUSTER_SERVICE_CIDR}
    fi
    DEFAULTS_CLUSTER=$( eval "echo -e \"${CLUSTER_HELP//\"/\\\"}\"" )
}

### HA CONFIGURATION

IFS='' read -r -d '\0' HA_HELP <<"EOL"
HA_CONTROLPLANE_NODES
  Description: specifies the names of kubernetes master nodes to load-balance (if unset, controlplane will be provisioned as single-node)
    (must match uname -n for each node)
  Default: unset
  Example: HA_CONTROLPLANE_NODES="server1 server2 server3"
  Current: HA_CONTROLPLANE_NODES=${HA_CONTROLPLANE_NODES}

HA_HEARTBEAT_AUTH_MD5SUM
  Description: used to assign subnets for use by provisioned applications (k8s/metallb)
  Default: ${DEFAULT_HA_HEARTBEAT_AUTH_MD5SUM} (dynamically assigned by using last octet of KUBERNETES_CONTROLPLANE_ENDPOINT, 10.x.0.0/16)
  Example: HA_HEARTBEAT_AUTH_MD5SUM=53bbce87861bbf1fd27827ce692ce5dd
  Current: HA_HEARTBEAT_AUTH_MD5SUM=${HA_HEARTBEAT_AUTH_MD5SUM}

HA_HEARTBEAT_MCAST_GROUP
  Description: specifies cidr address to use for metallb external services (vm pool)
  Default: ${DEFAULT_HA_HEARTBEAT_MCAST_GROUP}
  Example: HA_HEARTBEAT_MCAST_GROUP=255.0.0.2
  Current: HA_HEARTBEAT_MCAST_GROUP=${HA_HEARTBEAT_MCAST_GROUP}

HA_HEARTBEAT_UDP_PORT
  Description: specifies cidr address to use for metallb external services (general pool)
  Default: ${DEFAULT_HA_HEARTBEAT_UDP_PORT}
  Example: HA_HEARTBEAT_UDP_PORT=700
  Current: HA_HEARTBEAT_UDP_PORT=${HA_HEARTBEAT_UDP_PORT}
\0
EOL

function __set_ha_defaults {
    local DEFAULT_HA_HEARTBEAT_AUTH_MD5SUM=$(echo -n "${CLUSTER_CONTROLPLANE_ENDPOINT}" | md5sum | awk '{print $1}')
    local DEFAULT_HA_HEARTBEAT_MCAST_GROUP="225.0.0.1"
    local DEFAULT_HA_HEARTBEAT_UDP_PORT="694"

    if [[ "${HA_CONTROLPLANE_NODES:-}" != "" ]]; then
        ENABLE_HA=true
    else
        ENABLE_HA=false
        HA_CONTROLPLANE_NODES=""
    fi
    if [[ "${HA_HEARTBEAT_AUTH_MD5SUM:-}" == "" ]]; then
        HA_HEARTBEAT_AUTH_MD5SUM=${DEFAULT_HA_HEARTBEAT_AUTH_MD5SUM}
    fi
    if [[ "${HA_HEARTBEAT_MCAST_GROUP:-}" == "" ]]; then
        HA_HEARTBEAT_MCAST_GROUP=${DEFAULT_HA_HEARTBEAT_MCAST_GROUP}
    fi
    if [[ "${HA_HEARTBEAT_UDP_PORT:-}" == "" ]]; then
        HA_HEARTBEAT_UDP_PORT=${DEFAULT_HA_HEARTBEAT_UDP_PORT}
    fi

    DEFAULTS_HA=$( eval "echo -e \"${HA_HELP//\"/\\\"}\"" )
}

### HA BOOTSTRAP

function ha_bootstrap {
    if [[ "${ENABLE_HA}" == "true" && "${KUBERNETES_CONTROLPLANE_ENDPOINT}" != "" ]]; then
        ha_dependencies
    fi
    if [[ "${DEPENDENCIES_ONLY}" == "true" ]]; then
        return 0
    fi
}

function ha_dependencies {
    ha_heartbeat_install
    ha_haproxy_install
}

function ha_heartbeat_install {
    echo "Installing heartbeat for kubernetes apiserver vip management"
    mkdir -p /etc/sysctl.d/ || true
    OUTPUT=$(egrep "net.ipv4.ip_nonlocal_bind=1" /etc/sysctl.d/ha.conf || true)
    if [[ $? -ne 0 ]]; then
        echo "net.ipv4.ip_nonlocal_bind=1" | \
            sudo tee -a /etc/sysctl.d/ha.conf &> /dev/null
    fi
  
    sudocmd sysctl -p
  
    sudocmd apt-get -yq update
    sudocmd apt-get -yq install heartbeat

    echo -e "auth 1\n1 md5 ${HEARTBEAT_AUTH_MD5SUM}" | \
        sudo tee /etc/ha.d/authkeys &> /dev/null
    sudocmd chmod 600 /etc/ha.d/authkeys

    HEARTBEAT_NODES_CONF=""
    HEARTBEAT_LEADER=""
    for node in ${KUBERNETES_MASTER_NODES}; do
        if [[ "$HEARTBEAT_LEADER" == "" ]]; then
            HEARTBEAT_LEADER=$node
        fi
        HEARTBEAT_NODES_CONF="${HEARTBEAT_NODES_CONF}node    ${node}\n"
    done

    sudocmd mkdir -p /etc/ha.d/
    eval "echo -e \"${HA_CONF}\"" \
        | sudo tee /etc/ha.d/ha.cf &> /dev/null

    echo -e "${HEARTBEAT_LEADER} ${LB_IP}\n" \
        | sudo tee /etc/ha.d/haresources &> /dev/null

    sudocmd systemctl restart heartbeat
}

IFS='' read -r -d '\0' HA_CONF <<"EOL"
#       keepalive: how many seconds between heartbeats
#
keepalive 2
#
#       deadtime: seconds-to-declare-host-dead
#
deadtime 10
#
#       What UDP port to use for udp or ppp-udp communication?
#
udpport        ${HEARTBEAT_UDP_PORT}
bcast  ${DEFAULT_INTERFACE}
mcast ${DEFAULT_INTERFACE} ${HEARTBEAT_MCAST_GROUP} ${HEARTBEAT_UDP_PORT} 1 0
ucast ${DEFAULT_INTERFACE} ${DEFAULT_INTERFACE_IP}
#
#       Facility to use for syslog()/logger (alternative to log/debugfile)
#
logfacility     local0
#
#       Tell what machines are in the cluster
#       node    nodename ...    -- must match uname -n
${HEARTBEAT_NODES_CONF}
\0
EOL

function ha_haproxy_install {
    echo "Installing haproxy for kubernetes apiserver load-balancing"
    sudocmd apt-get -yq update
    sudocmd apt-get -yq install haproxy

    HAPROXY_NODES_CONF=""
    for node in ${KUBERNETES_MASTER_NODES}; do
        node_ip=$(getent hosts $node | awk '{print $1}')
        HAPROXY_NODES_CONF="${HAPROXY_NODES_CONF}\n  server ${node} ${node_ip}:${KUBERNETES_APISERVER_LOCAL_BIND_PORT} check check-ssl verify none"
    done

    sudocmd mkdir -p /etc/haproxy/
    eval "echo -e \"${HAPROXY_CONF}\"" \
        | sudo tee /etc/haproxy/haproxy.cfg &> /dev/null

    sudocmd systemctl restart haproxy
}

IFS='' read -r -d '\0' HAPROXY_CONF <<"EOL"
defaults
  timeout connect 5000ms
  timeout check 5000ms
  timeout server 30000ms
  timeout client 30000

global
  tune.ssl.default-dh-param 2048

listen stats
  bind :9000
  mode http
  stats enable
  stats hide-version
  stats realm Haproxy\ Statistics
  stats uri /stats

frontend kubernetes
    bind ${KUBERNETES_CONTROLPLANE_IP}:${KUBERNETES_CONTROLPLANE_BIND_PORT}
    option tcplog
    mode tcp
    use_backend kubernetes-master-nodes

backend kubernetes-master-nodes
  mode tcp
  balance roundrobin
  option httpchk GET /healthz
  http-check expect string ok
${HAPROXY_NODES_CONF}
\0
EOL


### KUBERNETES CONFIGURATION

IFS='' read -r -d '\0' KUBERNETES_HELP <<"EOL"
KUBERNETES_VERSION
  Description: specifies which version of kubernetes to provision
  Default: ${DEFAULT_KUBERNETES_VERSION}
  Example: KUBERNETES_VERSION=${DEFAULT_KUBERNETES_VERSION}
  Current: KUBERNETES_VERSION=${KUBERNETES_VERSION}

KUBERNETES_IMAGE_REPOSITORY
  Description: specifies which image repository to use for kubernetes container images
  Default: ${DEFAULT_KUBERNETES_IMAGE_REPOSITORY}
  Example: KUBERNETES_IMAGE_REPOSITORY=repo.snaproute.com/${DEFAULT_KUBERNETES_IMAGE_REPOSITORY}
  Current: KUBERNETES_IMAGE_REPOSITORY=${KUBERNETES_IMAGE_REPOSITORY}

KUBERNETES_CONTROLPLANE_ENDPOINT
  Description: specifies the VIP / port for k8s cluster when deploying multiple master nodes (requires you set KUBERNETES_MASTER_NODES)
  Default: ${DEFAULT_KUBERNETES_CONTROLPLANE_ENDPOINT} (defaults to CLUSTER_CONTROLPLANE_ENDPOINT)
  Example: KUBERNETES_CONTROLPLANE_ENDPOINT=172.17.0.1:443
  Current: KUBERNETES_CONTROLPLANE_ENDPOINT=${KUBERNETES_CONTROLPLANE_ENDPOINT}

KUBERNETES_APISERVER_LOCAL_BIND_PORT
  Description: specifies the port to locally bind kube-apiserver 
    (load-balancer is expected to forward connections from KUBERNETES_CONTROLPLANE_ENDPOINT to this host/port)
  Default: 6443 if deploying single-node controlplane, 16443 if deploying multi-node controlplane
  Current: KUBERNETES_APISERVER_LOCAL_BIND_PORT=${KUBERNETES_APISERVER_LOCAL_BIND_PORT}

KUBERNETES_POD_CIDR
  Description: specifies the cidr range to use for pod addressing
  Default: ${CLUSTER_POD_CIDR} (see CLUSTER addressing section for details)
  Example: KUBERNETES_POD_CIDR=10.90.128.0/18
  Current: KUBERNETES_POD_CIDR=${KUBERNETES_POD_CIDR}

KUBERNETES_SERVICE_CIDR
  Description: specifies the cidr range to use for service addressing
  Default: ${CLUSTER_SERVICE_CIDR} (see CLUSTER addressing section for details)
  Example: KUBERNETES_SERVICE_CIDR=10.90.192.0/18
  Current: KUBERNETES_SERVICE_CIDR=${KUBERNETES_SERVICE_CIDR}

KUBERNETES_OIDC_ISSUER_URL
  Description: specifies the OIDC issuer URL to use for kube-apiserver authentication
  Default: ${DEFAULT_KUBERNETES_OIDC_ISSUER_URL}
  Current: KUBERNETES_OIDC_ISSUER_URL=${KUBERNETES_OIDC_ISSUER_URL}

KUBERNETES_OIDC_CLIENT_ID
  Description: specifies the OIDC client provider to use for kube-apiserver authentication
  Default: unset
  Current: KUBERNETES_OIDC_CLIENT_ID=${KUBERNETES_OIDC_CLIENT_ID}
\0
EOL

function __set_kubernetes_defaults {
    local DEFAULT_KUBERNETES_IMAGE_REPOSITORY=k8s.gcr.io
    local DEFAULT_KUBERNETES_VERSION=v1.14.1
    local DEFAULT_KUBERNETES_CONTROLPLANE_ENDPOINT=${CLUSTER_CONTROLPLANE_ENDPOINT}
    
    local DEFAULT_KUBERNETES_OIDC_ISSUER_URL=https://accounts.google.com

    if [[ "${KUBERNETES_VERSION:-}" == "" ]]; then
        KUBERNETES_VERSION=${DEFAULT_KUBERNETES_VERSION}
    fi
    if [[ "${KUBERNETES_IMAGE_REPOSITORY:-}" == "" ]]; then
        KUBERNETES_IMAGE_REPOSITORY=${DEFAULT_KUBERNETES_IMAGE_REPOSITORY}
    fi
    if [[ "${KUBERNETES_CONTROLPLANE_ENDPOINT:-}" == "" ]]; then
        KUBERNETES_CONTROLPLANE_ENDPOINT=${DEFAULT_KUBERNETES_CONTROLPLANE_ENDPOINT}
    fi

    KUBERNETES_CONTROLPLANE_IP=$(getent hosts ${KUBERNETES_CONTROLPLANE_ENDPOINT//:*/} | awk '{print $1}')
    KUBERNETES_CONTROLPLANE_BIND_PORT="${KUBERNETES_CONTROLPLANE_ENDPOINT//*:/}"

    local DEFAULT_KUBERNETES_APISERVER_LOCAL_BIND_PORT="${KUBERNETES_CONTROLPLANE_BIND_PORT}"
    if [[ "${HA_CONTROLPLANE_NODES:-}" != "" ]]; then
        DEFAULT_KUBERNETES_APISERVER_LOCAL_BIND_PORT="16443"
    fi

    if [[ "${KUBERNETES_APISERVER_LOCAL_BIND_PORT:-}" == "" ]]; then
        KUBERNETES_APISERVER_LOCAL_BIND_PORT=${DEFAULT_KUBERNETES_APISERVER_LOCAL_BIND_PORT}
    fi

    if [[ "${KUBERNETES_POD_CIDR:-}" == "" ]]; then
        KUBERNETES_POD_CIDR=${CLUSTER_POD_CIDR}
    fi
    if [[ "${KUBERNETES_SERVICE_CIDR:-}" == "" ]]; then
        KUBERNETES_SERVICE_CIDR=${CLUSTER_SERVICE_CIDR}
    fi
    if [[ "${KUBERNETES_OIDC_ISSUER_URL:-}" == "" ]]; then
        KUBERNETES_OIDC_ISSUER_URL=${DEFAULT_KUBERNETES_OIDC_ISSUER_URL}
    fi
    if [[ "${KUBERNETES_OIDC_CLIENT_ID:-}" == "" ]]; then
        KUBERNETES_OIDC_CLIENT_ID=""
    fi

    DEFAULTS_KUBERNETES=$( eval "echo -e \"${KUBERNETES_HELP//\"/\\\"}\"" )
}


### MINIKUBE CONFIGURATION

IFS='' read -r -d '\0' DEFAULTS_MINIKUBE <<"EOL"
MINIKUBE_CPUS
  Description:specifies the number of cpus to allocate to minikube vm
    (minimum 4 cores suggested, performance of nested vms will be impacted if too low)
  Default: ${DEFAULT_MINIKUBE_CPUS}
  Example: MINIKUBE_CPUS=v0.9.3
  Current: MINIKUBE_CPUS=${MINIKUBE_CPUS}

MINIKUBE_MEMORY
  Description: specifies the amount of memory to allocate to minikube vm
    (minimum 8gb suggested, total needed depends on number of nested vms will be run)
  Default: ${DEFAULT_MINIKUBE_MEMORY}
  Example: MINIKUBE_MEMORY=16384
  Current: MINIKUBE_MEMORY=${MINIKUBE_MEMORY}

MINIKUBE_DISK_SIZE
  Description: specifies the amount of memory to allocate to minikube vm
    (minimum 8gb suggested, total needed depends on number of nested vms will be run)
  Default: ${DEFAULT_MINIKUBE_DISK_SIZE}
  Example: MINIKUBE_DISK_SIZE=80g
  Current: MINIKUBE_DISK_SIZE=${MINIKUBE_DISK_SIZE}

MINIKUBE_VM_DRIVER
  Description: specifies minikube driver to use
    (tested with kvm2 on linux, nested virtualization will be enabled in kvm)
    (tested with virtualbox on mac, software virtualization will be enabled in kubevirt)
  Default: ${DEFAULT_MINIKUBE_VM_DRIVER} (depends on os)
  Example: MINIKUBE_VM_DRIVER=kvm2
  Current: MINIKUBE_VM_DRIVER=${MINIKUBE_VM_DRIVER}

MINIKUBE_REGISTRY_NODEPORT
  Description: specifies nodeport to expose a local docker registry
  Default: unset
  Example: MINIKUBE_REGISTRY_NODEPORT=31000
  Current: MINIKUBE_REGISTRY_NODEPORT=${MINIKUBE_REGISTRY_NODEPORT:-}
\0
EOL

function __set_minikube_defaults {
    local DEFAULT_MINIKUBE_CPUS=4
    local DEFAULT_MINIKUBE_MEMORY=8192
    local DEFAULT_MINIKUBE_DISK_SIZE=20g
    if [[ ${OS} == "linux" ]]; then
        local DEFAULT_MINIKUBE_VM_DRIVER=kvm2
    elif [[ ${OS} == "darwin" ]]; then
        local DEFAULT_MINIKUBE_VM_DRIVER=virtualbox
    fi

    if [[ "${MINIKUBE_CPUS:-}" == "" ]]; then
        MINIKUBE_CPUS=${DEFAULT_MINIKUBE_CPUS}
    fi
    if [[ "${MINIKUBE_MEMORY:-}" == "" ]]; then
        MINIKUBE_MEMORY=${DEFAULT_MINIKUBE_MEMORY}
    fi
    if [[ "${MINIKUBE_DISK_SIZE:-}" == "" ]]; then
        MINIKUBE_DISK_SIZE=${DEFAULT_MINIKUBE_DISK_SIZE}
    fi
    if [[ "${MINIKUBE_VM_DRIVER:-}" == "" ]]; then
        MINIKUBE_VM_DRIVER=${DEFAULT_MINIKUBE_VM_DRIVER}
    fi
}

### MINIKUBE BOOTSTRAP

function minikube_bootstrap {
        ADDITIONAL_FILES_PATH_PREPEND=~/.minikube/files
        if [[ "$OS" == "linux " ]]; then
            minikube_dependencies_linux
        elif [[ "$OS" == "darwin " ]]; then
            minikube_dependencies_darwin
        fi
        minikube_download
        minikube_vmdriver
        if [[ "${DEPENDENCIES_ONLY}" == "true" ]]; then
            return 0
        fi
        minikube_files
        minikube_start
        if [[ "${MINIKUBE_REGISTRY_NODEPORT:-}" != "" ]]; then
            minikube_registry
        fi
}

function minikube_dependencies_linux {
    linux_kvm2_install
    minikube_linux_machine_driver
}

function minikube_linux_machine_driver {
    if [[ ! -f $(which docker-machine-driver-kvm2 || true) || "${FULL_INSTALL}" == "true" ]]; then
        echo "Installing kvm2 machine driver for minikube"
        curl -fLo docker-machine-driver-kvm2 https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-kvm2 &> ${REDIR}
        sudocmd install $(pwd)/docker-machine-driver-kvm2 /usr/local/bin/
        rm ./docker-machine-driver-kvm2 &> ${REDIR} || true
    fi
}

function minikube_dependencies_darwin {
    darwin_homebrew_install
    darwin_virtualbox_install
}

function minikube_download {
    echo "Downloading minikube"
    curl -fLo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-${OS}-amd64 &> ${REDIR}
    sudocmd install $(pwd)/minikube /usr/local/bin/
    rm $(pwd)/minikube &> ${REDIR} || true
}

function minikube_vmdriver {
    minikube config set vm-driver ${MINIKUBE_VM_DRIVER} &> ${REDIR}
}

function minikube_files {
    echo "Populating additional files"
    if [[ "${ADDITIONAL_FILES_PATH_PREPEND}" != "" ]]; then
        mkdir -p ${ADDITIONAL_FILES_PATH_PREPEND} &> ${REDIR} && true
    fi

    CNI_PATH=/etc/cni/net.d
    MINIKUBE_CNIPATH=${ADDITIONAL_FILES_PATH_PREPEND}/${CNI_PATH}
    mkdir -p ${MINIKUBE_CNIPATH} &> ${REDIR}
    echo -e "${K8S_CNICONF//\"/\\\"}" > ${MINIKUBE_CNIPATH}/99-k8s.conf

    MINIKUBE_HOSTSPATH=${ADDITIONAL_FILES_PATH_PREPEND}/etc/hosts
    echo -e "127.0.0.1 localhost" > ${MINIKUBE_HOSTSPATH}
    echo -e "127.0.1.1 minikube" >> ${MINIKUBE_HOSTSPATH}
}

IFS='' read -r -d '\0' K8S_CNICONF <<"EOL"
{
  "name": "rkt.kubernetes.io",
  "type": "bridge",
  "bridge": "mybridge",
  "mtu": 1460,
  "addIf": "true",
  "isGateway": true,
  "ipMasq": true,
  "ipam": {
    "type": "host-local",
    "subnet": "10.192.1.0/24",
    "gateway": "10.192.1.1",
    "routes": [
      {
        "dst": "0.0.0.0/0"
      }
    ]
  }
}
\0
EOL

function minikube_start {
    if [[ ${DEBUG} ]]; then
      EXTRA_FLAGS="--v=9"
    fi
    if [[ "${KUBERNETES_OIDC_CLIENT_ID}" != "" ]]; then
        OIDC_FLAGS="\
        --extra-config=apiserver.oidc-issuer-url=${KUBERNETES_OIDC_ISSUER_URL} \
        --extra-config=apiserver.oidc-client-id=${KUBERNETES_OIDC_CLIENT_ID} \
        --extra-config=apiserver.oidc-username-claim=email \
        --extra-config=apiserver.oidc-username-prefix=oidc: \
        --extra-config=apiserver.oidc-groups-claim=groups \
        --extra-config=apiserver.oidc-groups-prefix=oidc: \
        "
    fi
    echo "Starting minikube"
    minikube start \
        --vm-driver ${MINIKUBE_VM_DRIVER} \
        --cpus ${MINIKUBE_CPUS} \
        --memory ${MINIKUBE_MEMORY} \
        --disk-size ${MINIKUBE_DISK_SIZE} \
        --network-plugin cni \
        --enable-default-cni \
        --bootstrapper=kubeadm \
        --kubernetes-version=${KUBERNETES_VERSION} \
        --service-cluster-ip-range=${KUBERNETES_SERVICE_CIDR} \
        --extra-config=controller-manager.allocate-node-cidrs=true \
        --extra-config=controller-manager.cidr-allocator-type=RangeAllocator \
        --extra-config=controller-manager.cluster-cidr=${KUBERNETES_POD_CIDR} \
        --extra-config=controller-manager.service-cluster-ip-range=${KUBERNETES_SERVICE_CIDR} \
        --extra-config=controller-manager.node-cidr-mask-size=24 \
        --extra-config=apiserver.service-cluster-ip-range=${KUBERNETES_SERVICE_CIDR} \
        ${OIDC_FLAGS} \
        ${EXTRA_FLAGS}
}


function minikube_registry {
    echo "Installing minikube registry"
    eval "echo -e \"${REGISTRY_YAML//\"/\\\"}\"" | \
        kubectl create -f - &> ${REDIR}
}

IFS=''  read -r -d '\0' REGISTRY_YAML << "EOL"
apiVersion: v1
kind: ReplicationController
metadata:
  labels:
    kubernetes.io/minikube-addons: registry
    addonmanager.kubernetes.io/mode: Reconcile
  name: registry
  namespace: kube-system
spec:
  replicas: 1
  selector:
    kubernetes.io/minikube-addons: registry
  template:
    metadata:
      labels:
        kubernetes.io/minikube-addons: registry
        addonmanager.kubernetes.io/mode: Reconcile
    spec:
      containers:
      - image: registry.hub.docker.com/library/registry:2.6.1
        imagePullPolicy: IfNotPresent
        name: registry
        ports:
        - containerPort: 5000
          protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  labels:
    kubernetes.io/minikube-addons: registry
    addonmanager.kubernetes.io/mode: Reconcile
  name: registry-local
  namespace: kube-system
spec:
  type: NodePort
  ports:
  - nodePort: ${MINIKUBE_REGISTRY_NODEPORT}
    port: 5000
    targetPort: 5000
  selector:
    kubernetes.io/minikube-addons: registry
\0
EOL


### KUBEADM CONFIGURATION

function kubeadm_bootstrap {
    ADDITIONAL_FILES_PATH_PREPEND=""
    kubeadm_dependencies
    if [[ "${DEPENDENCIES_ONLY}" == "true" ]]; then
        return 0
    fi
    kubeadm_files
    kubeadm_init
}

function kubeadm_dependencies {
    echo "installing/downloading kubeadm dependencies"

    if [[ ! -f $(which kvm-ok || true) || "${FULL_INSTALL}" == "true" ]]; then
        sudocmd apt-get -qy update
        sudocmd apt-get -qy install cpu-checker
    fi
    set +e
    kvm-ok &> /dev/null
    RT=$?
    set -e
    if [[ "${RT}" != "0" || "${FULL_INSTALL}" == "true" ]]; then
        linux_kvm2_install
    fi

    if [[ ! -f $(which docker || true) || "${FULL_INSTALL}" == "true" ]]; then
        linux_docker_install
    fi
    
    kubelet_init
    kubeadm_download
    kubectl_download
}

function kubectl_download {
    if [[ ! -f $(which kubectl || true) || "${FULL_INSTALL}" == "true" ]]; then
        echo "Installing kubectl"
        curl -fLo kubectl https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/${OS}/amd64/kubectl &> ${REDIR}
        sudocmd install $(pwd)/kubectl /usr/local/bin/
        rm $(pwd)/kubectl &> ${REDIR} || true
    fi
}

function kubeadm_download {
    if [[ ! -f $(which kubeadm || true) || "${FULL_INSTALL}" == "true" ]]; then
        echo "Installing kubeadm"
        curl -fLo kubeadm https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/${OS}/amd64/kubeadm &> ${REDIR}
        sudocmd install $(pwd)/kubeadm /usr/local/bin/
        rm $(pwd)/kubeadm &> ${REDIR} || true
    fi
}

function kubelet_init {
    local output=$(egrep "br_netfilter" /etc/modules-load.d/modules.conf)
    if [[ $? -ne 0 ]]; then
        echo "br_netfilter" | sudo tee -a /etc/modules-load.d/modules.conf
        sudocmd modprobe br_netfilter
    fi

    local output=$(egrep "net.bridge.bridge-nf-call-ip6tables = 1" /etc/sysctl.d/k8s.conf)
    if [[ $? -ne 0 ]]; then
        echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee -a /etc/sysctl.d/k8s.conf &> ${REDIR}
    fi
    local output=$(egrep "net.bridge.bridge-nf-call-iptables = 1" /etc/sysctl.d/k8s.conf)
    if [[ $? -ne 0 ]]; then
        echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.d/k8s.conf &> ${REDIR}
    fi
    
    sudocmd sysctl -p

    KVERSION=${KUBERNETES_VERSION//v/}-00
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - &> /dev/null
    echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list &> /dev/null
    sudocmd apt-get -yq update
    sudocmd apt-get -yq install kubelet=$KVERSION kubectl=$KVERSION kubeadm=$KVERSION --allow-downgrades
}

function kubeadm_files {
    echo "Populating additional files"
    if [[ "${ADDITIONAL_FILES_PATH_PREPEND}" != "" ]]; then
        mkdir -p ${ADDITIONAL_FILES_PATH_PREPEND} &> ${REDIR} && true
    fi
}

function kubeadm_init {
    echo "Running kubeadm initialization"
    sudocmd kubeadm reset --force || true
    KUBERNETES_OIDC_CONF=$( eval "echo -e \"${KUBERNETES_OIDC_CONF//\"/\\\"}\"" )
    if [[ "${KUBERNETES_OIDC_CLIENT_ID}" == "" ]]; then
        KUBERNETES_OIDC_CONF=""
    fi

    eval "echo -e \"${KUBEADM_CONF//\"/\\\"}\"" \
        > ./kubeadm.yaml

    EXTRA_FLAGS=""
    if [[ ${DEBUG} ]]; then
        EXTRA_FLAGS="--v=9"
    fi

    KUBEADM_OUTPUT=$(\
        sudo kubeadm init \
        --ignore-preflight-errors=Swap \
        --config=./kubeadm.yaml \
        --experimental-upload-certs \
        ${EXTRA_FLAGS} \
        )

    rm ./kubeadm.yaml &> ${REDIR} || true
    mkdir -p ${HOME}/.kube &> ${REDIR}
    sudocmd cp /etc/kubernetes/admin.conf ${HOME}/.kube/config
    sudocmd chown $(id -u):$(id -g) ${HOME}/.kube/config
}


IFS='' read -r -d '\0' KUBERNETES_OIDC_CONF <<"EOL"
    oidc-issuer-url: ${KUBERNETES_OIDC_ISSUER_URL}
    oidc-client-id: ${KUBERNETES_OIDC_CLIENT_ID}
    oidc-username-claim: email
    oidc-username-prefix: "oidc:"
    oidc-groups-claim: groups
    oidc-groups-prefix: "oidc:"
\0
EOL

IFS='' read -r -d '\0' KUBEADM_CONF <<"EOL"
apiVersion: kubeadm.k8s.io/v1beta1
kind: InitConfiguration
localAPIEndpoint:
  bindPort: ${KUBERNETES_APISERVER_LOCAL_BIND_PORT}
bootstrapTokens:
  - groups:
      - system:bootstrappers:kubeadm:default-node-token
    token: abcdef.0123456789abcdef
    ttl: 24h0m0s
    usages:
      - signing
      - authentication
nodeRegistration:
  criSocket: /var/run/dockershim.sock
  name: ${HOSTNAME}
  taints:
  - effect: PreferNoSchedule
    key: node-role.kubernetes.io/master
  kubeletExtraArgs:
    fail-swap-on: "false"
---
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
apiServer:
  extraArgs:
    enable-admission-plugins: "NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota"
    service-cluster-ip-range: "${KUBERNETES_SERVICE_CIDR}"
${KUBERNETES_OIDC_CONF}
controllerManager:
  extraArgs:
    allocate-node-cidrs: "true"
    cidr-allocator-type: "RangeAllocator"
    cluster-cidr: "${KUBERNETES_POD_CIDR}"
    node-cidr-mask-size: "24"
    service-cluster-ip-range: "${KUBERNETES_SERVICE_CIDR}"
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controlPlaneEndpoint: "${KUBERNETES_CONTROLPLANE_ENDPOINT}"
dns:
  type: CoreDNS
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: ${KUBERNETES_IMAGE_REPOSITORY}
kubernetesVersion: ${KUBERNETES_VERSION}
networking:
  dnsDomain: cluster.local
  podSubnet: "${KUBERNETES_POD_CIDR}"
  serviceSubnet: "${KUBERNETES_SERVICE_CIDR}"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
imageGCHighThresholdPercent: 90
evictionHard:
  nodefs.available: "0%"
  nodefs.inodesFree: "0%"
  imagefs.available: "0%"
\0
EOL



### CNI CONFIGURATION

IFS='' read -r -d '\0' CNI_HELP <<"EOL"
CNI_PLUGINS_VERSION
  Description: specifies which version of cni plugins to deploy
  Default: ${DEFAULT_CNI_PLUGINS_VERSION}
  Example: CNI_PLUGINS_VERSION=v0.3
  Current: CNI_PLUGINS_VERSION=${CNI_PLUGINS_VERSION}

CNI_PLUGINS_IMAGE_REPOSITORY
  Description: specifies which image repository to use for cni plugins init container image
  Default: ${DEFAULT_CNI_PLUGINS_IMAGE_REPOSITORY}
  Example: CNI_PLUGINS_IMAGE_REPOSITORY=${BOOTSTRAPPER_DOCKER_REGISTRY}/vm-infra/cni
  Current: CNI_PLUGINS_IMAGE_REPOSITORY=${CNI_PLUGINS_IMAGE_REPOSITORY}

CNI_MULTUS_VERSION
  Description: specifies which version of multus to deploy
  Default: ${DEFAULT_CNI_MULTUS_VERSION}
  Example: CNI_MULTUS_VERSION=latest
  Current: CNI_MULTUS_VERSION=${CNI_MULTUS_VERSION}

CNI_MULTUS_IMAGE_REPOSITORY
  Description: specifies which image repository to use for kubernetes container images
  Default: ${DEFAULT_CNI_MULTUS_IMAGE_REPOSITORY}
  Example: CNI_MULTUS_IMAGE_REPOSITORY=${BOOTSTRAPPER_DOCKER_REGISTRY}/vm-infra/cni
  Current: CNI_MULTUS_IMAGE_REPOSITORY=${CNI_MULTUS_IMAGE_REPOSITORY}

CNI_FLANNEL_VERSION
  Description: specifies which version of flannel to deploy
  Default: ${DEFAULT_CNI_FLANNEL_VERSION}
  Example: CNI_FLANNEL_VERSION=${DEFAULT_CNI_FLANNEL_VERSION}
  Current: CNI_FLANNEL_VERSION=${CNI_FLANNEL_VERSION}

CNI_FLANNEL_IMAGE_REPOSITORY
  Description: specifies which image repository to use for flannel container images
  Default: ${DEFAULT_CNI_FLANNEL_IMAGE_REPOSITORY}
  Example: CNI_FLANNEL_IMAGE_REPOSITORY=${BOOTSTRAPPER_DOCKER_REGISTRY}/vm-infra/cni
  Current: CNI_FLANNEL_IMAGE_REPOSITORY=${CNI_FLANNEL_IMAGE_REPOSITORY}
\0
EOL

function __set_cni_defaults {
    local DEFAULT_CNI_PLUGINS_VERSION=v0.4
    local DEFAULT_CNI_PLUGINS_IMAGE_REPOSITORY=${BOOTSTRAPPER_DOCKER_REGISTRY}/vm-infra/cni
    local DEFAULT_CNI_MULTUS_VERSION=latest
    local DEFAULT_CNI_MULTUS_IMAGE_REPOSITORY=${BOOTSTRAPPER_DOCKER_REGISTRY}/vm-infra/cni
    local DEFAULT_CNI_FLANNEL_VERSION=v0.11.0
    local DEFAULT_CNI_FLANNEL_IMAGE_REPOSITORY=${BOOTSTRAPPER_DOCKER_REGISTRY}/vm-infra/quay.io/coreos

    if [[ "${CNI_PLUGINS_VERSION:-}" == "" ]]; then
        CNI_PLUGINS_VERSION=${DEFAULT_CNI_PLUGINS_VERSION}
    fi
    if [[ "${CNI_PLUGINS_IMAGE_REPOSITORY:-}" == "" ]]; then
        CNI_PLUGINS_IMAGE_REPOSITORY=${DEFAULT_CNI_PLUGINS_IMAGE_REPOSITORY}
    fi
    if [[ "${CNI_MULTUS_VERSION:-}" == "" ]]; then
        CNI_MULTUS_VERSION=${DEFAULT_CNI_MULTUS_VERSION}
    fi
    if [[ "${CNI_MULTUS_IMAGE_REPOSITORY:-}" == "" ]]; then
        CNI_MULTUS_IMAGE_REPOSITORY=${DEFAULT_CNI_MULTUS_IMAGE_REPOSITORY}
    fi
    if [[ "${CNI_FLANNEL_VERSION:-}" == "" ]]; then
        CNI_FLANNEL_VERSION=${DEFAULT_CNI_FLANNEL_VERSION}
    fi
    if [[ "${CNI_FLANNEL_IMAGE_REPOSITORY:-}" == "" ]]; then
        CNI_FLANNEL_IMAGE_REPOSITORY=${DEFAULT_CNI_FLANNEL_IMAGE_REPOSITORY}
    fi

    DEFAULTS_CNI=$( eval "echo -e \"${CNI_HELP//\"/\\\"}\"" )
}

### CNI BOOTSTRAP

function cni_bootstrap {
    if [[ "${DEPENDENCIES_ONLY}" == "true" ]]; then
        return 0
    fi
    flannel_deploy
    multus_deploy
}

function flannel_deploy {
    echo "Installing flannel networking"
    eval "echo -e \"${FLANNEL_YAML//\"/\\\"}\"" | \
        kubectl create -f - &> ${REDIR}
}

function multus_deploy {
    echo "Installing cni-plugins / multus networking"
    eval "echo -e \"${MULTUS_YAML//\"/\\\"}\"" | \
        kubectl create -f - &> ${REDIR}
}

IFS='' read -r -d '\0' FLANNEL_YAML <<"EOL"
---
apiVersion: extensions/v1beta1
kind: PodSecurityPolicy
metadata:
  name: psp.flannel.unprivileged
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: docker/default
    seccomp.security.alpha.kubernetes.io/defaultProfileName: docker/default
    apparmor.security.beta.kubernetes.io/allowedProfileNames: runtime/default
    apparmor.security.beta.kubernetes.io/defaultProfileName: runtime/default
spec:
  privileged: false
  volumes:
    - configMap
    - secret
    - emptyDir
    - hostPath
  allowedHostPaths:
    - pathPrefix: "/etc/cni/net.d"
    - pathPrefix: "/etc/kube-flannel"
    - pathPrefix: "/run/flannel"
  readOnlyRootFilesystem: false
  # Users and groups
  runAsUser:
    rule: RunAsAny
  supplementalGroups:
    rule: RunAsAny
  fsGroup:
    rule: RunAsAny
  # Privilege Escalation
  allowPrivilegeEscalation: false
  defaultAllowPrivilegeEscalation: false
  # Capabilities
  allowedCapabilities: ['NET_ADMIN']
  defaultAddCapabilities: []
  requiredDropCapabilities: []
  # Host namespaces
  hostPID: false
  hostIPC: false
  hostNetwork: true
  hostPorts:
  - min: 0
    max: 65535
  # SELinux
  seLinux:
    # SELinux is unsed in CaaSP
    rule: 'RunAsAny'
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: flannel
rules:
  - apiGroups: ['extensions']
    resources: ['podsecuritypolicies']
    verbs: ['use']
    resourceNames: ['psp.flannel.unprivileged']
  - apiGroups:
      - ""
    resources:
      - pods
    verbs:
      - get
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - nodes/status
    verbs:
      - patch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: flannel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flannel
subjects:
- kind: ServiceAccount
  name: flannel
  namespace: kube-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flannel
  namespace: kube-system
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: kube-flannel-cfg
  namespace: kube-system
  labels:
    tier: node
    app: flannel
data:
  cni-conf.json: |
    {
      "cniVersion": "0.3.1",
      "name": "default-cni-network",
      "plugins": [
        {
          "type": "flannel",
          "name": "flannel.1",
            "delegate": {
              "isDefaultGateway": true,
              "hairpinMode": true
            }
          },
          {
            "type": "portmap",
            "capabilities": {
              "portMappings": true
            }
          }
      ]
    }
  net-conf.json: |
    {
      "Network": "${KUBERNETES_POD_CIDR}",
      "Backend": {
        "Type": "vxlan"
      }
    }
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: kube-flannel-ds-amd64
  namespace: kube-system
  labels:
    tier: node
    app: flannel
spec:
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      hostNetwork: true
      nodeSelector:
        beta.kubernetes.io/arch: amd64
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni
        image: ${CNI_FLANNEL_IMAGE_REPOSITORY}/flannel:${CNI_FLANNEL_VERSION}-amd64
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/90-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
        image: ${CNI_FLANNEL_IMAGE_REPOSITORY}/flannel:${CNI_FLANNEL_VERSION}-amd64
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: false
          capabilities:
             add: ["NET_ADMIN"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      volumes:
        - name: run
          hostPath:
            path: /run/flannel
        - name: cni
          hostPath:
            path: /etc/cni/net.d
        - name: flannel-cfg
          configMap:
            name: kube-flannel-cfg
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: kube-flannel-ds-arm64
  namespace: kube-system
  labels:
    tier: node
    app: flannel
spec:
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      hostNetwork: true
      nodeSelector:
        beta.kubernetes.io/arch: arm64
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni
        image: ${CNI_FLANNEL_IMAGE_REPOSITORY}/flannel:${CNI_FLANNEL_VERSION}-arm64
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/90-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
        image: ${CNI_FLANNEL_IMAGE_REPOSITORY}/flannel:${CNI_FLANNEL_VERSION}-arm64
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: false
          capabilities:
             add: ["NET_ADMIN"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      volumes:
        - name: run
          hostPath:
            path: /run/flannel
        - name: cni
          hostPath:
            path: /etc/cni/net.d
        - name: flannel-cfg
          configMap:
            name: kube-flannel-cfg
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: kube-flannel-ds-arm
  namespace: kube-system
  labels:
    tier: node
    app: flannel
spec:
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      hostNetwork: true
      nodeSelector:
        beta.kubernetes.io/arch: arm
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni
        image: ${CNI_FLANNEL_IMAGE_REPOSITORY}/flannel:${CNI_FLANNEL_VERSION}-arm
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/90-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
        image: ${CNI_FLANNEL_IMAGE_REPOSITORY}/flannel:${CNI_FLANNEL_VERSION}-arm
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: false
          capabilities:
             add: ["NET_ADMIN"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      volumes:
        - name: run
          hostPath:
            path: /run/flannel
        - name: cni
          hostPath:
            path: /etc/cni/net.d
        - name: flannel-cfg
          configMap:
            name: kube-flannel-cfg
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: kube-flannel-ds-ppc64le
  namespace: kube-system
  labels:
    tier: node
    app: flannel
spec:
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      hostNetwork: true
      nodeSelector:
        beta.kubernetes.io/arch: ppc64le
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni
        image: ${CNI_FLANNEL_IMAGE_REPOSITORY}/flannel:${CNI_FLANNEL_VERSION}-ppc64le
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/90-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
        image: ${CNI_FLANNEL_IMAGE_REPOSITORY}/flannel:${CNI_FLANNEL_VERSION}-ppc64le
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: false
          capabilities:
             add: ["NET_ADMIN"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      volumes:
        - name: run
          hostPath:
            path: /run/flannel
        - name: cni
          hostPath:
            path: /etc/cni/net.d
        - name: flannel-cfg
          configMap:
            name: kube-flannel-cfg
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: kube-flannel-ds-s390x
  namespace: kube-system
  labels:
    tier: node
    app: flannel
spec:
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      hostNetwork: true
      nodeSelector:
        beta.kubernetes.io/arch: s390x
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni
        image: ${CNI_FLANNEL_IMAGE_REPOSITORY}/flannel:${CNI_FLANNEL_VERSION}-s390x
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/90-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
        image: ${CNI_FLANNEL_IMAGE_REPOSITORY}/flannel:${CNI_FLANNEL_VERSION}-s390x
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: false
          capabilities:
             add: ["NET_ADMIN"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      volumes:
        - name: run
          hostPath:
            path: /run/flannel
        - name: cni
          hostPath:
            path: /etc/cni/net.d
        - name: flannel-cfg
          configMap:
            name: kube-flannel-cfg
\0
EOL

IFS=''  read -r -d '\0' MULTUS_YAML << "EOL"
---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: network-attachment-definitions.k8s.cni.cncf.io
spec:
  group: k8s.cni.cncf.io
  version: v1
  scope: Namespaced
  names:
    plural: network-attachment-definitions
    singular: network-attachment-definition
    kind: NetworkAttachmentDefinition
    shortNames:
    - net-attach-def
  validation:
    openAPIV3Schema:
      properties:
        spec:
          properties:
            config:
                 type: string
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: multus
rules:
  - apiGroups: ["k8s.cni.cncf.io"]
    resources:
      - '*'
    verbs:
      - '*'
  - apiGroups:
      - ""
    resources:
      - pods
      - pods/status
    verbs:
      - get
      - update
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: multus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: multus
subjects:
- kind: ServiceAccount
  name: multus
  namespace: kube-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: multus
  namespace: kube-system
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: multus-cni-config
  namespace: kube-system
  labels:
    tier: node
    app: multus
data:
  cni-conf.json: |
    {
      "name": "multus-cni-network",
      "type": "multus",
      "capabilities": {
        "portMappings": true
      },
      "delegates": [
        {
          "cniVersion": "0.3.1",
          "name": "default-cni-network",
          "plugins": [
            {
              "type": "flannel",
              "name": "flannel.1",
                "delegate": {
                  "isDefaultGateway": true,
                  "hairpinMode": true
                }
              },
              {
                "type": "portmap",
                "capabilities": {
                  "portMappings": true
                }
              }
          ]
        }
      ],
      "kubeconfig": "/etc/cni/net.d/multus.d/multus.kubeconfig",
      "LogFile": "/var/log/multus.log",
      "LogLevel": "debug"
    }
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: kube-multus-ds-amd64
  namespace: kube-system
  labels:
    tier: node
    app: multus
spec:
  template:
    metadata:
      labels:
        tier: node
        app: multus
    spec:
      hostNetwork: true
      nodeSelector:
        beta.kubernetes.io/arch: amd64
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: multus
      initContainers:
      - name: install-cni
        image: ${CNI_PLUGINS_IMAGE_REPOSITORY}/cni-plugins:${CNI_PLUGINS_VERSION}-amd64
        command:
        - /bin/sh
        - -c
        args:
        - cp -f /plugins/* /opt/cni/bin/
        volumeMounts:
        - name: cnibin
          mountPath: /opt/cni/bin/
      containers:
      - name: kube-multus
        image: ${CNI_MULTUS_IMAGE_REPOSITORY}/multus:${CNI_MULTUS_VERSION}
        imagePullPolicy: Always
        command: ["/entrypoint.sh"]
        args:
        - "--multus-conf-file=/tmp/multus-conf/70-multus.conf"
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: true
        volumeMounts:
        - name: cni
          mountPath: /host/etc/cni/net.d
        - name: cnibin
          mountPath: /host/opt/cni/bin
        - name: varlog
          mountPath: /var/log/multus.log
        - name: multus-cfg
          mountPath: /tmp/multus-conf
      volumes:
        - name: cni
          hostPath:
            path: /etc/cni/net.d
        - name: cnibin
          hostPath:
            path: /opt/cni/bin
        - name: varlog
          hostPath:
            path: /var/log/multus.log
            type: FileOrCreate
        - name: multus-cfg
          configMap:
            name: multus-cni-config
            items:
            - key: cni-conf.json
              path: 70-multus.conf
\0
EOL


### HELM CONFIGURATION

IFS='' read -r -d '\0' HELM_HELP <<"EOL"
HELM_VERSION
  Description: specifies which version of helm to provision
  Default: ${DEFAULT_HELM_VERSION}
  Example: HELM_VERSION=v2.10.0
  Current: HELM_VERSION=${HELM_VERSION}
\0
EOL

function __set_helm_defaults {
    local DEFAULT_HELM_VERSION=v2.11.0

    if [[ "${HELM_VERSION:-}" == "" ]]; then
        HELM_VERSION=${DEFAULT_HELM_VERSION}
    fi

    DEFAULTS_HELM=$( eval "echo -e \"${HELM_HELP//\"/\\\"}\"" )
}

### HELM BOOTSTRAP

function helm_bootstrap {
    helm_dependencies
    if [[ "${DEPENDENCIES_ONLY}" == "true" ]]; then
        return 0
    fi
    helm_deploy
}

function helm_dependencies {
    if [[ ! -f $(which helm || true) || "${FULL_INSTALL}" == "true" ]]; then
        echo "Installing helm"
        curl https://raw.githubusercontent.com/helm/helm/master/scripts/get > get_helm.sh 2> /dev/null && \
            chmod 700 get_helm.sh && \
            ./get_helm.sh --version ${HELM_VERSION} &> ${REDIR}
            rm ./get_helm.sh &> ${REDIR} || true
    fi
}

function helm_deploy {
    echo "Deploying helm"
    kubectl --namespace kube-system create serviceaccount tiller &> ${REDIR}
    kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller &> ${REDIR}
    helm init --service-account tiller --upgrade --wait &> ${REDIR}
    sudocmd chown -R $(id -u):$(id -g) ${HOME}/.helm/
    helm repo update &> ${REDIR}
}

### KUBEFED CONFIGURATION

IFS='' read -r -d '\0' KUBEFED_HELP <<"EOL"
KUBEFED_VERSION
  Description: specifies the version to use for kubevirt (virt-api / virt-controller / virt-handler)
  Default: ${DEFAULT_KUBEFED_VERSION}
  Example: KUBEFED_VERSION=0.1.0-rc3
  Current: KUBEFED_VERSION=${KUBEFED_VERSION}

KUBEFED_KUBEFEDCTL_VERSION
  Description: specifies the version of kubefedctl to download/install
  Default: ${DEFAULT_KUBEFED_KUBEFEDCTL_VERSION}
  Example: KUBEFED_KUBEFEDCTL_VERSION=0.1.0-rc3
  Current: KUBEFED_KUBEFEDCTL_VERSION=${KUBEFED_KUBEFEDCTL_VERSION}

KUBEFED_IMAGE_REPOSITORY
  Description: specifies the docker repository to use for kubefed images
  Default: ${DEFAULT_KUBEFED_IMAGE_REPOSITORY}
  Example: KUBEFED_IMAGE_REPOSITORY=quay.io/kubernetes-multicluster
  Current: KUBEFED_IMAGE_REPOSITORY=${KUBEFED_IMAGE_REPOSITORY}

KUBEFED_KUBEFEDCTL_BASE_URL
  Description: specifies the base url to use when downloading kubefedctl
  Default: ${DEFAULT_KUBEFED_KUBEFEDCTL_BASE_URL}
  Example: KUBEFED_KUBEFEDCTL_BASE_URL=0.1.0-rc3
  Current: KUBEFED_KUBEFEDCTL_BASE_URL=${KUBEFED_KUBEFEDCTL_BASE_URL}

KUBEFED_SYSTEM_NAMESPACE
  Description: namespace to deploy the kubefed controller/webhook
  Default: ${DEFAULT_KUBEFED_SYSTEM_NAMESPACE}
  Example: KUBEFED_SYSTEM_NAMESPACE=kube-federation-system
  Current: KUBEFED_SYSTEM_NAMESPACE=${KUBEFED_SYSTEM_NAMESPACE}
\0
EOL

function __set_kubefed_defaults {
    local DEFAULT_KUBEFED_IMAGE_REPOSITORY=quay.io/kubernetes-multicluster/kubefed
    # ${BOOTSTRAPPER_DOCKER_REGISTRY}/vm-infra/kubefed
    local DEFAULT_KUBEFED_VERSION=0.1.0-rc5
    local DEFAULT_KUBEFED_KUBEFEDCTL_VERSION=0.1.0-rc5
    local DEFAULT_KUBEFED_KUBEFEDCTL_BASE_URL=https://github.com/kubernetes-sigs/kubefed/releases/download
    # https://github.com/snaproute-mino/kubefed/releases/download
    local DEFAULT_KUBEFED_SYSTEM_NAMESPACE=kube-federation-system

    if [[ "${KUBEFED_IMAGE_REPOSITORY:-}" == "" ]]; then
        KUBEFED_IMAGE_REPOSITORY=${DEFAULT_KUBEFED_IMAGE_REPOSITORY}
    fi
    if [[ "${KUBEFED_VERSION:-}" == "" ]]; then
        KUBEFED_VERSION=${DEFAULT_KUBEFED_VERSION}
    fi
    if [[ "${KUBEFED_KUBEFEDCTL_VERSION:-}" == "" ]]; then
        KUBEFED_KUBEFEDCTL_VERSION=${DEFAULT_KUBEFED_KUBEFEDCTL_VERSION}
    fi
    if [[ "${KUBEFED_KUBEFEDCTL_BASE_URL:-}" == "" ]]; then
        KUBEFED_KUBEFEDCTL_BASE_URL=${DEFAULT_KUBEFED_KUBEFEDCTL_BASE_URL}
    fi
    if [[ "${KUBEFED_SYSTEM_NAMESPACE:-}" == "" ]]; then
        KUBEFED_SYSTEM_NAMESPACE=${DEFAULT_KUBEFED_SYSTEM_NAMESPACE}
    fi
    if [[ "${KUBEFED_KUBEFEDCTL_URL:-}" == "" ]]; then
        KUBEFED_KUBEFEDCTL_URL=${KUBEFED_KUBEFEDCTL_BASE_URL}/${KUBEFED_KUBEFEDCTL_VERSION}/kubefedctl-${KUBEFED_KUBEFEDCTL_VERSION}-${OS}-amd64.tgz
    fi
    KUBEFED_KUBEFEDCTL_FILE=${KUBEFED_KUBEFEDCTL_URL##*\/}
    DEFAULTS_KUBEFED=$( eval "echo -e \"${KUBEFED_HELP//\"/\\\"}\"" )
}

function kubefed_bootstrap {
    kubefed_dependencies
    if [[ "${DEPENDENCIES_ONLY}" == "true" ]]; then
        return 0
    fi
    kubefed_deploy
}

function kubefed_dependencies {
    if [[ ! -f $(which kubefedctl || true) || "${FULL_INSTALL}" == "true" ]]; then
        >&2 echo "Installing kubefedctl"
        curl -fLo ${KUBEFED_KUBEFEDCTL_FILE} ${KUBEFED_KUBEFEDCTL_URL} &> ${REDIR}
        tar xvzf $(pwd)/${KUBEFED_KUBEFEDCTL_FILE}
        sudocmd install $(pwd)/${KUBEFED_KUBEFEDCTL_FILE%%\.*} /usr/local/bin/
        sudocmd ln -s /usr/local/bin/${KUBEFED_KUBEFEDCTL_FILE%%\.*} /usr/local/bin/kubefedctl
        rm $(pwd)/${KUBEFED_KUBEFEDCTL_FILE} &> ${REDIR} || true
        rm $(pwd)/kubefedctl &> ${REDIR} || true
    fi
}

function kubefed_deploy {
    echo "Deploying kubefed"
    helm repo add kubefed-charts https://raw.githubusercontent.com/kubernetes-sigs/kubefed/master/charts &> ${REDIR}
    helm repo update &> ${REDIR}
    helm upgrade \
        --install kubefed \
        kubefed-charts/kubefed \
        --version ${KUBEFED_VERSION} \
        --namespace ${KUBEFED_SYSTEM_NAMESPACE} \
        --set "controllermanager.repository=${KUBEFED_IMAGE_REPOSITORY}" \
        --set "controllermanager.replicaCount=2"
}

### KUBEVIRT CONFIGURATION

IFS='' read -r -d '\0' KUBEVIRT_HELP <<"EOL"
KUBEVIRT_VERSION
  Description: specifies the version to use for kubevirt (virt-api / virt-controller / virt-handler)
  Default: ${DEFAULT_KUBEVIRT_VERSION}
  Example: KUBEVIRT_VERSION=v0.16.0
  Current: KUBEVIRT_VERSION=${KUBEVIRT_VERSION}

KUBEVIRT_VIRTCTL_VERSION
  Description: specifies the version of virtctl to download/install
  Default: ${DEFAULT_KUBEVIRT_VIRTCTL_VERSION}
  Example: KUBEVIRT_VIRTCTL_VERSION=v0.15.0
  Current: KUBEVIRT_VIRTCTL_VERSION=${KUBEVIRT_VIRTCTL_VERSION}

KUBEVIRT_IMAGE_REPOSITORY
  Description: specifies the docker repository to use for kubevirt images
  Default: ${DEFAULT_KUBEVIRT_IMAGE_REPOSITORY}
  Example: KUBEVIRT_IMAGE_REPOSITORY=docker.io/kubevirt
  Current: KUBEVIRT_IMAGE_REPOSITORY=${KUBEVIRT_IMAGE_REPOSITORY}

KUBEVIRT_SOFTWARE_EMULATION
  Description: specifies whether software emulation should be enabled
  Default: ${DEFAULT_KUBEVIRT_SOFTWARE_EMULATION}
  Example: KUBEVIRT_SOFTWARE_EMULATION=true
  Current: KUBEVIRT_SOFTWARE_EMULATION=${KUBEVIRT_SOFTWARE_EMULATION}
\0
EOL

function __set_kubevirt_defaults {
    local DEFAULT_KUBEVIRT_IMAGE_REPOSITORY=${BOOTSTRAPPER_DOCKER_REGISTRY}/vm-infra/kubevirt
    local DEFAULT_KUBEVIRT_VERSION=v0.16.0-snaproute
    local DEFAULT_KUBEVIRT_VIRTCTL_VERSION=v0.16.0
    if [[ "${OS}" == "linux" ]]; then
        local DEFAULT_KUBEVIRT_SOFTWARE_EMULATION=false
    elif [[ "${OS}" == "darwin" ]]; then
        local DEFAULT_KUBEVIRT_SOFTWARE_EMULATION=true
    fi

    if [[ "${KUBEVIRT_IMAGE_REPOSITORY:-}" == "" ]]; then
        KUBEVIRT_IMAGE_REPOSITORY=${DEFAULT_KUBEVIRT_IMAGE_REPOSITORY}
    fi
    if [[ "${KUBEVIRT_VERSION:-}" == "" ]]; then
        KUBEVIRT_VERSION=${DEFAULT_KUBEVIRT_VERSION}
    fi
    if [[ "${KUBEVIRT_VIRTCTL_VERSION:-}" == "" ]]; then
        KUBEVIRT_VIRTCTL_VERSION=${DEFAULT_KUBEVIRT_VIRTCTL_VERSION}
    fi
    if [[ "${KUBEVIRT_SOFTWARE_EMULATION:-}" == "" ]]; then
        KUBEVIRT_SOFTWARE_EMULATION=${DEFAULT_KUBEVIRT_SOFTWARE_EMULATION}
    fi

    DEFAULTS_KUBEVIRT=$( eval "echo -e \"${KUBEVIRT_HELP//\"/\\\"}\"" )
}

### KUBEVIRT BOOTSTRAP

function kubevirt_bootstrap {
    kubevirt_dependencies
    if [[ "${DEPENDENCIES_ONLY}" == "true" ]]; then
        return 0
    fi
    kubevirt_deploy
    if [[ "${KUBEVIRT_SOFTWARE_EMULATION}" == "true" ]]; then 
        kubevirt_enable_emulation
    fi
}

function kubevirt_dependencies {
    if [[ ! -f $(which virtctl || true) || "${FULL_INSTALL}" == "true" ]]; then
        echo "Installing virtctl"
        curl -fLo virtctl https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VIRTCTL_VERSION}/virtctl-${KUBEVIRT_VIRTCTL_VERSION}-${OS}-amd64 &> ${REDIR}
        sudocmd install $(pwd)/virtctl /usr/local/bin/
        rm $(pwd)/virtctl &> ${REDIR} || true
    fi
}

function kubevirt_deploy {
    echo "Deploying kubevirt"
    eval "echo -e \"${KUBEVIRT_YAML//\"/\\\"}\"" | 
    sed 's/@@NODENAME@@/$(NODE_NAME)/' | 
    sed 's/@@MYPODIP@@/$(MY_POD_IP)/' | 
        kubectl create -f - &> ${REDIR}
}

function kubevirt_enable_emulation {
    echo "Enabling kubevirt software emulation"
    kubectl create configmap -n kubevirt kubevirt-config --from-literal debug.useEmulation=true
}

IFS=''  read -r -d '\0' KUBEVIRT_YAML << "EOL"
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt
---
apiVersion: v1
kind: Service
metadata:
  labels:
    kubevirt.io: ""
    prometheus.kubevirt.io: ""
  name: kubevirt-prometheus-metrics
  namespace: kubevirt
spec:
  ports:
  - name: metrics
    port: 443
    protocol: TCP
    targetPort: metrics
  selector:
    prometheus.kubevirt.io: ""

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
    kubevirt.io: ""
  name: kubevirt.io:default
rules:
- apiGroups:
  - subresources.kubevirt.io
  resources:
  - version
  verbs:
  - get
  - list
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubevirt.io: ""
  name: kubevirt.io:default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubevirt.io:default
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:authenticated
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:unauthenticated
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubevirt.io: ""
    rbac.authorization.k8s.io/aggregate-to-admin: "true"
  name: kubevirt.io:admin
rules:
- apiGroups:
  - subresources.kubevirt.io
  resources:
  - virtualmachineinstances/console
  - virtualmachineinstances/vnc
  verbs:
  - get
- apiGroups:
  - subresources.kubevirt.io
  resources:
  - virtualmachines/restart
  verbs:
  - put
  - update
- apiGroups:
  - kubevirt.io
  resources:
  - virtualmachines
  - virtualmachineinstances
  - virtualmachineinstancepresets
  - virtualmachineinstancereplicasets
  verbs:
  - get
  - delete
  - create
  - update
  - patch
  - list
  - watch
  - deletecollection
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubevirt.io: ""
    rbac.authorization.k8s.io/aggregate-to-edit: "true"
  name: kubevirt.io:edit
rules:
- apiGroups:
  - subresources.kubevirt.io
  resources:
  - virtualmachineinstances/console
  - virtualmachineinstances/vnc
  verbs:
  - get
- apiGroups:
  - subresources.kubevirt.io
  resources:
  - virtualmachines/restart
  verbs:
  - put
  - update
- apiGroups:
  - kubevirt.io
  resources:
  - virtualmachines
  - virtualmachineinstances
  - virtualmachineinstancepresets
  - virtualmachineinstancereplicasets
  verbs:
  - get
  - delete
  - create
  - update
  - patch
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubevirt.io: ""
    rbac.authorization.k8s.io/aggregate-to-view: "true"
  name: kubevirt.io:view
rules:
- apiGroups:
  - kubevirt.io
  resources:
  - virtualmachines
  - virtualmachineinstances
  - virtualmachineinstancepresets
  - virtualmachineinstancereplicasets
  verbs:
  - get
  - list
  - watch
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-apiserver
  namespace: kubevirt
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-apiserver
rules:
- apiGroups:
  - admissionregistration.k8s.io
  resources:
  - validatingwebhookconfigurations
  - mutatingwebhookconfigurations
  verbs:
  - get
  - create
  - update
- apiGroups:
  - apiregistration.k8s.io
  resources:
  - apiservices
  verbs:
  - get
  - create
  - update
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - list
- apiGroups:
  - ""
  resources:
  - pods/exec
  verbs:
  - create
- apiGroups:
  - kubevirt.io
  resources:
  - virtualmachines
  - virtualmachineinstances
  - virtualmachineinstancemigrations
  verbs:
  - get
  - list
  - watch
  - delete
- apiGroups:
  - kubevirt.io
  resources:
  - virtualmachineinstancepresets
  verbs:
  - watch
  - list
- apiGroups:
  - ""
  resourceNames:
  - extension-apiserver-authentication
  resources:
  - configmaps
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - limitranges
  verbs:
  - watch
  - list
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-apiserver
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubevirt-apiserver
subjects:
- kind: ServiceAccount
  name: kubevirt-apiserver
  namespace: kubevirt
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-apiserver-auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: kubevirt-apiserver
  namespace: kubevirt
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-apiserver
  namespace: kubevirt
rules:
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
  - list
  - delete
  - update
  - create
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-apiserver
  namespace: kubevirt
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: kubevirt-apiserver
subjects:
- kind: ServiceAccount
  name: kubevirt-apiserver
  namespace: kubevirt
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-controller
  namespace: kubevirt
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-controller
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - configmaps
  - endpoints
  verbs:
  - get
  - list
  - watch
  - delete
  - update
  - create
- apiGroups:
  - ""
  resources:
  - events
  verbs:
  - update
  - create
  - patch
- apiGroups:
  - ""
  resources:
  - pods/finalizers
  verbs:
  - update
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
  - list
  - watch
  - update
  - patch
- apiGroups:
  - ""
  resources:
  - persistentvolumeclaims
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - kubevirt.io
  resources:
  - '*'
  verbs:
  - '*'
- apiGroups:
  - cdi.kubevirt.io
  resources:
  - '*'
  verbs:
  - '*'
- apiGroups:
  - k8s.cni.cncf.io
  resources:
  - network-attachment-definitions
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubevirt-controller
subjects:
- kind: ServiceAccount
  name: kubevirt-controller
  namespace: kubevirt
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-handler
  namespace: kubevirt
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-handler
rules:
- apiGroups:
  - kubevirt.io
  resources:
  - virtualmachineinstances
  verbs:
  - update
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - secrets
  - persistentvolumeclaims
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - patch
- apiGroups:
  - ""
  resources:
  - events
  verbs:
  - create
  - patch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-handler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubevirt-handler
subjects:
- kind: ServiceAccount
  name: kubevirt-handler
  namespace: kubevirt
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-handler
  namespace: kubevirt
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  labels:
    kubevirt.io: ""
  name: kubevirt-handler
  namespace: kubevirt
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: kubevirt-handler
subjects:
- kind: ServiceAccount
  name: kubevirt-handler
  namespace: kubevirt

---
apiVersion: v1
kind: Service
metadata:
  labels:
    kubevirt.io: virt-api
  name: virt-api
  namespace: kubevirt
spec:
  ports:
  - port: 443
    protocol: TCP
    targetPort: 8443
  selector:
    kubevirt.io: virt-api
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    kubevirt.io: virt-api
  name: virt-api
  namespace: kubevirt
spec:
  replicas: 2
  selector:
    matchLabels:
      kubevirt.io: virt-api
  strategy: {}
  template:
    metadata:
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ""
        scheduler.alpha.kubernetes.io/tolerations: '[{"key":"CriticalAddonsOnly","operator":"Exists"}]'
      labels:
        kubevirt.io: virt-api
        prometheus.kubevirt.io: ""
      name: virt-api
    spec:
      containers:
      - command:
        - virt-api
        - --port
        - "8443"
        - --subresources-only
        - -v
        - "2"
        image: ${KUBEVIRT_IMAGE_REPOSITORY}/virt-api:${KUBEVIRT_VERSION}
        imagePullPolicy: IfNotPresent
        name: virt-api
        ports:
        - containerPort: 8443
          name: virt-api
          protocol: TCP
        - containerPort: 8443
          name: metrics
          protocol: TCP
        readinessProbe:
          httpGet:
            path: /apis/subresources.kubevirt.io/v1alpha3/healthz
            port: 8443
            scheme: HTTPS
          initialDelaySeconds: 15
          periodSeconds: 10
        resources: {}
      securityContext:
        runAsNonRoot: true
      serviceAccountName: kubevirt-apiserver

---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    kubevirt.io: virt-controller
  name: virt-controller
  namespace: kubevirt
spec:
  replicas: 2
  selector:
    matchLabels:
      kubevirt.io: virt-controller
  strategy: {}
  template:
    metadata:
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ""
        scheduler.alpha.kubernetes.io/tolerations: '[{"key":"CriticalAddonsOnly","operator":"Exists"}]'
      labels:
        kubevirt.io: virt-controller
        prometheus.kubevirt.io: ""
      name: virt-controller
    spec:
      containers:
      - command:
        - virt-controller
        - --launcher-image
        - ${KUBEVIRT_IMAGE_REPOSITORY}/virt-launcher:${KUBEVIRT_VERSION}
        - --port
        - "8443"
        - -v
        - "2"
        image: ${KUBEVIRT_IMAGE_REPOSITORY}/virt-controller:${KUBEVIRT_VERSION}
        imagePullPolicy: IfNotPresent
        livenessProbe:
          failureThreshold: 8
          httpGet:
            path: /healthz
            port: 8443
            scheme: HTTPS
          initialDelaySeconds: 15
          timeoutSeconds: 10
        name: virt-controller
        ports:
        - containerPort: 8443
          name: metrics
          protocol: TCP
        readinessProbe:
          httpGet:
            path: /leader
            port: 8443
            scheme: HTTPS
          initialDelaySeconds: 15
          timeoutSeconds: 10
        resources: {}
      securityContext:
        runAsNonRoot: true
      serviceAccountName: kubevirt-controller

---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    kubevirt.io: virt-handler
  name: virt-handler
  namespace: kubevirt
spec:
  selector:
    matchLabels:
      kubevirt.io: virt-handler
  template:
    metadata:
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ""
        scheduler.alpha.kubernetes.io/tolerations: '[{"key":"CriticalAddonsOnly","operator":"Exists"}]'
      labels:
        kubevirt.io: virt-handler
        prometheus.kubevirt.io: ""
      name: virt-handler
    spec:
      containers:
      - command:
        - virt-handler
        - --port
        - "8443"
        - --hostname-override
        - @@NODENAME@@
        - --pod-ip-address
        - @@MYPODIP@@
        - -v
        - "2"
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: MY_POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        image: ${KUBEVIRT_IMAGE_REPOSITORY}/virt-handler:${KUBEVIRT_VERSION}
        imagePullPolicy: IfNotPresent
        name: virt-handler
        ports:
        - containerPort: 8443
          name: metrics
          protocol: TCP
        resources: {}
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /var/run/kubevirt-libvirt-runtimes
          name: libvirt-runtimes
        - mountPath: /var/run/kubevirt
          name: virt-share-dir
        - mountPath: /var/run/kubevirt-private
          name: virt-private-dir
        - mountPath: /var/lib/kubelet/device-plugins
          name: device-plugin
      hostPID: true
      serviceAccountName: kubevirt-handler
      volumes:
      - hostPath:
          path: /var/run/kubevirt-libvirt-runtimes
        name: libvirt-runtimes
      - hostPath:
          path: /var/run/kubevirt
        name: virt-share-dir
      - hostPath:
          path: /var/run/kubevirt-private
        name: virt-private-dir
      - hostPath:
          path: /var/lib/kubelet/device-plugins
        name: device-plugin
  updateStrategy:
    type: RollingUpdate

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  labels:
    kubevirt.io: ""
  name: virtualmachineinstances.kubevirt.io
spec:
  additionalPrinterColumns:
  - JSONPath: .metadata.creationTimestamp
    name: Age
    type: date
  - JSONPath: .status.phase
    name: Phase
    type: string
  - JSONPath: .status.interfaces[0].ipAddress
    name: IP
    type: string
  - JSONPath: .status.nodeName
    name: NodeName
    type: string
  group: kubevirt.io
  names:
    kind: VirtualMachineInstance
    plural: virtualmachineinstances
    shortNames:
    - vmi
    - vmis
    singular: virtualmachineinstance
  scope: Namespaced
  version: v1alpha3

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  labels:
    kubevirt.io: ""
  name: virtualmachineinstancereplicasets.kubevirt.io
spec:
  additionalPrinterColumns:
  - JSONPath: .spec.replicas
    description: Number of desired VirtualMachineInstances
    name: Desired
    type: integer
  - JSONPath: .status.replicas
    description: Number of managed and not final or deleted VirtualMachineInstances
    name: Current
    type: integer
  - JSONPath: .status.readyReplicas
    description: Number of managed VirtualMachineInstances which are ready to receive
      traffic
    name: Ready
    type: integer
  - JSONPath: .metadata.creationTimestamp
    name: Age
    type: date
  group: kubevirt.io
  names:
    kind: VirtualMachineInstanceReplicaSet
    plural: virtualmachineinstancereplicasets
    shortNames:
    - vmirs
    - vmirss
    singular: virtualmachineinstancereplicaset
  scope: Namespaced
  subresources:
    scale:
      labelSelectorPath: .status.labelSelector
      specReplicasPath: .spec.replicas
      statusReplicasPath: .status.replicas
  version: v1alpha3

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  labels:
    kubevirt.io: ""
  name: virtualmachineinstancepresets.kubevirt.io
spec:
  group: kubevirt.io
  names:
    kind: VirtualMachineInstancePreset
    plural: virtualmachineinstancepresets
    shortNames:
    - vmipreset
    - vmipresets
    singular: virtualmachineinstancepreset
  scope: Namespaced
  version: v1alpha3

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  labels:
    kubevirt.io: ""
  name: virtualmachines.kubevirt.io
spec:
  additionalPrinterColumns:
  - JSONPath: .metadata.creationTimestamp
    name: Age
    type: date
  - JSONPath: .spec.running
    name: Running
    type: boolean
  - JSONPath: .spec.volumes[0].name
    description: Primary Volume
    name: Volume
    type: string
  group: kubevirt.io
  names:
    kind: VirtualMachine
    plural: virtualmachines
    shortNames:
    - vm
    - vms
    singular: virtualmachine
  scope: Namespaced
  version: v1alpha3

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  labels:
    kubevirt.io: ""
  name: virtualmachineinstancemigrations.kubevirt.io
spec:
  group: kubevirt.io
  names:
    kind: VirtualMachineInstanceMigration
    plural: virtualmachineinstancemigrations
    shortNames:
    - vmim
    - vmims
    singular: virtualmachineinstancemigration
  scope: Namespaced
  version: v1alpha3
\0
EOL


### METALLB CONFIGURATION

IFS='' read -r -d '\0' METALLB_HELP <<"EOL"
METALLB_VERSION
  Description: specifies the version to use for metallb
  Default: ${DEFAULT_METALLB_VERSION}
  Example: METALLB_VERSION=v0.9.3
  Current: METALLB_VERSION=${METALLB_VERSION}

METALLB_PEER_ADDRESS
  Description: specifies the bgp peer that metallb daemonsets should peer with (one running per node)
    (if not set, the feature will be disabled)
  Default: unset
  Example: METALLB_PEER_ADDRESS=192.168.100.1
  Current: METALLB_PEER_ADDRESS=${METALLB_PEER_ADDRESS}

METALLB_PEER_ASN
  Description: specifies the AS number of the bgp peer (router / switch where nodes are connected)
  Default: ${DEFAULT_METALLB_PEER_ASN}
  Example: METALLB_PEER_ASN=65554
  Current: METALLB_PEER_ASN=${METALLB_PEER_ASN}

METALLB_LOCAL_ASN
  Description: specifies the AS number of the local bgp session (metallb daemonset)
  Default: ${DEFAULT_METALLB_LOCAL_ASN}
  Example: METALLB_LOCAL_ASN=65555
  Current: METALLB_LOCAL_ASN=${METALLB_LOCAL_ASN}

METALLB_POOL_DEFAULT_CIDR
  Description: specifies the default ip pool to use for allocating external load-balancer ips
  Default: ${DEFAULT_METALLB_POOL_DEFAULT_CIDR}
  Example: METALLB_POOL_DEFAULT_CIDR=10.20.0.0/18
  Current: METALLB_POOL_DEFAULT_CIDR=${METALLB_POOL_DEFAULT_CIDR}

METALLB_POOL_VM_CIDR
  Description: specifies the vm ip pool to use for allocating external load-balancer ips
  Default: ${DEFAULT_METALLB_POOL_VM_CIDR}
  Example: METALLB_POOL_VM_CIDR=10.20.64.0/18
  Current: METALLB_POOL_VM_CIDR=${METALLB_POOL_VM_CIDR}

METALLB_COMMUNITY_NOADVERTISE
  Description: specifies the bgp noadvertise community to use on routes advertised by metallb sessions
  Default: ${DEFAULT_METALLB_COMMUNITY_NOADVERTISE}
  Example: METALLB_COMMUNITY_NOADVERTISE=65555:65300
  Current: METALLB_COMMUNITY_NOADVERTISE=${METALLB_COMMUNITY_NOADVERTISE}
\0
EOL

function __set_metallb_defaults {
    local DEFAULT_METALLB_VERSION=v0.9.4
    local DEFAULT_METALLB_PEER_ADDRESS=""
    local DEFAULT_METALLB_PEER_ASN=65500
    local DEFAULT_METALLB_LOCAL_ASN=65501
    local DEFAULT_METALLB_POOL_DEFAULT_CIDR=${CLUSTER_LB_DEFAULT_CIDR}
    local DEFAULT_METALLB_POOL_VM_CIDR=${CLUSTER_LB_VM_CIDR}
    local DEFAULT_METALLB_COMMUNITY_NOADVERTISE=65535:65282

    if [[ "${METALLB_VERSION:-}" == "" ]]; then
        METALLB_VERSION=${DEFAULT_METALLB_VERSION}
    fi
    if [[ "${METALLB_PEER_ADDRESS:-}" == "" ]]; then
        METALLB_PEER_ADDRESS=${DEFAULT_METALLB_PEER_ADDRESS}
    fi
    if [[ "${METALLB_PEER_ASN:-}" == "" ]]; then
        METALLB_PEER_ASN=${DEFAULT_METALLB_PEER_ASN}
    fi
    if [[ "${METALLB_LOCAL_ASN:-}" == "" ]]; then
        METALLB_LOCAL_ASN=${DEFAULT_METALLB_LOCAL_ASN}
    fi
    if [[ "${METALLB_POOL_DEFAULT_CIDR:-}" == "" ]]; then
        METALLB_POOL_DEFAULT_CIDR=${DEFAULT_METALLB_POOL_DEFAULT_CIDR}
    fi
    if [[ "${METALLB_POOL_VM_CIDR:-}" == "" ]]; then
        METALLB_POOL_VM_CIDR=${DEFAULT_METALLB_POOL_VM_CIDR}
    fi
    if [[ "${METALLB_COMMUNITY_NOADVERTISE:-}" == "" ]]; then
        METALLB_COMMUNITY_NOADVERTISE=${DEFAULT_METALLB_COMMUNITY_NOADVERTISE}
    fi

    DEFAULTS_METALLB=$( eval "echo -e \"${METALLB_HELP//\"/\\\"}\"" )
}

### METALLB BOOTSTRAP

function metallb_bootstrap {
    if [[ "$METALLB_PEER_ADDRESS" == "" ]]; then
        return 0
    fi
    metallb_install
}

function metallb_install {
    eval "echo \"${METALLB_CONF//\"/\\\"}\"" | \
        kubectl create -f - &> ${REDIR}
    helm repo update &> ${REDIR}
    helm upgrade --install --namespace kube-system metallb stable/metallb --version=${METALLB_VERSION} \
        &> ${REDIR}
}

IFS=''  read -r -d '\0' METALLB_CONF << "EOL"
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: kube-system
  name: metallb-config
data:
  config: |
    peers:
    - peer-address: ${METALLB_PEER_ADDRESS}
      peer-asn: ${METALLB_PEER_ASN}
      my-asn: ${METALLB_LOCAL_ASN}
    address-pools:
    - name: default
      protocol: bgp
      addresses:
      - ${METALLB_POOL_DEFAULT_CIDR}
      auto-assign: false
      bgp-advertisements:
      - aggregation-length: 32
        localpref: 100
        communities:
        - no-advertise
      - aggregation-length: ${METALLB_POOL_DEFAULT_CIDR##*/}
    - name: vm-pool
      protocol: bgp
      addresses:
      - ${METALLB_POOL_VM_CIDR}
      bgp-advertisements:
      - aggregation-length: 32
        localpref: 100
        communities:
        - no-advertise
      - aggregation-length: ${METALLB_POOL_VM_CIDR##*/}
    bgp-communities:
      no-advertise: ${METALLB_COMMUNITY_NOADVERTISE}
\0
EOL

function bootstrapper_help {
    eval "echo -e \"${BOOTSTRAPPER_TEMPLATE}\"" | cat
}

IFS='' read -r -d '\0' BOOTSTRAPPER_TEMPLATE <<"EOL"
# FOLLOWING ENVIRONMENT VARIABLES MODIFY INSTALLATION BEHAVIOR

### BOOTSTRAPPER

${DEFAULTS_BOOTSTRAPPER}


### CLUSTER
${DEFAULTS_CLUSTER}


### HA (configures VIP load-balancing using ha-proxy/heartbeat)
${DEFAULTS_HA}


### KUBERNETES
${DEFAULTS_KUBERNETES}


### MINIKUBE (used if bootstrapper is minikube)
${DEFAULTS_MINIKUBE}


### CNI (NETWORKING)
${DEFAULTS_CNI}


### HELM
${DEFAULTS_HELM}


### KUBEVIRT
${DEFAULTS_KUBEVIRT}


### METALLB (used for external load-balancer services)
${DEFAULTS_METALLB}
\0
EOL


function bootstrapper_info {
    eval "echo -e \"${BOOTSTRAPPER_INFO}\"" | cat
}

IFS='' read -r -d '\0' BOOTSTRAPPER_INFO <<"EOL"
host info:
    OS: ${OS}
    OS_DISTRIBUTOR: ${OS_DISTRIBUTOR}
    HOSTNAME: ${HOSTNAME}
    DEFAULT_INTERFACE: ${DEFAULT_INTERFACE}
    DEFAULT_INTERFACE_IP: ${DEFAULT_INTERFACE_IP}


# PROVISIONING CONFIGURATION

bootstrapper:
    DEBUG: ${DEBUG}
    BOOTSTRAPPER: ${BOOTSTRAPPER}
    BOOTSTRAPPER_DOCKER_REGISTRY: ${BOOTSTRAPPER_DOCKER_REGISTRY}
    DEPENDENCIES_ONLY: ${DEPENDENCIES_ONLY}

cluster:
    CLUSTER_CONTROLPLANE_ENDPOINT: ${CLUSTER_CONTROLPLANE_ENDPOINT}
    CLUSTER_ID: ${CLUSTER_ID}
    CLUSTER_LB_VM_CIDR: ${CLUSTER_LB_VM_CIDR}
    CLUSTER_LB_DEFAULT_CIDR: ${CLUSTER_LB_DEFAULT_CIDR}
    CLUSTER_POD_CIDR: ${CLUSTER_POD_CIDR}
    CLUSTER_SERVICE_CIDR: ${CLUSTER_SERVICE_CIDR}

ha (heartbeat / haproxy):
    HA_CONTROLPLANE_NODES: ${HA_CONTROLPLANE_NODES}
    HA_HEARTBEAT_AUTH_MD5SUM: ${HA_HEARTBEAT_AUTH_MD5SUM}
    HA_HEARTBEAT_MCAST_GROUP: ${HA_HEARTBEAT_MCAST_GROUP}
    HA_HEARTBEAT_UDP_PORT: ${HA_HEARTBEAT_UDP_PORT}

kubernetes:
    KUBERNETES_VERSION: ${KUBERNETES_VERSION}
    KUBERNETES_IMAGE_REPOSITORY: ${KUBERNETES_IMAGE_REPOSITORY}
    KUBERNETES_CONTROLPLANE_ENDPOINT: ${KUBERNETES_CONTROLPLANE_ENDPOINT}
    KUBERNETES_APISERVER_LOCAL_BIND_PORT: ${KUBERNETES_APISERVER_LOCAL_BIND_PORT}
    KUBERNETES_POD_CIDR: ${KUBERNETES_POD_CIDR}
    KUBERNETES_SERVICE_CIDR: ${KUBERNETES_SERVICE_CIDR}
    KUBERNETES_OIDC_ISSUER_URL: ${KUBERNETES_OIDC_ISSUER_URL}
    KUBERNETES_OIDC_CLIENT_ID: ${KUBERNETES_OIDC_CLIENT_ID}

minikube (only applicable if bootstrapper is minikube):
    MINIKUBE_CPUS: ${MINIKUBE_CPUS}
    MINIKUBE_MEMORY: ${MINIKUBE_MEMORY}
    MINIKUBE_DISK_SIZE: ${MINIKUBE_DISK_SIZE}
    MINIKUBE_VM_DRIVER: ${MINIKUBE_VM_DRIVER}
    MINIKUBE_REGISTRY_NODEPORT: ${MINIKUBE_REGISTRY_NODEPORT:-}

cni (container networking):
    CNI_PLUGINS_VERSION: ${CNI_PLUGINS_VERSION}
    CNI_PLUGINS_IMAGE_REPOSITORY: ${CNI_PLUGINS_IMAGE_REPOSITORY}
    CNI_MULTUS_VERSION: ${CNI_MULTUS_VERSION}
    CNI_MULTUS_IMAGE_REPOSITORY: ${CNI_MULTUS_IMAGE_REPOSITORY}
    CNI_FLANNEL_VERSION: ${CNI_FLANNEL_VERSION}
    CNI_FLANNEL_IMAGE_REPOSITORY: ${CNI_FLANNEL_IMAGE_REPOSITORY}

helm:
    HELM_VERSION: ${HELM_VERSION}

kubefed:
    KUBEFED_VERSION: ${KUBEFED_VERSION}
    KUBEFED_KUBEFEDCTL_VERSION: ${KUBEFED_KUBEFEDCTL_VERSION}
    KUBEFED_IMAGE_REPOSITORY: ${KUBEFED_IMAGE_REPOSITORY}
    KUBEFED_KUBEFEDCTL_BASE_URL: ${KUBEFED_KUBEFEDCTL_BASE_URL}
    KUBEFED_SYSTEM_NAMESPACE: ${KUBEFED_SYSTEM_NAMESPACE}

kubevirt:
    KUBEVIRT_VERSION: ${KUBEVIRT_VERSION}
    KUBEVIRT_VIRTCTL_VERSION: ${KUBEVIRT_VIRTCTL_VERSION}
    KUBEVIRT_IMAGE_REPOSITORY: ${KUBEVIRT_IMAGE_REPOSITORY}
    KUBEVIRT_SOFTWARE_EMULATION: ${KUBEVIRT_SOFTWARE_EMULATION}

metallb (load-balancer for kubernetes services, only applicable if METALLB_PEER_ADDRESS is set):
    METALLB_VERSION: ${METALLB_VERSION}
    METALLB_PEER_ADDRESS: ${METALLB_PEER_ADDRESS}
    METALLB_PEER_ASN: ${METALLB_PEER_ASN}
    METALLB_LOCAL_ASN: ${METALLB_LOCAL_ASN}
    METALLB_POOL_DEFAULT_CIDR: ${METALLB_POOL_DEFAULT_CIDR}
    METALLB_POOL_VM_CIDR: ${METALLB_POOL_VM_CIDR}
    METALLB_COMMUNITY_NOADVERTISE: ${METALLB_COMMUNITY_NOADVERTISE}
\0
EOL

function bootstrap {
    permissions_test

    sudo mkdir -p /usr/local/bin &> /dev/null || true

    if [[ "${OS}" == "linux" ]]; then
        sudocmd apt-get -yq update
    fi

    ha_bootstrap

    if [[ "${BOOTSTRAPPER}" == "minikube" ]]; then
        minikube_bootstrap
    elif [[ "${BOOTSTRAPPER}" == "kubeadm" ]]; then
        kubeadm_bootstrap
    fi
    
    cni_bootstrap

    helm_bootstrap

    kubefed_bootstrap

    kubevirt_bootstrap

    metallb_bootstrap

    echo "bootstrapping complete"
    if [[ -n "${KUBEADM_OUTPUT}" ]]; then
        echo -n "${KUBEADM_OUTPUT}" | \
        egrep -A 500 "Kubernetes control-plane has initialized successfully!"
    fi
    echo
}

function permissions_test {
    USER_ID=`id -u`
    if [[ ${USER_ID} -eq 0 ]]; then
        echo "This script must be run as a non-root user with sudo privileges."
        exit 1
    fi
    SUDO_ID=`sudo id -u`
    if [[ ${SUDO_ID} -ne 0 || "${SUDO_ID}" == "" ]]; then
        echo "This script requires user to have sudo privileges."
        exit 1
    fi
}

function main {
    # set -euo pipefail
    __set_variables

    local allow_install=false 

    if [[ "${OS}" == "darwin" ]]; then
        if [[ "${BOOTSTRAPPER}" != "minikube" ]]; then
            echo "This script only supports bootstrapping a mac/darwin system using minikube BOOTSTRAPPER"
            return 1
        fi
    elif [[ "${OS}" == "darwin" ]]; then
        if [[ "${BOOTSTRAPPER}" != "kubeadm" && "${BOOTSTRAPPER}" != "minikube" ]]; then
            echo "This script only supports bootstrapping a linux system using a BOOTSTRAPPER of minikube or kubeadm."
            return 1
        fi
    fi

    for var in "$@"; do
        case "$var" in
            "-f")
                allow_install=true
                ;;
            "-h" | "help")
                allow_install=false
                bootstrapper_help
                exit 0
                ;;
        esac
    done

    bootstrapper_info

    echo "bootstrapping with ${BOOTSTRAPPER} on ${OS}"

    if [[ "${allow_install}" == "false" ]]; then
        echo -n "Proceed with installation/provisioning? [yes or no]: "
        
        read yno
        case $yno in

                [yY] | [yY][Ee][Ss] )
                        allow_install=true
                        ;;

                [nN] | [n|N][O|o] )
                        allow_install=false
                        exit 1
                        ;;
                *) echo "Invalid input"
                    exit 1
                    ;;
        esac
    fi

    if [[ "${DEBUG}" == "true" ]]; then
        set -x
        REDIR="/dev/null"
    else
        unset DEBUG
        REDIR="/dev/null"
    fi

    bootstrap
}


[[ "$0" == "$BASH_SOURCE" ]] && main "$@"
