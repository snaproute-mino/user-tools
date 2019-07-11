# SnapRoute CN-NOS Virtualization

## Provisioning a single node Kubernetes cluster with virtualization dependencies 

The following instructions were preformed on a bare metal Ubuntu 18.04 fresh installation.  We recommend using a bare metal installation for optimal results.

This virtual version of CN-NOS is intended for evaluation and reference only - it is not designed or supported for any production or pseudo-production workloads.

1) Download the provisioning script

```
ubuntu@server:~$ curl -Lo provision-vm-cluster.sh https://raw.githubusercontent.com/snaproute-mino/user-tools/v1.0.0/virtualization/provision-vm-cluster.sh

  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 82963  100 82963    0     0   275k      0 --:--:-- --:--:-- --:--:--  275k

```

2) Make the script executable

```
ubuntu@server:~$ chmod +x provision-vm-cluster.sh 
```

3) Run the provisioning script

```
ubuntu@server:~$ DEBUG=true BOOTSTRAPPER=kubeadm ./provision-vm-cluster.sh 
```
Note: You can remove the "DEBUG=true" output if you wish to obscure the step-by-step process that the script is taking.

After some detailed output, you will be presented with this prompt to proceed

```
Proceed with installation/provisioning? [yes or no]: yes

```

4) Verify all pods are running

```
ubuntu@server:~$ kubectl get pod --all-namespaces
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

## Kubernetes Cluster Access

Kubernetes provides a number of options for authenticating users.  

For production Kubernetes clusters, it is recommended to deploy an OIDC provider (like coreos/dex) to integrate with your existing authentication infrastructure (such as LDAP).  This is outside the scope of this document.  Additional info can be found at [[https://kubernetes.io/docs/reference/access-authn-authz/authentication/#users-in-kubernetes]]

Below we provide a simple example of creating serviceaccounts for users - which will allow for remote/local access of the Kubernetes cluster.

1) Create a namespace / service account / rbac role / rbac rolebinding for a new user (run this on the server you provisioned)

For this example, we will create a new user:

john.smith@snaproute.com

Substitute "john.smith@snaproute.com" below with the appropriate user info.

Cut and paste these lines onto the shell of the host running your Kubernetes cluster:

```
ubuntu@server:~$ 
USER_EMAIL=john.smith@snaproute.com
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
ubuntu@server:~$ 
```
You should see output similar to this after pasting in the above:

```
namespace/johnsmith created
serviceaccount/john.smith.snaproute.com created
role.rbac.authorization.k8s.io/john.smith.snaproute.com created
rolebinding.rbac.authorization.k8s.io/john.smith.snaproute.com created
```

2) Generate a kubeconfig file for the user

Substitute "john.smith@snaproute.com" below with the appropriate user info.

Cut and paste these lines onto the shell of the host running your Kubernetes cluster:

```
ubuntu@server:~$ 

USER_EMAIL=john.smith@snaproute.com
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

ubuntu@server:~$ 
```

You should see that the context has switched after running the above:

```
Switched to context "john.smith.cnnos-cluster".
```

3) If you are going to be accessing the Kubernetes cluster remotely, you will need to copy the generated kubeconfig file to the target user home directory on that host.

This step can be skipped if you will only be accessing the Kubernetes cluster locally - on the host it was provisioned on.

Substitute "jsmith" below with the appropriate user info.
Substitute "192.168.0.10" with the IP of the target host that will be used to access the cluster.

Cut and paste these lines onto the shell of the host running your Kubernetes cluster:

```
ubuntu@server:~$ 
USERNAME=jsmith
USER_IP=192.168.0.10
KUBE_DIR=/home/${USERNAME}/.kube/
ssh ${USERNAME}@${USER_IP} mkdir -p ${KUBE_DIR}
scp ./kubeconfig ${USERNAME}@${USER_IP}:${KUBE_DIR}/config
ubuntu@server:~$ 
```

## Installing User Tools to Local Host

If accessing the Kubernetes cluster remotely, follow these steps to prepare that host to access the cluster.

This section can be skipped if you will only be accessing the Kubernetes cluster locally - on the host it was provisioned on.

1) Download the user tools installation script

```
ubuntu@host:~$ curl -Lo user-tools-install.sh https://raw.githubusercontent.com/snaproute-mino/user-tools/master/user-tools-install.sh
```

2) Make the script executable

```
ubuntu@host:~$ chmod +x user-tools-install.sh
```

3) Run the user tools installation

```
ubuntu@host:~$ ./user-tools-install.sh
```

4) Verify you can access the cluster using kubectl and the kubeconfig you generated

```
ubuntu@host:~$ kubectl get sa
```

## Setup Account Access For CN-NOS Release Images

1) Contact your SnapRoute representative or email info@snaproute.com to request an account to the SnapRoute image repo

For this example, we will use these credentials:

Userid: 		john.smith@snaproute.com
Password:		Sample_Password_1234 	

These examples need to be substituted below with the username/password provided to you by SnapRoute.

2) Create an image pull secret for the account provided in step 1

Substitute docker-username, docker-email, and docker-password with those provided and cut and paste these lines:

```
ubuntu@server:~$ 
kubectl create secret docker-registry snaproute-pull-secret \
--docker-server=repo.snaproute.com \
--docker-username=john.smith@snaproute.com \
--docker-email=john.smith@snaproute.com \
--docker-password=Sample_Password_1234
ubuntu@server:~$ 
```
You should see a message like this:

```
secret/snaproute-pull-secret created
```

## Deploying an onie-http Server For Hosting the CN-NOS Monolithic Image to ONIE VMs

1) Add the cn-nos release repo

Substitute the username and password to those used in the previous section.

```
ubuntu@server:~$ helm repo add cnnos-release --username="john.smith@snaproute.com" --password="Sample_Password_1234" https://repo.snaproute.com/chartrepo/release
```
You should see a message like this, after the repo is added:
```
"cnnos-release" has been added to your repositories
```

2) Perform a repo update to ensure you have access to the latest charts

```
ubuntu@server:~$ helm repo update
```
You should see output similar to below:
```
Hang tight while we grab the latest from your chart repositories...
...Skip local chart repository
...Successfully got an update from the "stable" chart repository
...Successfully got an update from the "cnnos-release" chart repository
Update Complete. ⎈ Happy Helming!⎈ 
```

3) List the available monolithic releases

```
ubuntu@server:~$ helm search cnnos-release/cnnos-monolithic --versions

NAME                          	CHART VERSION	APP VERSION	DESCRIPTION                
cnnos-release/cnnos-monolithic	v1.1.0-R15   	v1.1.0-R15 	A Helm chart for Kubernetes

```

4) Download the desired version chart

For this example, we are copying the "v1.1.0-R15" version listed in the search results and setting it to VERSION variable below.

Copy these lines to fetch the image:

```
ubuntu@server:~$ 
VERSION=v1.1.0-R15
helm fetch cnnos-release/cnnos-monolithic --version ${VERSION}
```

5) Deploy an onie-http server instance to host the CN-NOS monolithic image

```
ubuntu@server:~$ 
PULL_SECRET=snaproute-pull-secret
VERSION=v1.1.0-R15
helm template --name onie-http-server --set imagePullSecret=${PULL_SECRET} cnnos-monolithic-${VERSION}.tgz | kubectl create -f -
```

After this, you should see output similar to this:

```
service/onie-http-server-cnnos-monolithic created
deployment.apps/onie-http-server-cnnos-monolithic created
```

6) Verify the server is running 

Note: As the monolithic image is downloaded - the status will stay in "ContainerCreating" for several minutes.

```
ubuntu@server:~$ kubectl get pod
NAME                                                 READY   STATUS              RESTARTS   AGE
onie-http-server-cnnos-monolithic-75b986b495-7cf4m   0/1     ContainerCreating   0          73s
```

```
ubuntu@server:~$ kubectl get pod
NAME                                                 READY   STATUS    RESTARTS   AGE
onie-http-server-cnnos-monolithic-75b986b495-7cf4m   1/1     Running   0          2m38s

ubuntu@server:~$ kubectl get service -o wide
NAME                                TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE     SELECTOR
kubernetes                          ClusterIP   10.254.192.1    <none>        443/TCP   103m    <none>
onie-http-server-cnnos-monolithic   ClusterIP   10.254.244.11   <none>        80/TCP    3m20s   app.kubernetes.io/instance=onie-http-server,app.kubernetes.io/name=cnnos-monolithic
```

## Deploy a VM Topology Using the ONIE Server & Image Deployed

1) Add the cnnos-virtualization repo to helm to pull the necessary charts

```
ubuntu@server:~$ helm repo add cnnos-virtualization https://repo.snaproute.com/chartrepo/virtualization
```

You should see output similar to this:

```
"cnnos-virtualization" has been added to your repositories

```

2) Perform a repo update to ensure you have access to the latest charts

```
ubuntu@server:~$ helm repo update
```
You should see output similar to this:

```
Hang tight while we grab the latest from your chart repositories...
...Skip local chart repository
...Successfully got an update from the "stable" chart repository
...Successfully got an update from the "cnnos-release" chart repository
...Successfully got an update from the "cnnos-virtualization" chart repository
Update Complete. ⎈ Happy Helming!⎈ 
```

3) List the available topology charts

```
ubuntu@server:~$ helm search cnnos-virtualization
NAME                                 	CHART VERSION	APP VERSION	DESCRIPTION                                                 
cnnos-virtualization/clos-2x3        	v1.0.1       	v1.0.1     	clos topology with 2 spines, 3 leafs                        
cnnos-virtualization/cnnos-cluster   	v0.1.1       	v0.1.1     	A Helm chart for Kubernetes                                 
cnnos-virtualization/dhcp-server     	v1.0.1       	v1.0.1     	provides a dhcp server for onie bootstrapping               
cnnos-virtualization/node            	v1.0.1       	v1.0.1     	single node with port 1-4 connected to 5-8                  
cnnos-virtualization/node2node       	v1.0.1       	v1.0.1     	back to back node topology, containing only 2 nodes         
cnnos-virtualization/onie-services   	v1.0.1       	v1.0.1     	provides a simple deployment of services for onie boot/in...
cnnos-virtualization/topology-builder	v1.0.1       	v1.0.1     	Base chart that provides a way to quickly create network ...
cnnos-virtualization/ubuntu-vm       	v0.1.1       	v0.1.1     	A Helm chart for Kubernetes       
```

4) Download the desired version chart

From the above list, we are going to use this option:

```
cnnos-virtualization/node2node       	v1.0.1       	v1.0.1     	back to back node topology, containing only 2 nodes         
```

Run these commands to fetch this topology chart

```
ubuntu@server:~$ 
TOPOLOGY=node2node
VERSION=v1.0.1
helm fetch cnnos-virtualization/${TOPOLOGY} --version ${VERSION}
```

5) Deploy the chart 

Copy and paste these lines to deploy the chart:

```
ubuntu@server:~$ 
TOPOLOGY=node2node
VERSION=v1.0.1
CHART_FILE=${TOPOLOGY}-${VERSION}.tgz
TOPOLOGY_NAME=my-topology
CLUSTER_IP=$(kubectl get service onie-http-server-cnnos-monolithic -o jsonpath="{.spec.clusterIP}")

helm template --name ${TOPOLOGY_NAME} ${CHART_FILE} --set "topology-builder.dhcpOptions.privateOptions[0].value=http://${CLUSTER_IP}/monolithic/onie-installer-x86_64" --set "topology-builder.dhcpOptions.privateOptions[0].option=114" | kubectl create -f -
ubuntu@server:~$ 
```

You should see output similar to this:

```
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
ubuntu@server:~$ kubectl get vm

ubuntu@server:~$ kubectl get vmi

ubuntu@server:~$ kubectl get pod

ubuntu@server:~$ kubectl get vm
NAME                  AGE     RUNNING   VOLUME
my-topology-switch1   9m41s   true      
my-topology-switch2   9m41s   true     
 
ubuntu@server:~$ kubectl get vm
NAME                  AGE   RUNNING   VOLUME
my-topology-switch1   12s   Scheduling      
my-topology-switch2   12s   Scheduling      

ubuntu@server:~$ kubectl get vmi
NAME                  AGE   PHASE     IP              NODENAME
my-topology-switch1   14m   Running   10.254.128.12   server
my-topology-switch2   14m   Running   10.254.128.13   server

ubuntu@server:~$ kubectl get pod
NAME                                                 READY   STATUS    RESTARTS   AGE
my-topology.topology-6fb765b7df-m4n9v                1/1     Running   0          15m
onie-http-server-cnnos-monolithic-75b986b495-7cf4m   1/1     Running   0          27m
virt-launcher-my-topology-switch1-pphc5              2/2     Running   0          15m
virt-launcher-my-topology-switch2-66dfm              2/2     Running   0          15m

ubuntu@server:~$ 

```

When all of the pods show a "Running" status, you can proceed.

7) Console to a switch and onie installation can be observed 

Note: The console command will wait until VMI is running.

```
ubuntu@server:~$ virtctl console my-topology-switch1
Successfully connected to my-topology-switch1 console. The escape sequence is ^]

ONIE: OS Install Mode ...
Platform  : x86_64-kvm_x86_64-r0
Version   : master-201903271045-dirty
Build Date: 2019-03-27T10:45+00:00

<snip>

ONIE: Starting ONIE Service Discovery
Info: Attempting http://10.41.225.99/monolithic/onie-installer-x86_64 ...
ONIE: Executing installer: http://10.41.225.99/monolithic/onie-installer-x86_64

#### Snaproute CN-NOS installer ####
Install mode [ ? ]. Progress: 22% 
  Booting `SnapL Image (20190515231420)'

Loading SNAPL ...
starting version 234
```

8) The console of each switch can be accessed with the virtctl command

Note: The default user is "root" with no password

```
ubuntu@ip-172-31-23-254:~$ virtctl console my-topology-switch1
Successfully connected to my-topology-switch1 console. The escape sequence is ^]

CN_NOS CN-NOS-1.0.0 CN-NOS-unknown ttyS0

CN-NOS-unknown login: root
root@CN-NOS-unknown:~# 
root@CN-NOS-unknown:~# 

```

9) From the console of the virtual instance, the CLI can be accessed using the cncli command


```
root@CN-NOS-unknown:~# cncli
Welcome, root().
CN-NOS-unknown# 

```

From here, industry standard "?" and <tab> can be used to navigate the interface:

```
CN-NOS-unknown# ?
Available completions :
  bash                 GNU Bourne-Again SHell
  cli                  
  cnnos-install-mode   Force a clean onie install.
  cnnos-update-pods    Update pods from a monolithic image download.
  configure            Configure Switch
  copy                 Copy switch configuration (from and to)
  default              
  exit                 Exit out ot cncli
  kubectl              kubectl controls the Kubernetes cluster manager.
  ping                 send ICMP ECHO_REQUEST to network hosts
  ping6                send ICMP ECHO_REQUEST to network hosts
  reboot               Reboot the system
  show                 Show Desired / Running / Operational data
  supportsave          Get all the info for debug support
  |                    Output modifiers
  <cr>                 

```
```
CN-NOS-unknown# show ?
Available completions :
  bfd                
  desired-config     Show Desired Configuration data
  dhcp               
  evpn               
  fabric             
  fluentdcollector   Returns the properties for a fluentdCollector instance - input, output, host, protocol, severity, database parameters, etc.
  interface          
  ip                 
  ip6                
  ipsg               Provides IP source guard information
  ipv4interface      Returns information about a named interface including up and down time events, operational states, the VRF id.
  ipv6interface      Returns information about a named interface including up and down time events, operational states, the VRF id.
  lacpagg            Returns LACP aggregation statistics and LAG AdminState.
  lacpaggport        Returns LACP Aggregation Port states and statistics.
  lldpglobal         Returns information about LLDP enable/disable state, number of LLDP neighbors, system-wide LLDP Tx/Rx packets, and current transmit interval.
  lldpinterface      Returns LLDP information at the port level. Information is returned by interface name.
  mac                
  policy-map         
  protocol           
  running-config     Show Running Configuration data
  service            
  span               
  stp                
  system             
  v4route            Returns routing information about IPv4 routes installed on the system. Keyed by the VRF name and V4 prefix.
  v6route            Returns routing information about IPv6 routes installed on the system. Keyed by the VRF name and V6 prefix
  version            
  vrf                Returns information (name and id) for each VRF in the system.
  vxlantunnel        Vxlan Tunnel Information
  |                  Output modifiers
  <cr>               

```
