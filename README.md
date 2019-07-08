# SnapRoute CN-NOS user tools

## Installing user tools to local laptop / server

1) Download the user tools installation script

```
curl -Lo user-tools-install.sh https://raw.githubusercontent.com/snaproute-mino/user-tools/v1.0.0/user-tools-install.sh
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

## Setting up a new Kubernetes cluster for CN-NOS virtualization

https://github.com/snaproute-mino/user-tools/blob/v1.0.0/virtualization/README.MD
