#!/bin/bash
hostname=$(hostname)
KUBECONFIG=/etc/kubernetes/admin.conf
IPS_INUSE=$(\
    KUBECONFIG=${KUBECONFIG} \
    kubectl get pods \
        --all-namespaces \
        -o=jsonpath="{range .items[?(@.spec.nodeName==\"${hostname}\")]}{\" \"}{.status.podIP}{\" \"}{end}" \
    )
echo "Pod IPs on this node: ${IPS_INUSE}"

CNI_NETWORKS="/var/lib/cni/networks/default-cni-network"
for ip in $( ls ${CNI_NETWORKS} | egrep "^[0-9]" ); do
    echo "checking ${ip}"
    if [[ "${IPS_INUSE}" =~ " ${ip} " ]]; then
        echo "${ip} is currently used"
    else
        echo "Freeing ${ip}."
        rm ${CNI_NETWORKS}/${ip}
    fi
done
