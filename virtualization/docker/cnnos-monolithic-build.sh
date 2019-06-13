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

### MONOLITHIC CONFIGURATION

IFS='' read -r -d '' MONOLITHIC_HELP <<"EOL"
MONOLITHIC_URL
  Description: specifies the URL/path to monolithic image to embed in container
  Default: ${DEFAULT_MONOLITHIC_URL}
  Current: MONOLITHIC_URL=${MONOLITHIC_URL}

IMAGE_REPOSITORY
  Description: specifies which registry / repository to use for container images
  Default: ${DEFAULT_IMAGE_REPOSITORY}
  Current: IMAGE_REPOSITORY=${IMAGE_REPOSITORY}

IMAGE_VERSION
  Description: specifies which version tag to use for the container image
  Default: unset
  Current: IMAGE_VERSION=${IMAGE_VERSION}

DOCKER_CONTEXT
  Description: specifies which path to use for the docker context (dockerfile should reside in this directory)
  Default: ${DEFAULT_DOCKER_CONTEXT}
  Current: DOCKER_CONTEXT=${DOCKER_CONTEXT}
EOL

function __set_monolithic_defaults {
    local DEFAULT_IMAGE_REPOSITORY=repo.snaproute.com/release
    local DEFAULT_DOCKER_CONTEXT=$(pwd)/cnnos-monolithic
    if [[ -z "${IMAGE_REPOSITORY}" ]]; then
        IMAGE_REPOSITORY=${DEFAULT_IMAGE_REPOSITORY}
    fi
    if [[ -z "${DOCKER_CONTEXT}" ]]; then
        DOCKER_CONTEXT=${DEFAULT_DOCKER_CONTEXT}
    fi

    DEFAULTS_MONOLITHIC=$( eval "echo -e \"${MONOLITHIC_HELP//\"/\\\"}\"" )
}

IFS='' read -r -d '' MONOLITHIC_SKAFFOLD_TEMPLATE <<"EOL"
apiVersion: skaffold/v1beta6
kind: Config
build:
  tagPolicy:
    envTemplate:
      template: "{{ if .IMAGE_REPOSITORY }}{{ .IMAGE_REPOSITORY }}/{{ .IMAGE_NAME }}:{{ if .TAG }}{{ .TAG }}{{ else }}dev{{ end }}{{ else }}{{.DOCKER_REGISTRY}}/{{.DOCKER_REPOSITORY}}/{{ .IMAGE_NAME }}:{{ if .TAG }}{{ .TAG }}{{ else }}dev{{ end }}{{ end }}"
  artifacts:
  - image: monolithic
    context: ${DOCKER_CONTEXT}
    docker:
      dockerfile: Dockerfile
      buildArgs:
        MONOLITHIC_URL: "${MONOLITHIC_URL}"
  local:
    push: true
    useDockerCLI: true
deploy:
  helm:
    releases: []
EOL

function build_images {
    if [[ -z "${IMAGE_VERSION}" ]]; then
        echo "IMAGE_VERSION must be specified"
        VALIDATION_FAILED=true
    fi
    if [[ -z "${MONOLITHIC_URL}" ]]; then
        echo "MONOLITHIC_URL must be specified"
        VALIDATION_FAILED=true
    fi
    [[ "${VALIDATION_FAILED}" == "true" ]] && exit 1

    skaffold_install

    SKAFFOLD=$( eval "echo -e \"${MONOLITHIC_SKAFFOLD_TEMPLATE//\"/\\\"}\"" )

    export IMAGE_REPOSITORY
    export TAG=${IMAGE_VERSION}
    echo -e "${SKAFFOLD}" | cat | skaffold-${SKAFFOLD_VERSION} build -f -
}


function builder_help {
    eval "echo -e \"${BUILDER_TEMPLATE}\"" | cat
}

IFS='' read -r -d '' BUILDER_TEMPLATE <<"EOL"
# FOLLOWING ENVIRONMENT VARIABLES MODIFY INSTALLATION BEHAVIOR

### SKAFFOLD

${DEFAULTS_SKAFFOLD}


### MONOLITHIC

${DEFAULTS_MONOLITHIC}
EOL


function builder_info {
    eval "echo -e \"${MONOLITHIC_INFO}\"" | cat
}

IFS='' read -r -d '' MONOLITHIC_INFO <<"EOL"
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
    MONOLITHIC_URL: ${MONOLITHIC_URL}
    IMAGE_REPOSITORY: ${IMAGE_REPOSITORY}
    IMAGE_VERSION: ${IMAGE_VERSION}
    DOCKER_CONTEXT: ${DOCKER_CONTEXT}
EOL


function __set_variables {

    OS=`uname | tr '[:upper:]' '[:lower:]'`
    OS_DISTRIBUTOR=`lsb_release -is`
    HOSTNAME=`hostname`
    DEFAULT_INTERFACE="$(awk '$2 == 00000000 { print $1 }' /proc/net/route)"
    DEFAULT_INTERFACE_IP=`ip addr show dev "${DEFAULT_INTERFACE}" | awk '$1 == "inet" && $3 == "brd" { sub("/.*", "", $2); print $2 }'`

    __set_skaffold_defaults
    __set_monolithic_defaults
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
