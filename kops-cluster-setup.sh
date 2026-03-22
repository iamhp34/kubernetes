#!/bin/bash
set -e

echo "Starting kops and kubectl setup..."

# Install kops
curl -LO https://github.com/kubernetes/kops/releases/latest/download/kops-linux-amd64
chmod +x kops-linux-amd64
sudo mv kops-linux-amd64 /usr/local/bin/kops

echo "kops installed:"
kops version

# Install kubectl
curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl

echo "kubectl installed:"
kubectl version --client

# Create local DNS style cluster name
export KOPS_CLUSTER_NAME=mykopscluster.k8s.local
echo "export KOPS_CLUSTER_NAME=mykopscluster.k8s.local" >> ~/.bashrc

echo "Local DNS cluster name set:"
echo $KOPS_CLUSTER_NAME

echo "Setup completed successfully."
echo "Now run: source ~/.bashrc"


: <<'KOPS_FLOW'

=========================================================
STEP 1: CREATE S3 BUCKET (STATE STORE)
=========================================================
aws s3api create-bucket \
  --bucket my-kops-state-store-<unique-name> \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

=========================================================
STEP 2: EXPORT VARIABLES
=========================================================
export KOPS_CLUSTER_NAME=mykopscluster.k8s.local
export KOPS_STATE_STORE=s3://my-kops-state-store-<unique-name>

=========================================================
STEP 3: GENERATE SSH KEY
=========================================================
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_kops -N ""

=========================================================
STEP 4: CREATE CLUSTER (DEFINE ONLY)
=========================================================
kops create cluster \
  --name=${KOPS_CLUSTER_NAME} \
  --cloud=aws \
  --state=${KOPS_STATE_STORE} \
  --zones=ap-south-1a \
  --node-count=2 \
  --node-size=t3.medium \
  --control-plane-size=t3.medium \
  --ssh-public-key=~/.ssh/id_ed25519_kops.pub

=========================================================
STEP 5: APPLY (ACTUAL CREATION)
=========================================================
kops update cluster \
  --name=${KOPS_CLUSTER_NAME} \
  --state=${KOPS_STATE_STORE} \
  --yes --admin

=========================================================
STEP 6: VALIDATE CLUSTER
=========================================================
kops validate cluster --wait 10m

=========================================================
STEP 7: CHECK NODES
=========================================================
kubectl get nodes
kubectl get pods -A

=========================================================
STEP 8: DELETE CLUSTER (CLEANUP)
=========================================================
kops delete cluster \
  --name=${KOPS_CLUSTER_NAME} \
  --state=${KOPS_STATE_STORE} \
  --yes

=========================================================
STEP 9: DELETE S3 BUCKET
=========================================================
aws s3 rb ${KOPS_STATE_STORE} --force

=========================================================

NOTES:
- Replace <unique-name> with a unique bucket name
- Always run: source ~/.bashrc before using variables
- Never skip "kops update cluster --yes"

=========================================================

KOPS_FLOW
