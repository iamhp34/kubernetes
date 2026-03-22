#!/bin/bash
set -euo pipefail

# =========================================================
# kops + kubectl installation and initial cluster setup
# =========================================================
# What this script does:
# 1. Downloads and installs kops
# 2. Downloads and installs kubectl
# 3. Sets local DNS style for kops using gossip DNS (*.k8s.local)
# 4. Creates an Amazon Simple Storage Service bucket for kops state
# 5. Exports KOPS_CLUSTER_NAME and KOPS_STATE_STORE
# 6. Generates a Secure Shell key pair for the cluster
#
# Requirements:
# - Linux machine
# - curl installed
# - Amazon Web Services Command Line Interface installed and configured
# - Valid Amazon Web Services credentials
# =========================================================

# -----------------------------
# User-editable variables
# -----------------------------
AWS_REGION="ap-south-1"
CLUSTER_PREFIX="mykopscluster"
BUCKET_PREFIX="my-kops-state-store"
SSH_KEY_PATH="$HOME/.ssh/id_ed25519_kops"

# -----------------------------
# Derived variables
# -----------------------------
KOPS_CLUSTER_NAME="${CLUSTER_PREFIX}.k8s.local"
S3_BUCKET_NAME="${BUCKET_PREFIX}-${RANDOM}-$(date +%s)"
KOPS_STATE_STORE="s3://${S3_BUCKET_NAME}"

# -----------------------------
# Helper functions
# -----------------------------
log() {
  echo
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: Required command not found: $1"
    exit 1
  fi
}

# -----------------------------
# Pre-checks
# -----------------------------
log "Checking required commands"
require_command curl
require_command chmod
require_command sudo
require_command aws

# -----------------------------
# Download and install kops
# -----------------------------
log "Downloading and installing kops"

KOPS_VERSION="$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)"
curl -Lo kops "https://github.com/kubernetes/kops/releases/download/${KOPS_VERSION}/kops-linux-amd64"
chmod +x kops
sudo mv kops /usr/local/bin/kops

echo "Installed kops version:"
kops version || true

# -----------------------------
# Download and install kubectl
# -----------------------------
log "Downloading and installing kubectl"

KUBECTL_VERSION="$(curl -s -L https://dl.k8s.io/release/stable.txt)"
curl -Lo kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl

echo "Installed kubectl version:"
kubectl version --client || true

# -----------------------------
# Local DNS via gossip DNS
# -----------------------------
log "Configuring local DNS style for kops"

echo "Using gossip DNS with cluster name: ${KOPS_CLUSTER_NAME}"
echo "For kops local DNS, the cluster name must end with .k8s.local"

# -----------------------------
# Create Amazon Simple Storage Service bucket
# -----------------------------
log "Creating Amazon Simple Storage Service bucket for kops state store"

# us-east-1 requires different create command
if [ "${AWS_REGION}" = "us-east-1" ]; then
  aws s3api create-bucket \
    --bucket "${S3_BUCKET_NAME}" \
    --region "${AWS_REGION}"
else
  aws s3api create-bucket \
    --bucket "${S3_BUCKET_NAME}" \
    --region "${AWS_REGION}" \
    --create-bucket-configuration LocationConstraint="${AWS_REGION}"
fi

echo "Created bucket: ${S3_BUCKET_NAME}"

# Optional but recommended for versioning
aws s3api put-bucket-versioning \
  --bucket "${S3_BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

echo "Enabled versioning on bucket: ${S3_BUCKET_NAME}"

# -----------------------------
# Export environment variables
# -----------------------------
log "Exporting environment variables"

export KOPS_CLUSTER_NAME="${KOPS_CLUSTER_NAME}"
export KOPS_STATE_STORE="${KOPS_STATE_STORE}"

echo "export KOPS_CLUSTER_NAME=${KOPS_CLUSTER_NAME}" | tee -a "$HOME/.bashrc"
echo "export KOPS_STATE_STORE=${KOPS_STATE_STORE}" | tee -a "$HOME/.bashrc"

echo "Environment variables for current session:"
echo "KOPS_CLUSTER_NAME=${KOPS_CLUSTER_NAME}"
echo "KOPS_STATE_STORE=${KOPS_STATE_STORE}"

# -----------------------------
# Generate Secure Shell key pair
# -----------------------------
log "Generating Secure Shell key pair"

if [ ! -f "${SSH_KEY_PATH}" ]; then
  ssh-keygen -t ed25519 -f "${SSH_KEY_PATH}" -N ""
  echo "Secure Shell key created at: ${SSH_KEY_PATH}"
else
  echo "Secure Shell key already exists at: ${SSH_KEY_PATH}"
fi

# -----------------------------
# Final output
# -----------------------------
log "Setup complete"

cat <<EOF
kops and kubectl are installed.

RUN:
curl -O https://raw.githubusercontent.com/iamhp34/kubernetes/main/kops-cluster-setup.sh
chmod +x kops-cluster-setup.sh
./kops-cluster-setup.sh

Cluster name:
  ${KOPS_CLUSTER_NAME}

State store:
  ${KOPS_STATE_STORE}

Secure Shell public key:
  ${SSH_KEY_PATH}.pub

Next step example:
  kops create cluster \\
    --name=\${KOPS_CLUSTER_NAME} \\
    --cloud=aws \\
    --state=\${KOPS_STATE_STORE} \\
    --zones=${AWS_REGION}a \\
    --node-count=1 \\
    --node-size=t3.medium \\
    --control-plane-size=t3.medium \\
    --ssh-public-key=${SSH_KEY_PATH}.pub

Then apply it with:
  kops update cluster --name=\${KOPS_CLUSTER_NAME} --yes --admin
EOF
