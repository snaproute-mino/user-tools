#!/bin/bash

helm repo add rook-release https://charts.rook.io/release
helm install --namespace rook-ceph --name rook-prod rook-release/rook-ceph
