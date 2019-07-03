# SnapRoute CN-NOS Virtualization

## Provisioning a single node Kubernetes cluster with virtualization dependencies (on an Ubuntu 18.04 system)

1) Download the provisioning script

    curl -Lo provision-vm-cluster.sh https://raw.githubusercontent.com/snaproute-mino/user-tools/v1.0.0/virtualization/provision-vm-cluster.sh

```
server41@server41:~$ curl -Lo provision-vm-cluster.sh https://github.com/snaproute-mino/user-tools/blob/v1.0.0/virtualization/provision-vm-cluster.sh
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 82963  100 82963    0     0   275k      0 --:--:-- --:--:-- --:--:--  275k
server41@server41:~$ 
```

2) Make the script executable
    chmod +x provision-vm-cluster.sh

```
server41@server41:~$ chmod +x provision-vm-cluster.sh 
server41@server41:~$ 
```

3) Run the provisioning script
    BOOTSTRAPPER=kubeadm ./provision-vm-cluster.sh

```
server41@server41:~$ DEBUG=true BOOTSTRAPPER=kubeadm ./provision-vm-cluster.sh 
host info:
    OS: linux
    OS_DISTRIBUTOR: Ubuntu
    HOSTNAME: server41
    DEFAULT_INTERFACE: bond0
    DEFAULT_INTERFACE_IP: 192.168.100.41


# PROVISIONING CONFIGURATION

bootstrapper:
    DEBUG: false
    BOOTSTRAPPER: kubeadm
    BOOTSTRAPPER_DOCKER_REGISTRY: repo.snaproute.com
    DEPENDENCIES_ONLY: false

cluster:
    CLUSTER_CONTROLPLANE_ENDPOINT: 192.168.100.41:6443
    CLUSTER_ID: 41
    CLUSTER_LB_VM_CIDR: 10.41.0.0/18
    CLUSTER_LB_DEFAULT_CIDR: 10.41.64.0/18
    CLUSTER_POD_CIDR: 10.41.128.0/18
    CLUSTER_SERVICE_CIDR: 10.41.192.0/18

ha (heartbeat / haproxy):
    HA_CONTROLPLANE_NODES: 
    HA_HEARTBEAT_AUTH_MD5SUM: 853ae90f0351324bd73ea615e6487517
    HA_HEARTBEAT_MCAST_GROUP: 225.0.0.1
    HA_HEARTBEAT_UDP_PORT: 694

kubernetes:
    KUBERNETES_VERSION: v1.14.1
    KUBERNETES_IMAGE_REPOSITORY: k8s.gcr.io
    KUBERNETES_CONTROLPLANE_ENDPOINT: 192.168.100.41:6443
    KUBERNETES_APISERVER_LOCAL_BIND_PORT: 6443
    KUBERNETES_POD_CIDR: 10.41.128.0/18
    KUBERNETES_SERVICE_CIDR: 10.41.192.0/18
    KUBERNETES_OIDC_ISSUER_URL: https://accounts.google.com
    KUBERNETES_OIDC_CLIENT_ID: 

minikube (only applicable if bootstrapper is minikube):
    MINIKUBE_CPUS: 4
    MINIKUBE_MEMORY: 8192
    MINIKUBE_DISK_SIZE: 20g
    MINIKUBE_VM_DRIVER: kvm2
    MINIKUBE_REGISTRY_NODEPORT: 

cni (container networking):
    CNI_PLUGINS_VERSION: v0.4
    CNI_PLUGINS_IMAGE_REPOSITORY: repo.snaproute.com/vm-infra/cni
    CNI_MULTUS_VERSION: latest
    CNI_MULTUS_IMAGE_REPOSITORY: repo.snaproute.com/vm-infra/cni
    CNI_FLANNEL_VERSION: v0.11.0
    CNI_FLANNEL_IMAGE_REPOSITORY: repo.snaproute.com/vm-infra/quay.io/coreos

helm:
    HELM_VERSION: v2.11.0

kubevirt:
    KUBEVIRT_VERSION: v0.16.0-snaproute
    KUBEVIRT_VIRTCTL_VERSION: v0.16.0
    KUBEVIRT_IMAGE_REPOSITORY: repo.snaproute.com/vm-infra/kubevirt
    KUBEVIRT_SOFTWARE_EMULATION: false

metallb (load-balancer for kubernetes services, only applicable if METALLB_PEER_ADDRESS is set):
    METALLB_VERSION: v0.9.4
    METALLB_PEER_ADDRESS: 
    METALLB_PEER_ASN: 65500
    METALLB_LOCAL_ASN: 65501
    METALLB_POOL_DEFAULT_CIDR: 10.41.64.0/18
    METALLB_POOL_VM_CIDR: 10.41.0.0/18
    METALLB_COMMUNITY_NOADVERTISE: 65535:65282

bootstrapping with kubeadm on linux with OIDC disabled
Proceed with installation/provisioning? [yes or no]: yes
installing/downloading kubeadm dependencies
Installing kvm2
Synchronizing state of libvirtd.service with SysV service script with /lib/systemd/systemd-sysv-install.
Executing: /lib/systemd/systemd-sysv-install enable libvirtd
Enabling nested virtualization in kvm2
Installing docker
Installing kubeadm
Installing kubectl
Populating additional files
Running kubeadm initialization
Installing flannel networking
Installing cni-plugins / multus networking
Installing helm
Deploying helm
Installing virtctl
Deploying kubevirt
bootstrapping complete
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of the control-plane node running the following command on each as root:

  kubeadm join 192.168.100.41:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:f3da5a71974d95aca58e9e4d7e7b737da88ce711b6f7608008e3210b77e9e2bd \
    --experimental-control-plane --certificate-key b8f812b213f3f580fee8984bcc7b57d1def9a3b021ac7a3dbac628f88e8e7dd6

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use 
"kubeadm init phase upload-certs --experimental-upload-certs" to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.100.41:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:f3da5a71974d95aca58e9e4d7e7b737da88ce711b6f7608008e3210b77e9e2bd 
```

4) Verify all pods are running
    kubectl get pod --all-namespaces

```
server41@server41:~$ kubectl get pod --all-namespaces
NAMESPACE     NAME                               READY   STATUS    RESTARTS   AGE
kube-system   coredns-fb8b8dccf-ghb9t            1/1     Running   0          3m33s
kube-system   coredns-fb8b8dccf-xrf8l            1/1     Running   0          3m33s
kube-system   etcd-server41                      1/1     Running   0          2m44s
kube-system   kube-apiserver-server41            1/1     Running   0          2m46s
kube-system   kube-controller-manager-server41   1/1     Running   0          2m29s
kube-system   kube-flannel-ds-amd64-76chf        1/1     Running   0          3m33s
kube-system   kube-multus-ds-amd64-xrfnk         1/1     Running   0          3m33s
kube-system   kube-proxy-bbmk8                   1/1     Running   0          3m33s
kube-system   kube-scheduler-server41            1/1     Running   0          2m35s
kube-system   tiller-deploy-59b99695d8-r7zgl     1/1     Running   0          3m33s
kubevirt      virt-api-556bcfff8-7rllh           1/1     Running   0          3m5s
kubevirt      virt-api-556bcfff8-glmdz           1/1     Running   0          3m5s
kubevirt      virt-controller-7dc5f5b56d-d4fdx   1/1     Running   0          3m5s
kubevirt      virt-controller-7dc5f5b56d-xrhhx   1/1     Running   0          3m5s
kubevirt      virt-handler-t2h5x                 1/1     Running   0          3m5s
```

## Kubernetes cluster access

Kubernetes provides a number of options for authenticating users.  This document will provide a simple example of creating serviceaccounts for users.

Generally, it is recommended to deploy an OIDC provider (like coreos/dex) to integrate with your existing authentication infrastructure (such as LDAP).  This is outside the scope of this document.  Additional info can be found at [[https://kubernetes.io/docs/reference/access-authn-authz/authentication/#users-in-kubernetes]]

1) Create a namespace / service account / rbac role / rbac rolebinding for a new user (run this on the server you provisioned)

```
USER_EMAIL=john.doe@test
NAME=${USER_EMAIL//@*/}
DOMAIN=${USER_EMAIL//*@/}
cat <<EOL | kubectl apply -f -
kind: Namespace
apiVersion: v1
metadata:
  name: ${NAME//.}
---
kind: ServiceAccount
apiVersion: v1
metadata:
  namespace: ${NAME//.}
  name: ${NAME}.${DOMAIN}
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: ${NAME//.}
  name: ${NAME}.${DOMAIN}
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: ${NAME//.}
  name: ${NAME}.${DOMAIN}
subjects:
- kind: ServiceAccount
  name: ${NAME}.${DOMAIN}
roleRef:
  kind: Role
  name: ${NAME}.${DOMAIN}
  apiGroup: rbac.authorization.k8s.io
EOL
```

2) Generate a kubeconfig file for the user

```
USER_EMAIL=john.doe@test
NAME=${USER_EMAIL//@*/}
NAMESPACE=${NAME//.}
DOMAIN=${USER_EMAIL//*@/}

SECRET_NAME=$(kubectl -n ${NAMESPACE} get sa ${NAME}.${DOMAIN} -o jsonpath='{.secrets[0].name}')
CA_CERT=$( kubectl -n ${NAMESPACE} get secret ${SECRET_NAME} -o jsonpath='{.data.ca\.crt}' )
SA_TOKEN=$( kubectl -n ${NAMESPACE} get secret ${SECRET_NAME} -o jsonpath='{.data.token}' | base64 -d )

DEFAULT_INTERFACE="$(awk '$2 == 00000000 { print $1 }' /proc/net/route)"
DEFAULT_INTERFACE_IP=`ip addr show dev "${DEFAULT_INTERFACE}" | awk '$1 == "inet" && $3 == "brd" { sub("/.*", "", $2); print $2 }'`
DEFAULT_SERVER_PORT=6443

CLUSTER_NAME="cnnos-cluster"
CLUSTER_SERVER=https://${DEFAULT_INTERFACE_IP}:${DEFAULT_SERVER_PORT}
CREDENTIALS_NAME=${NAME}.${CLUSTER_NAME}
CONTEXT_NAME=${CREDENTIALS_NAME}


DEFAULT_KUBECONFIG=$(pwd)/kubeconfig
KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config set-cluster ${CLUSTER_NAME} --server=${CLUSTER_SERVER} --insecure-skip-tls-verify=true

KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config set-credentials ${CREDENTIALS_NAME}

KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config set users."${CREDENTIALS_NAME}".token "${SA_TOKEN}"

KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config set-context ${CONTEXT_NAME} \
        --cluster ${CLUSTER_NAME} \
        --user ${CREDENTIALS_NAME} \
        --namespace ${NAMESPACE}

KUBECONFIG=${DEFAULT_KUBECONFIG} kubectl config use-context ${CONTEXT_NAME}
```

3) Copy the generated kubeconfig file to the machine / user home directory that you'd like to use when remotely accessing the cluster

```
USERNAME=jdoe
USER_IP=192.168.0.10
KUBE_DIR=/home/${USERNAME}/.kube/
ssh ${USERNAME}@${USER_IP} mkdir -p ${KUBE_DIR}
scp ./kubeconfig ${USERNAME}@${USER_IP}:${KUBE_DIR}/config
```

## Installing user tools to local laptop / server

1) Download the user tools installation script

```
curl -Lo user-tools-install.sh https://raw.githubusercontent.com/snaproute-mino/user-tools/master/user-tools-install.sh
```

2) Make the script executable

```
chmod +x user-tools-install.sh
```

3) Run the user tools installation

```
./user-tools-install.sh
```

4) Verify you can access the cluster using kubectl and the kubeconfig you generated

```
kubectl get sa
```

## Request an account for access to CN-NOS release images

1) Contact your sales representation or email info@snaproute.com to request an account

2) Create an image pull secret for the account provided in step 1 (this should be created in the namespace that you'll be deploying cnnos-topologies)

```
kubectl create secret docker-registry snaproute-pull-secret \
--docker-server=repo.snaproute.com \
--docker-username=john.doe@customer.local \
--docker-email=john.doe@customer.local \
--docker-password=PasswordProvided
```

## Deploying an onie-http server for hosting cn-nos monolithic image to ONIE VMs

1) Add the cn-nos release repo

```
helm repo add cnnos-release --username="john.doe@customer.local" --password="PasswordProvided" https://repo.snaproute.com/chartrepo/release
```

2) Perform a repo update to ensure you have access to the latest charts

```
helm repo update
```

3) List the available monolithic releases

```
helm search cnnos-release/cnnos-monolithic --versions
```

4) Download the desired version chart

```
VERSION=v1.1.0-R15
helm fetch cnnos-release/cnnos-monolithic --version ${VERSION}
```

5) Deploy an onie-http server instance to host the desired CN-NOS monolithic image (referencing the imagePullSecret created earlier)

```
PULL_SECRET=snaproute-pull-secret
VERSION=v1.1.0-R15
helm template --name onie-http-server --set imagePullSecret=${PULL_SECRET} cnnos-monolithic-${VERSION}.tgz | kubectl create -f -
```

6) Verify the server is running (this may take some time in ContainerCreating as the monolithic image is downloaded)

```
pferrell@pferrell-lnx:~$ kubectl get pod
NAME                                                 READY   STATUS    RESTARTS   AGE
onie-http-server-cnnos-monolithic-75b986b495-zb9hj   1/1     Running   0          10m

pferrell@pferrell-lnx:~$ kubectl get service -o wide
NAME                                TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE   SELECTOR
onie-http-server-cnnos-monolithic   ClusterIP   10.41.225.99   <none>        80/TCP    10m   app.kubernetes.io/instance=onie-http-server,app.kubernetes.io/name=cnnos-monolithic

```

## Deploy a VM topology referencing the onie-http server / image you deployed

1) Add the cnnos-virtualization repo

```
helm repo add cnnos-virtualization https://repo.snaproute.com/chartrepo/virtualization
```

2) Perform a repo update to ensure you have access to the latest charts

```
helm repo update
```

3) List the available monolithic releases

```
helm search cnnos-virtualization
```

4) Download the desired version chart

```
TOPOLOGY=node2node
VERSION=v1.0.0
helm fetch cnnos-virtualization/${TOPOLOGY} --version ${VERSION}
```

5) Deploy the chart referencing the service IP of the onie-http-server you deployed (CHART_FILE should reference the location where you fetched it in previous step)

```
TOPOLOGY=node2node
VERSION=v1.0.0
CHART_FILE=${TOPOLOGY}-${VERSION}.tgz
TOPOLOGY_NAME=my-topology
CLUSTER_IP=$(kubectl get service onie-http-server-cnnos-monolithic -o jsonpath="{.spec.clusterIP}")

helm template --name ${TOPOLOGY_NAME} ${CHART_FILE} --set "topology-builder.dhcpOptions.privateOptions[0].value=http://${CLUSTER_IP}/monolithic/onie-installer_x86-64" --set "topology-builder.dhcpOptions.privateOptions[0].option=114" | kubectl create -f -
```

```
pferrell@pferrell-lnx:~$ TOPOLOGY=node2node
pferrell@pferrell-lnx:~$ VERSION=v1.0.0
pferrell@pferrell-lnx:~$ helm fetch cnnos-virtualization/${TOPOLOGY} --version ${VERSION}
pferrell@pferrell-lnx:~$ TOPOLOGY=node2node
pferrell@pferrell-lnx:~$ VERSION=v1.0.0
pferrell@pferrell-lnx:~$ CHART_FILE=${TOPOLOGY}-${VERSION}.tgz
pferrell@pferrell-lnx:~$ TOPOLOGY_NAME=my-topology
pferrell@pferrell-lnx:~$ CLUSTER_IP=$(kubectl get service onie-http-server-cnnos-monolithic -o jsonpath="{.spec.clusterIP}")
pferrell@pferrell-lnx:~$ 
pferrell@pferrell-lnx:~$ helm template --name ${TOPOLOGY_NAME} ${CHART_FILE} --set "topology-builder.dhcpOptions.privateOptions[0].value=http://${CLUSTER_IP}/monolithic/onie-installer-x86_64" --set "topology-builder.dhcpOptions.privateOptions[0].option=114" | kubectl create -f -
configmap/my-topology-topology created
deployment.extensions/my-topology.topology created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch1-p2-switch2-p2-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch1-p3-switch2-p3-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch1-p1-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch1-p4-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch1-p5-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch1-p6-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch1-p7-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch1-p8-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch2-p1-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch2-p4-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch2-p5-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch2-p6-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch2-p7-conf created
networkattachmentdefinition.k8s.cni.cncf.io/my-topology-switch2-p8-conf created
virtualmachine.kubevirt.io/my-topology-switch1 created
service/my-topology-switch1 created
virtualmachine.kubevirt.io/my-topology-switch2 created
service/my-topology-switch2 created
virtualmachineinstancepreset.kubevirt.io/my-topology-onie-2core-2g created
virtualmachineinstancepreset.kubevirt.io/my-topology-onie-2core-4g created
virtualmachineinstancepreset.kubevirt.io/my-topology-onie-2core-8g created
virtualmachineinstancepreset.kubevirt.io/my-topology-onie-4core-16g created
virtualmachineinstancepreset.kubevirt.io/my-topology-onie-4core-8g created
virtualmachineinstancepreset.kubevirt.io/my-topology-onie-8core-16g created
virtualmachineinstancepreset.kubevirt.io/my-topology-onie-8core-32g created
virtualmachineinstancepreset.kubevirt.io/my-topology-default created
```

6) Verify the VMs are deployed and running

```
kubectl get vm

kubectl get vmi

kubectl get pod

pferrell@pferrell-lnx:~$ kubectl get vm
NAME                  AGE   RUNNING   VOLUME
my-topology-switch1   52s   true      
my-topology-switch2   52s   true      


pferrell@pferrell-lnx:~$ kubectl get vmi
NAME                  AGE   PHASE        IP    NODENAME
my-topology-switch1   19s   Scheduling         
my-topology-switch2   19s   Scheduling  

pferrell@pferrell-lnx:~$ kubectl get vmi
NAME                  AGE   PHASE     IP              NODENAME
my-topology-switch1   54s   Running   10.41.128.236   server41
my-topology-switch2   54s   Running   10.41.128.237   server41

pferrell@pferrell-lnx:~$ kubectl get pod
NAME                                                 READY   STATUS    RESTARTS   AGE
my-topology.topology-87c555694-9hjrk                 1/1     Running   0          47s
onie-http-server-cnnos-monolithic-75b986b495-zb9hj   1/1     Running   0          2m40s
virt-launcher-my-topology-switch1-zp7tx              2/2     Running   0          47s
virt-launcher-my-topology-switch2-2cczj              2/2     Running   0          46s
```

7) Console to a switch and onie installation can be observed (console command will wait until VMI is running)

```
pferrell@pferrell-lnx:~$ virtctl console my-topology-switch1
Successfully connected to my-topology-switch1 console. The escape sequence is ^]

ONIE: OS Install Mode ...
Platform  : x86_64-kvm_x86_64-r0
Version   : master-201903271045-dirty
Build Date: 2019-03-27T10:45+00:00
Info: Mounting kernel filesystems... done.
Info: Mounting ONIE-BOOT on /mnt/onie-boot ...
Info: BIOS mode: legacy
Running demonstration platform init pre_arch routines...
Running demonstration platform init post_arch routines...
Info: Making NOS install boot mode persistent.
Installing for i386-pc platform.
Installation finished. No error reported.
network_driver: Running demonstration pre_init routines...
network_driver: Running ASIC/SDK init routines...
network_driver: Running demonstration post_init routines...
Info: Using eth0 MAC address: 02:bb:26:87:c4:05
Info: Using eth1 MAC address: 7a:2f:28:f3:cd:24
Info: eth0:  Checking link... up.
Info: Trying DHCPv4 on interface: eth0
ONIE: Using DHCPv4 addr: eth0: 10.41.128.246 / 255.255.255.0
Info: eth1:  Checking link... up.
Info: Trying DHCPv4 on interface: eth1
Warning: Unable to configure interface using DHCPv4: eth1
ONIE: Using link-local IPv4 addr: eth1: 169.254.42.218/16
Starting: klogd... done.
Starting: dropbear ssh daemon... done.
Starting: telnetd... done.
discover: installer mode detected.  Running installer.
Starting: discover... done.

Please press Enter to activate this console. Info: eth0:  Checking link... up.
Info: Trying DHCPv4 on interface: eth0
ONIE: Using DHCPv4 addr: eth0: 10.41.128.246 / 255.255.255.0
Info: eth1:  Checking link... up.
Info: Trying DHCPv4 on interface: eth1
Warning: Unable to configure interface using DHCPv4: eth1
ONIE: Using link-local IPv4 addr: eth1: 169.254.165.95/16
ONIE: Starting ONIE Service Discovery
Info: Attempting http://10.41.225.99/monolithic/onie-installer-x86_64 ...
ONIE: Executing installer: http://10.41.225.99/monolithic/onie-installer-x86_64

#### Snaproute CN-NOS installer ####
Install mode [ ? ]. Progress: 22% 
  Booting `SnapL Image (20190515231420)'

Loading SNAPL ...
starting version 234

CN_NOS CN-NOS-1.0.0 CN-NOS-unknown ttyS0

CN-NOS-unknown login: root
Welcome to CN-NOS
root@CN-NOS-unknown:~# 
```
