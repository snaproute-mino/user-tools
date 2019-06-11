#!/bin/bash


IFS='' read -r -d '' SKAFFOLD_HELP <<"EOL"
SKAFFOLD_VERSION
  Description: specifies which version of skaffold to use (depends on version of skaffold file)
  Default: ${DEFAULT_SKAFFOLD_VERSION}
  Current: SKAFFOLD_VERSION=${SKAFFOLD_VERSION}
EOL

function __set_skaffold_defaults {
    local DEFAULT_SKAFFOLD_VERSION=v0.31.0

    if [[ -z "${SKAFFOLD_VERSION}" ]]; then
        SKAFFOLD_VERSION=${DEFAULT_SKAFFOLD_VERSION}
    fi

    DEFAULTS_SKAFFOLD=$( eval "echo -e \"${SKAFFOLD_HELP//\"/\\\"}\"" )
}

function skaffold_install {
    if [[ ! -f $( which skaffold-${SKAFFOLD_VERSION} ) || -n ${FULL_INSTALL} ]]; then
        echo "Installing skaffold"
        curl -Lo skaffold-${SKAFFOLD_VERSION} https://storage.googleapis.com/skaffold/releases/${SKAFFOLD_VERSION}/skaffold-linux-amd64 && \
            sudo install ./skaffold-${SKAFFOLD_VERSION} /usr/local/bin/
        rm ./skaffold-${SKAFFOLD_VERSION} &> ${REDIR} || true
    fi
}

### ONIE CONFIGURATION

IFS='' read -r -d '' ONIE_HELP <<"EOL"
ONIE_IMAGE_REPOSITORY
  Description: specifies which registry / repository to use for onie container images
  Default: ${DEFAULT_ONIE_IMAGE_REPOSITORY}
  Current: ONIE_IMAGE_REPOSITORY=${ONIE_IMAGE_REPOSITORY}

ONIE_IMAGE_VERSION
  Description: specifies which version tag to use for onie container images
  Default: ${DEFAULT_ONIE_IMAGE_VERSION}
  Current: ONIE_IMAGE_VERSION=${ONIE_IMAGE_VERSION}

ONIE_DOCKER_CONTEXT
  Description: specifies which path to use for the onie docker context (dockerfile should reside in this directory)
  Default: $$(pwd)/onie
  Current: ONIE_DOCKER_CONTEXT=${ONIE_DOCKER_CONTEXT}
EOL

function __set_onie_defaults {
    local DEFAULT_ONIE_IMAGE_REPOSITORY=repo.snaproute.com/vm-infra/onie
    local DEFAULT_ONIE_IMAGE_VERSION=$( git describe --tag 2> /dev/null )
    if [[ $? -ne 0 || "${DEFAULT_ONIE_IMAGE_VERSION}" == "" ]]; then
        DEFAULT_ONIE_IMAGE_VERSION=v1.0
    fi
    local DEFAULT_ONIE_DOCKER_CONTEXT=$(pwd)/onie
    if [[ -z "${ONIE_IMAGE_REPOSITORY}" ]]; then
        ONIE_IMAGE_REPOSITORY=${DEFAULT_ONIE_IMAGE_REPOSITORY}
    fi
    if [[ -z "${ONIE_IMAGE_VERSION}" ]]; then
        ONIE_IMAGE_VERSION=${DEFAULT_ONIE_IMAGE_VERSION}
    fi
    if [[ -z "${ONIE_DOCKER_CONTEXT}" ]]; then
        ONIE_DOCKER_CONTEXT=${DEFAULT_ONIE_DOCKER_CONTEXT}
    fi

    DEFAULTS_ONIE=$( eval "echo -e \"${ONIE_HELP//\"/\\\"}\"" )
}

IFS='' read -r -d '' ONIE_SKAFFOLD_TEMPLATE <<"EOL"
apiVersion: skaffold/v1beta6
kind: Config
build:
  tagPolicy:
    envTemplate:
      template: "{{ if .IMAGE_REPOSITORY }}{{ .IMAGE_REPOSITORY }}/{{ .IMAGE_NAME }}:{{ if .TAG }}{{ .TAG }}{{ else }}dev{{ end }}{{ else }}{{.DOCKER_REGISTRY}}/{{.DOCKER_REPOSITORY}}/{{ .IMAGE_NAME }}:{{ if .TAG }}{{ .TAG }}{{ else }}dev{{ end }}{{ end }}"
  artifacts:
  - image: onie-8g
    context: ${ONIE_DOCKER_CONTEXT}
    docker:
      dockerfile: Dockerfile
      buildArgs:
        DISK_SIZE: "8"
  - image: onie-16g
    context: ${ONIE_DOCKER_CONTEXT}
    docker:
      dockerfile: Dockerfile
      buildArgs:
        DISK_SIZE: "16"
  - image: onie-32g
    context: ${ONIE_DOCKER_CONTEXT}
    docker:
      dockerfile: Dockerfile
      buildArgs:
        DISK_SIZE: "32"
  local:
    push: true
    useDockerCLI: true
deploy:
  helm:
    releases: []
EOL

function build_images {
    skaffold_install

    ONIE_SKAFFOLD=$( eval "echo -e \"${ONIE_SKAFFOLD_TEMPLATE//\"/\\\"}\"" )

    export IMAGE_REPOSITORY=${ONIE_IMAGE_REPOSITORY}
    export TAG=${ONIE_IMAGE_VERSION}
    echo -e "${ONIE_SKAFFOLD}" | cat | skaffold-${SKAFFOLD_VERSION} build -f -
}


function builder_help {
    eval "echo -e \"${BUILDER_TEMPLATE}\"" | cat
}

IFS='' read -r -d '' BUILDER_TEMPLATE <<"EOL"
# FOLLOWING ENVIRONMENT VARIABLES MODIFY INSTALLATION BEHAVIOR

### SKAFFOLD

${DEFAULTS_SKAFFOLD}


### ONIE

${DEFAULTS_ONIE}
EOL


function builder_info {
    eval "echo -e \"${ONIE_INFO}\"" | cat
}

IFS='' read -r -d '' ONIE_INFO <<"EOL"
host info:
    OS: ${OS}
    OS_DISTRIBUTOR: ${OS_DISTRIBUTOR}
    HOSTNAME: ${HOSTNAME}
    DEFAULT_INTERFACE: ${DEFAULT_INTERFACE}
    DEFAULT_INTERFACE_IP: ${DEFAULT_INTERFACE_IP}


# CONFIGURATION

skaffold:
    SKAFFOLD_VERSION: ${SKAFFOLD_VERSION}

onie:
    ONIE_IMAGE_REPOSITORY: ${ONIE_IMAGE_REPOSITORY}
    ONIE_IMAGE_VERSION: ${ONIE_IMAGE_VERSION}
EOL

function __set_variables {

    OS=`uname | tr '[:upper:]' '[:lower:]'`
    OS_DISTRIBUTOR=`lsb_release -is`
    HOSTNAME=`hostname`
    DEFAULT_INTERFACE="$(awk '$2 == 00000000 { print $1 }' /proc/net/route)"
    DEFAULT_INTERFACE_IP=`ip addr show dev "${DEFAULT_INTERFACE}" | awk '$1 == "inet" && $3 == "brd" { sub("/.*", "", $2); print $2 }'`

    __set_skaffold_defaults
    __set_onie_defaults
}

function main {
    # set -euo pipefail
    __set_variables

    for var in "$@"; do
        case "$var" in
            "-h" | "help")
                builder_help
                exit 0
                ;;
        esac
    done

    builder_info

    if [[ "${DEBUG}" == "true" ]]; then
        set -x
        REDIR="/dev/stderr"
    else
        unset DEBUG
        REDIR="/dev/null"
    fi

    build_images
}

[[ "$0" == "$BASH_SOURCE" ]] && main "$@"
