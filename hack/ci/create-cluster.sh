#!/bin/sh
set -o errexit

REPO_ROOT="${REPO_ROOT:-$(dirname "${BASH_SOURCE}")/../..}"
KUBECTL_BIN="${KUBECTL_BIN:-$REPO_ROOT/bin/kubectl}"
HELM_BIN="${HELM_BIN:-$REPO_ROOT/bin/helm}"
KIND_BIN="${KIND_BIN:-$REPO_ROOT/bin/kind}"
POLICY_APPROVER_TAG="${POLICY_APPROVER_TAG:-smoke}"
POLICY_APPROVER_REPO="${POLICY_APPROVER_REPO:-quay.io/jetstack/cert-manager-policy-approver}"
POLICY_APPROVER_IMAGE="$POLICY_APPROVER_REPO:$POLICY_APPROVER_TAG"

echo ">> building policy-approver binary..."
GOARCH=$(go env GOARCH) GOOS=linux CGO_ENABLED=0 go build -o $REPO_ROOT/bin/policy-approver-linux $REPO_ROOT/cmd/.

echo ">> building docker image..."
docker build -t $POLICY_APPROVER_IMAGE .

echo ">> creating kind cluster..."
$KIND_BIN delete cluster --name policy-approver
cat <<EOF | $KIND_BIN create cluster --name policy-approver --config=-
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
kubeadmConfigPatches:
  - |
    # config generated by kind
    apiVersion: kubeadm.k8s.io/v1beta2
    kind: ClusterConfiguration
    metadata:
      name: config
    networking:
      serviceSubnet: 10.0.0.0/16
EOF

echo ">> loading docker image..."
$KIND_BIN load docker-image $POLICY_APPROVER_IMAGE --name policy-approver

echo ">> installing cert-manager..."
$HELM_BIN repo add jetstack https://charts.jetstack.io --force-update
$HELM_BIN upgrade -i -n cert-manager cert-manager jetstack/cert-manager --set installCRDs=true --wait --create-namespace --set extraArgs={--controllers='*\,-certificaterequests-approver'} --set global.logLevel=2

echo ">> installing policy-approver..."
$HELM_BIN upgrade -i -n cert-manager cert-manager-policy-approver ./deploy/charts/policy-approver --wait --set app.logLevel=2 --set image.repository=$POLICY_APPROVER_REPO --set image.tag=$POLICY_APPROVER_TAG
