# SnapRoute CN-NOS Virtualization

## Provisioning a single node Kubernetes cluster with virtualization dependencies (on an Ubuntu 18.04 system)

1) Download the provisioning script

    curl -Lo provision-vm-cluster.sh https://raw.githubusercontent.com/snaproute-mino/user-tools/master/virtualization/provision-vm-cluster.sh

```
server41@server41:~$ curl -Lo provision-vm-cluster.sh https://raw.githubusercontent.com/snaproute-mino/user-tools/master/virtualization/provision-vm-cluster.sh
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
server41@server41:~$ BOOTSTRAPPER=kubeadm ./provision-vm-cluster.sh 
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