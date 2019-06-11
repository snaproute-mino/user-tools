#!/bin/bash


### HELM CONFIGURATION

IFS='' read -r -d '' HELM_HELP <<"EOL"
HELM_VERSION
  Description: specifies which version of helm to provision
  Default: ${DEFAULT_HELM_VERSION}
  Current: HELM_VERSION=${HELM_VERSION}
EOL

function __set_helm_defaults {
    local DEFAULT_HELM_VERSION=v2.11.0

    if [[ -z "${HELM_VERSION}" ]]; then
        HELM_VERSION=${DEFAULT_HELM_VERSION}
    fi

    DEFAULTS_HELM=$( eval "echo -e \"${HELM_HELP//\"/\\\"}\"" )
}


### HELM INSTALL

function helm_bootstrap {
    helm_dependencies
    if [[ "${DEPENDENCIES_ONLY}" == "true" ]]; then
        return 0
    fi
    helm_init
}

function helm_dependencies {
    if [[ ! -f $(which helm) || -n ${FULL_INSTALL} ]]; then
        echo "Installing helm"
        curl https://raw.githubusercontent.com/helm/helm/master/scripts/get > get_helm.sh 2> /dev/null && \
            chmod 700 get_helm.sh && \
            ./get_helm.sh --version ${HELM_VERSION} &> ${REDIR}
            rm ./get_helm.sh &> ${REDIR} || true
    fi
}

function helm_init {
    echo "Initializing helm"
    helm init --client-only &> ${REDIR}
    sudo chown -R $(id -u):$(id -g) ${HOME}/.helm/ &> ${REDIR}
    helm repo update &> ${REDIR}
}

### SNAPROUTE REPO CONFIGURATION

IFS='' read -r -d '' SNAPROUTE_HELP <<"EOL"
SNAPROUTE_CNNOS_HELM_REPO_NAME
  Description: specifies name to use for SnapRoute CN-NOS repo
  Default: ${DEFAULT_SNAPROUTE_CNNOS_HELM_REPO_NAME}
  Current: SNAPROUTE_CNNOS_HELM_REPO_NAME=${SNAPROUTE_CNNOS_HELM_REPO_NAME}

SNAPROUTE_CNNOS_HELM_REPO_URL
  Description: specifies url to use for SnapRoute CN-NOS repo
  Default: ${DEFAULT_SNAPROUTE_CNNOS_HELM_REPO_URL}
  Current: SNAPROUTE_CNNOS_HELM_REPO_URL=${SNAPROUTE_CNNOS_HELM_REPO_URL}

SNAPROUTE_VM_HELM_REPO_NAME
  Description: specifies name to use for SnapRoute VM repo
  Default: ${DEFAULT_SNAPROUTE_VM_HELM_REPO_NAME}
  Current: SNAPROUTE_VM_HELM_REPO_NAME=${SNAPROUTE_VM_HELM_REPO_NAME}

SNAPROUTE_VM_HELM_REPO_URL
  Description: specifies url to use for SnapRoute VM repo
  Default: ${DEFAULT_SNAPROUTE_VM_HELM_REPO_URL}
  Current: SNAPROUTE_VM_HELM_REPO_URL=${HELM_SNAPROUTE_VM_HELM_REPO_URLVERSION}
EOL

function __set_snaproute_defaults {
    local DEFAULT_SNAPROUTE_CNNOS_HELM_REPO_NAME=cnnos-release
    local DEFAULT_SNAPROUTE_CNNOS_HELM_REPO_URL=https://repo.snaproute.com/chartrepo/release
    local DEFAULT_SNAPROUTE_VM_HELM_REPO_NAME=cnnos-virtualization
    local DEFAULT_SNAPROUTE_VM_HELM_REPO_URL=https://repo.snaproute.com/chartrepo/virtualization

    if [[ -z "${SNAPROUTE_CNNOS_HELM_REPO_NAME}" ]]; then
        SNAPROUTE_CNNOS_HELM_REPO_NAME=${DEFAULT_SNAPROUTE_CNNOS_HELM_REPO_NAME} &> ${REDIR}
    fi
    if [[ -z "${SNAPROUTE_CNNOS_HELM_REPO_URL}" ]]; then
        SNAPROUTE_CNNOS_HELM_REPO_URL=${DEFAULT_SNAPROUTE_CNNOS_HELM_REPO_URL} &> ${REDIR}
    fi
    if [[ -z "${SNAPROUTE_VM_HELM_REPO_NAME}" ]]; then
        SNAPROUTE_VM_HELM_REPO_NAME=${DEFAULT_SNAPROUTE_VM_HELM_REPO_NAME} &> ${REDIR}
    fi
    if [[ -z "${SNAPROUTE_VM_HELM_REPO_URL}" ]]; then
        SNAPROUTE_VM_HELM_REPO_URL=${DEFAULT_SNAPROUTE_VM_HELM_REPO_URL} &> ${REDIR}
    fi


    DEFAULTS_SNAPROUTE=$( eval "echo -e \"${SNAPROUTE_HELP//\"/\\\"}\"" )
}

### HELM INSTALL

function snaproute_bootstrap {
    helm repo add ${SNAPROUTE_CNNOS_HELM_REPO_NAME} ${SNAPROUTE_CNNOS_HELM_REPO_URL}
    helm repo add ${SNAPROUTE_VM_HELM_REPO_NAME} ${SNAPROUTE_VM_HELM_REPO_URL}
    helm repo update &> ${REDIR}
}

function bootstrap {
    permissions_test

    sudo mkdir -p /usr/local/bin &> /dev/null || true

    helm_bootstrap

    snaproute_bootstrap

    echo "installation complete"
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

function __set_variables {
    FAILED_VALIDATION=false

    OS=`uname | tr '[:upper:]' '[:lower:]'`
    OS_DISTRIBUTOR=`lsb_release -is`
    HOSTNAME=`hostname`
    DEFAULT_INTERFACE="$(awk '$2 == 00000000 { print $1 }' /proc/net/route)"
    DEFAULT_INTERFACE_IP=`ip addr show dev "${DEFAULT_INTERFACE}" | awk '$1 == "inet" && $3 == "brd" { sub("/.*", "", $2); print $2 }'`
    ADDITIONAL_FILES_PATH_PREPEND=""

    __set_helm_defaults
    __set_snaproute_defaults
}

function bootstrapper_help {
    eval "echo -e \"${BOOTSTRAPPER_TEMPLATE}\"" | cat
}

IFS='' read -r -d '' BOOTSTRAPPER_TEMPLATE <<"EOL"
# FOLLOWING ENVIRONMENT VARIABLES MODIFY INSTALLATION BEHAVIOR

### HELM
${DEFAULTS_HELM}


### SNAPROUTE
${DEFAULTS_SNAPROUTE}
EOL


function bootstrapper_info {
    eval "echo -e \"${BOOTSTRAPPER_INFO}\"" | cat
}

IFS='' read -r -d '' BOOTSTRAPPER_INFO <<"EOL"
host info:
    OS: ${OS}
    OS_DISTRIBUTOR: ${OS_DISTRIBUTOR}
    HOSTNAME: ${HOSTNAME}
    DEFAULT_INTERFACE: ${DEFAULT_INTERFACE}
    DEFAULT_INTERFACE_IP: ${DEFAULT_INTERFACE_IP}


# CONFIGURATION

helm:
    HELM_VERSION: ${HELM_VERSION}

snaproute:
    SNAPROUTE_CNNOS_HELM_REPO_NAME: ${SNAPROUTE_CNNOS_HELM_REPO_NAME}
    SNAPROUTE_CNNOS_HELM_REPO_URL: ${SNAPROUTE_CNNOS_HELM_REPO_URL}
    SNAPROUTE_VM_HELM_REPO_NAME: ${SNAPROUTE_VM_HELM_REPO_NAME}
    SNAPROUTE_VM_HELM_REPO_URL: ${SNAPROUTE_VM_HELM_REPO_URL}
EOL


function main {
    # set -euo pipefail
    __set_variables

    local allow_install=false 

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

    if [[ "${allow_install}" == "false" ]]; then
        echo -n "Proceed with installation? [yes or no]: "
        
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
        REDIR="/dev/stderr"
    else
        unset DEBUG
        REDIR="/dev/null"
    fi

    bootstrap
}


[[ "$0" == "$BASH_SOURCE" ]] && main "$@"
