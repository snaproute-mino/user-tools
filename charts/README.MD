# cnnos-fluentd-collector federation example

## set k8s context variable for your host cluster
```

K8S_CONTEXT=admin@demo-ubuntu-vm

```


## update kubeconfig contexts for each device
```

update-kubeconfig leaf1 192.168.105.118

update-kubeconfig leaf2 192.168.105.119

update-kubeconfig leaf3 192.168.105.120

update-kubeconfig leaf4 192.168.105.100

update-kubeconfig spine1 192.168.105.116

update-kubeconfig spine2 192.168.105.117

update-kubeconfig spine3 192.168.105.103

```


## Join some nodes for federation
```

kubectl --context ${K8S_CONTEXT} -n kube-federation-system get kubefedcluster


K8S_CONTEXT=admin@demo-ubuntu-vm
ACTION=join

kubefedctl ${ACTION} --host-cluster-context ${K8S_CONTEXT} --host-cluster-name demo --cluster-context admin@leaf1 leaf1

kubefedctl ${ACTION} --host-cluster-context ${K8S_CONTEXT} --host-cluster-name demo --cluster-context admin@leaf2 leaf2

kubefedctl ${ACTION} --host-cluster-context ${K8S_CONTEXT} --host-cluster-name demo --cluster-context admin@leaf3 leaf3

kubefedctl ${ACTION} --host-cluster-context ${K8S_CONTEXT} --host-cluster-name demo --cluster-context admin@leaf4 leaf4


kubefedctl ${ACTION} --host-cluster-context ${K8S_CONTEXT} --host-cluster-name demo --cluster-context admin@spine1 spine1

kubefedctl ${ACTION} --host-cluster-context ${K8S_CONTEXT} --host-cluster-name demo --cluster-context admin@spine2 spine2

kubefedctl ${ACTION} --host-cluster-context ${K8S_CONTEXT} --host-cluster-name demo --cluster-context admin@spine3 spine3


kubectl --context ${K8S_CONTEXT} -n kube-federation-system get kubefedcluster

```

# Federate the "default" namespace
```

K8S_CONTEXT=admin@demo-ubuntu-vm
CLUSTER_LABEL='snaproute.com/cnf-namespace-default="true"'
SELECTOR_LABEL='snaproute.com/cnf-namespace-default: "true"'
FEDERATED_NAMESPACE="default"

cat <<EOL | kubectl --context ${K8S_CONTEXT} -n ${FEDERATED_NAMESPACE} apply -f -
apiVersion: types.kubefed.io/v1beta1
kind: FederatedNamespace
metadata:
  name: ${FEDERATED_NAMESPACE}
spec:
  placement:
    clusterSelector:
      matchLabels:
        ${SELECTOR_LABEL:-}
EOL

```

## Label the target nodes
```

kubectl \
    --context ${K8S_CONTEXT} \
    --namespace kube-federation-system \
    label kubefedcluster --all snaproute.com/cnf-namespace-default=true

```


## pre-deployment validation

### check each switch to see if logging resources exist
```

kubectl --context admin@leaf1 get fluentdcollector

kubectl --context admin@leaf2 get fluentdcollector

kubectl --context admin@leaf3 get fluentdcollector

kubectl --context admin@leaf4 get fluentdcollector

kubectl --context admin@spine1 get fluentdcollector

kubectl --context admin@spine2 get fluentdcollector

kubectl --context admin@spine3 get fluentdcollector

```

### verify elasticsearch indexes don't exist
```

xdg-open https://10.48.0.36:5601/login?next=%2F

```



## deploy logging

### Register CRD and enable federation
```

helm repo update
helm fetch virtualization/cnnos-fluentd-collector --version v1.0.0
helm template --name log-crd \
    cnnos-fluentd-collector-v1.0.0.tgz \
    --set create.fluentdCollector=false \
    --set create.crd=true \
    | \
    kubectl --context ${K8S_CONTEXT} create -f -

kubefedctl --host-cluster-context ${K8S_CONTEXT} \
    enable fluentdcollectors.config.snaproute.com

```


### Deploy CN-NOS fluentd collector config
```

helm template \
    cnnos-fluentd-collector-v1.0.0.tgz \
    --name cnf-log \
    --namespace default \
    --set outputType=forward \
    --set host=10.48.0.37 \
    --set port=24224 \
    --set username=cnnos \
    --set password=logging \
    --set federation.enabled=true \
    --set federation.createNamespace=true \
    | \
    kubectl --context ${K8S_CONTEXT} create -f -

```

### Label the target nodes
```

kubectl \
    --context ${K8S_CONTEXT} \
    --namespace kube-federation-system \
    label kubefedcluster --all snaproute.com/cnf-logging=true

```

## verification

### elasticsearch / kibana
```

xdg-open https://10.48.0.36:5601/login?next=%2F

```

### check federated object 
```

kubectl \
    --context ${K8S_CONTEXT} \
    get federatedfluentdcollector \
    -o yaml \
    | \
    egrep -A 8 "^  (metadata:|status:)"

```

### check each switch to has the synced logging resources
```

kubectl --context admin@leaf1 get fluentdcollector

kubectl --context admin@leaf2 get fluentdcollector

kubectl --context admin@leaf3 get fluentdcollector

kubectl --context admin@leaf4 get fluentdcollector

kubectl --context admin@spine1 get fluentdcollector

kubectl --context admin@spine2 get fluentdcollector

kubectl --context admin@spine3 get fluentdcollector

```


# cnnos-metrics-federation

## set k8s context variable for your host cluster
```

K8S_CONTEXT=admin@demo-ubuntu-vm

```

## install prometheus-operator in host cluster

```

chart="stable/prometheus-operator"
chart_version=$(helm search ${chart} | egrep -v "CHART" | awk '{ print $2 }')

namespace="monitoring"
prom_operate="cnf-metrics"

helm fetch ${chart} --version ${chart_version}

helm upgrade \
    --kube-context=${K8S_CONTEXT} \
    --install cnf-metrics \
    ${chart}-${chart_version}.tar.gz \
    --namespace ${namespace} \
    --set "prometheus.server.terminationGracePeriodSeconds=30"

```

## enable federation of additional core resources
```

kubefedctl --host-cluster-context ${K8S_CONTEXT} enable clusterrole
kubefedctl --host-cluster-context ${K8S_CONTEXT} enable clusterrolebinding
kubefedctl --host-cluster-context ${K8S_CONTEXT} enable daemonsets.apps
kubefedctl --host-cluster-context ${K8S_CONTEXT} enable podsecuritypolicies.extensions

```

## deploy a prometheus instance for scraping each switch
```
namespace=default

helm fetch virtualization/cnnos-metrics-federation --version v1.0.0

helm template \
    cnnos-metrics-federation-v1.0.0.tgz \
    --name cnnos-metrics \
    --namespace ${namespace} \
    --set prometheusRelease=${prom_operate} \
    --set fabricName=cnf1 \
    --set nodes.leaf1=192.168.105.118 \
    --set nodes.leaf2=192.168.105.119 \
    --set nodes.leaf3=192.168.105.120 \
    | \
    kubectl --context ${K8S_CONTEXT} create -f -

```

## Label the target nodes
```

kubectl \
    --context ${K8S_CONTEXT} \
    --namespace kube-federation-system \
    label kubefedcluster --all snaproute.com/cnf-metrics=true

```

## connect to prometheus instance and verify the targets / service discovery
```

kubectl --context admin@demo-ubuntu-vm port-forward svc/cnf1-leaf1-prometheus 9090

```

## connect to graphana for visualization of the metrics

```
kubectl --context admin@demo-ubuntu-vm --namespace monitoring port-forward svc/cnf-metrics-grafana 8080:80

```


# cnnos-audit-collector federation example

## set k8s context variable for your host cluster
```

K8S_CONTEXT=admin@demo-ubuntu-vm

```

## enable federation of additional core resources
```

kubefedctl --host-cluster-context ${K8S_CONTEXT} enable clusterrolebinding
kubefedctl --host-cluster-context ${K8S_CONTEXT} enable crd

```

## deploy audit crd and enable federation of audithooks
```

helm repo add virtualization https://repo.snaproute.com/chartrepo/virtualization
helm repo update

helm fetch virtualization/audit-crd --version v1.0.3
helm fetch virtualization/audit-collector --version v1.0.3

helm template \
    audit-crd-v1.0.3.tgz \
    --name audit-crd \
    --namespace default \
    --set audit.federation.enabled=true \
    | \
    kubectl --context ${K8S_CONTEXT} create -f -

kubefedctl --host-cluster-context ${K8S_CONTEXT} enable audithooks

```

## start audit-aggregator
```

USERS_AUDITHOOK_URL=http://192.168.101.45:7443

docker run --rm -it -p 7443:7443 repo.snaproute.com/virtualization/audit:v1.0.3

```

## deploy audit collector and filter configuration
```

helm template \
    audit-collector-v1.0.3.tgz \
    --name audit-demo \
    --namespace default \
    --set audit.federation.enabled=true \
    --set audit.usersAuditHookURL=${USERS_AUDITHOOK_URL} \
    | \
    kubectl --context ${K8S_CONTEXT} create -f -

```

## Label the target nodes
```

kubectl \
    --context ${K8S_CONTEXT} \
    --namespace kube-federation-system \
    label kubefedcluster --all snaproute.com/cnf-audit=true

```


# evpn federation

## set a few variable for reuse
```

K8S_CONTEXT=admin@demo-ubuntu-vm
CLUSTER_LABEL="snaproute.com/cnnos-cluster=evpn-cluster"
SELECTOR_LABEL="snaproute.com/cnnos-cluster: evpn-cluster"
FEDERATED_NAMESPACE="default"

```

# Retrieve CRD definitions from a switch
```

mkdir -p crds

kubectl --context admin@leaf1 get crd vlans.config.snaproute.com -o yaml > crds/vlans.config.snaproute.com.yaml

kubectl --context admin@leaf1 get crd l2evpninstances.config.snaproute.com -o yaml > crds/l2evpninstances.config.snaproute.com.yaml

kubectl --context admin@leaf1 get crd l2evpnethernetsegments.config.snaproute.com -o yaml > crds/l2evpnethernetsegments.config.snaproute.com.yaml

```

# Create CRDs in the host-cluster
```

kubectl --context ${K8S_CONTEXT} create -f crds/

```

# Enable federation of the CRDs in host-cluster
```

kubefedctl enable --host-cluster-context ${K8S_CONTEXT} -f crds/vlans.config.snaproute.com.yaml

kubefedctl enable --host-cluster-context ${K8S_CONTEXT} -f crds/l2evpninstances.config.snaproute.com.yaml

kubefedctl enable --host-cluster-context ${K8S_CONTEXT} -f crds/l2evpnethernetsegments.config.snaproute.com.yaml

```

# Federate the "default" namespace
```

cat <<EOL | kubectl --context ${K8S_CONTEXT} -n ${FEDERATED_NAMESPACE} apply -f -
apiVersion: types.kubefed.io/v1beta1
kind: FederatedNamespace
metadata:
  name: ${FEDERATED_NAMESPACE}
spec:
  placement:
    clusterSelector:
      matchLabels:
        ${SELECTOR_LABEL:-}
EOL

```

# Federate some vlans
```

# indentation is import here since we're working with yaml
IFS='' read -r -d '`' CLUSTER_OVERRIDES <<"EOL"
    - clusterName: leaf1
      clusterOverrides:
      - path: /spec/taggedInterfaces
        value:
          lags: ["po1"]
    - clusterName: leaf2
      clusterOverrides:
      - path: /spec/taggedInterfaces/lags
        value: 
        - "po1"
    - clusterName: leaf3
      clusterOverrides:
      - path: /spec/taggedInterfaces
        value: 
          ports: ["fpPort22"]
EOL

vlans="600 601 602"
for vlan in ${vlans}; do
  object_name=${vlan}
  vlan_id=${vlan}
  
  cat <<EOL | kubectl --context ${K8S_CONTEXT} -n ${FEDERATED_NAMESPACE} apply -f -
apiVersion: types.kubefed.io/v1beta1
kind: FederatedVlan
metadata:
  name: "${object_name}"
spec:
  template:
    metadata:
      labels:
        vlanId: "${vlan_id}"
    spec:
      vlanId: ${vlan_id}
      taggedInterfaces:
        ports: []
        lags: []
      untaggedInterfaces:
        ports: []
        lags: []
  placement:
    clusterSelector:
      matchLabels:
        ${SELECTOR_LABEL:-}
  overrides:
${CLUSTER_OVERRIDES:-    []}
EOL
done

```



# Federate VNIs for each vlan
```

vlans="600 601 602"
for vlan in ${vlans}; do
  object_name=${vlan}
  vlan_name=${vlan}
  vni=${vlan}

  cat <<EOL | kubectl --context ${K8S_CONTEXT} -n ${FEDERATED_NAMESPACE} apply -f -
apiVersion: types.kubefed.io/v1beta1
kind: FederatedL2EvpnInstance
metadata:
  name: "${object_name}"
  namespace: ${FEDERATED_NAMESPACE}
  annotations:
    kubefed.io/orphan: "true"
spec:
  template:
    metadata:
      name: "${object_name}"
      namespace: ${FEDERATED_NAMESPACE}
    spec:
      encapsulation: vxlan
      rd: auto
      rt:
      - routeTarget: auto
        routeTargetType: both
      staticType2Routes: {}
      vlanService:
        vlan: "${vlan_name}"
      vni: ${vni}
  placement:
    clusterSelector:
      matchLabels:
        ${SELECTOR_LABEL:-}
EOL
done

```



# Federate EVPN Ethernet Segment on a couple nodes
```

# indentation is import here since we're working with yaml
IFS='' read -r -d '`' CLUSTER_OVERRIDES <<"EOL"
    - clusterName: leaf1
      clusterOverrides:
      - path: /spec/bgp/rd
        value: 2.2.2.2:3
      - path: /spec/bgp/rt
        value: 11:22:33:44:55:66
      - path: /spec/ifName
        value: po1
    - clusterName: leaf2
      clusterOverrides:
      - path: /spec/bgp/rd
        value: 3.3.3.3:3
      - path: /spec/bgp/rt
        value: 11:22:33:44:55:66
      - path: /spec/ifName
        value: po1
EOL

object_name="es1"

cat <<EOL | kubectl --context ${K8S_CONTEXT} -n ${FEDERATED_NAMESPACE} apply -f -
apiVersion: types.kubefed.io/v1beta1
kind: FederatedL2EvpnEthernetSegment
metadata:
  name: ${object_name}
  annotations:
    kubefed.io/orphan: "true"
spec:
  template:
    metadata:
      name: ${object_name}
    spec:
      activeMode: all-active-mode
      dfElection:
        waitTime: 3
      esi: 00:11:22:33:44:55:66:77:88:99
      # these will be overridden per node, but required to pass validation
      ifName: placeholder
      bgp:
        rd: 0.0.0.0:0
        rt: 00:00:00:00:00:00
  placement:
    clusters:
    - name: leaf1
    - name: leaf2
  overrides:
${CLUSTER_OVERRIDES:-    []}
EOL

```

## Label the target nodes
```

kubectl \
    --context ${K8S_CONTEXT} \
    --namespace kube-federation-system \
    label kubefedcluster leaf1 snaproute.com/cnf-namespace-default=true

kubectl \
    --context ${K8S_CONTEXT} \
    --namespace kube-federation-system \
    label kubefedcluster leaf2 snaproute.com/cnf-namespace-default=true

kubectl \
    --context ${K8S_CONTEXT} \
    --namespace kube-federation-system \
    label kubefedcluster leaf3 snaproute.com/cnf-namespace-default=true


kubectl \
    --context ${K8S_CONTEXT} \
    --namespace kube-federation-system \
    label kubefedcluster leaf1 snaproute.com/cnnos-cluster=evpn-cluster

kubectl \
    --context ${K8S_CONTEXT} \
    --namespace kube-federation-system \
    label kubefedcluster leaf2 snaproute.com/cnnos-cluster=evpn-cluster

kubectl \
    --context ${K8S_CONTEXT} \
    --namespace kube-federation-system \
    label kubefedcluster leaf3 snaproute.com/cnnos-cluster=evpn-cluster


```