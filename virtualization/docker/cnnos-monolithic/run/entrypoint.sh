#!/bin/bash

set -euxo pipefail

function __set_variables {
    HOSTNAME=`hostname`
    DEFAULT_INTERFACE="$(awk '$2 == 00000000 { print $1 }' /proc/net/route)"
    DEFAULT_INTERFACE_IP=`ip addr show dev "${DEFAULT_INTERFACE}" | awk '$1 == "inet" && $3 == "brd" { sub("/.*", "", $2); print $2 }'`
}

function __parse_arguments {
    ARG1=${1:-}
    # Single argument to command line is interface name
    if [[ "${ARG1}" != "" ]]; then
        # skip wait-for-interface behavior if found in path
        if ! which "${ARG1}" >/dev/null; then
            # loop until interface is found, or we give up
            NEXT_WAIT_TIME=1
            until [[ -e "/sys/class/net/${ARG1}" ]] || [[ $NEXT_WAIT_TIME -eq 4 ]]; do
                sleep $(( NEXT_WAIT_TIME++ ))
                echo "Waiting for interface '${ARG1}' to become available... ${NEXT_WAIT_TIME}"
            done
            if [[ -e "/sys/class/net/${ARG1}" ]]; then
                IFACE="${ARG1}"
            fi
        else
            exec "$@"
            exit $!
        fi
        if [[ "${IFACE:-}" == "" ]]; then
            echo "Interface not found."
            exit 1
        fi
    else
        IFACE=" "
    fi

    if [[ "${INTERFACES:-}" != "" ]]; then
        IFACE=${INTERFACES}
    fi

    
    if [[ "${DHCP_SUBNET:-}" == "" ]]; then
        DHCP_SUBNET=169.254.115.0
    fi
    if [[ "${DHCP_NETMASK:-}" == "" ]]; then
        DHCP_NETMASK=255.255.255.0
    fi
    if [[ "${DHCP_GATEWAY:-}" == "" ]]; then
        DHCP_GATEWAY=169.254.115.1
    fi
    if [[ "${DHCP_RANGE_START:-}" == "" ]]; then
        DHCP_RANGE_START=169.254.115.10
    fi
    if [[ "${DHCP_RANGE_END:-}" == "" ]]; then
        DHCP_RANGE_END=169.254.115.254
    fi
    if [[ "${HOST_IP:-}"  != "" ]]; then
        HTTP_SERVER_IP=${HOST_IP}
    else
        HTTP_SERVER_IP=${DEFAULT_INTERFACE_IP}
    fi
    if [[ "${HOST_HTTP_SERVER_PORT:-}" != "" ]]; then
        HTTP_SERVER_PORT=${HOST_HTTP_SERVER_PORT}
    else
        HTTP_SERVER_PORT=8888
    fi

    export DHCP_SUBNET
    export DHCP_NETMASK
    export DHCP_GATEWAY
    export DHCP_RANGE_START
    export DHCP_RANGE_END
    export HTTP_SERVER_IP
    export HTTP_SERVER_PORT
}

function dhcpd_prep {    
    export DHCPD_CONFIG_FILE=/etc/dhcp/dhcpd.conf
    /usr/local/bin/generate-dhcpd-config

    export DHCPD_LEASE_FILE=/var/lib/dhcp/dhcpd.leases
    touch ${DHCPD_LEASE_FILE}
}

function nginx_prep {
    export NGINX_CONFIG_FILE=/etc/nginx/conf.d/default.conf
    echo "daemon off;" >> /etc/nginx/nginx.conf
    /usr/local/bin/generate-nginx-config
}

_term() { 
  echo "Caught SIGTERM signal!"
  STOPPING=true
  kill -TERM "${DHCPD_PID}" 2>/dev/null
  kill -TERM "${NGINX_PID}" 2>/dev/null
}

trap _term SIGTERM

function main {
    STOPPING=false
    __set_variables
    __parse_arguments
    dhcpd_prep
    nginx_prep

    DHCRELAY="dhcrelay --no-pid 127.0.0.1 -p 77"

    DHCPD_RUN="dhcpd -4 -f -d --no-pid -cf "${DHCPD_CONFIG_FILE}" -lf "${DHCPD_LEASE_FILE}" $IFACE"
    ${DHCPD_RUN} &
    DHCPD_PID=$!

    NGINX_RUN="nginx"
    ${NGINX_RUN} &
    NGINX_PID=$!
    
    set +ex
    while [[ "${STOPPING}" == "false" ]]; do
        sleep 10
        kill -0 ${DHCPD_PID}
        RT=$?
        if [[ "${RT}" != "0" ]]; then
            echo "Restarting dhcp server"
            ${DHCPD_RUN} &
            DHCPD_PID=$!
        fi
        kill -0 ${NGINX_PID}
        RT=$?
        if [[ "${RT}" != "0" ]]; then
            echo "Restarting nginx server"
            ${NGINX_RUN} &
            NGINX_PID=$!
        fi
    done
}

[[ "$0" == "$BASH_SOURCE" ]] && main "$@"