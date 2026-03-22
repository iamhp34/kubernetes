#!/bin/bash
set -e

# --- CONFIGURATION ---
# Change 'my-unique-kops-state' to something globally unique
BUCKET_NAME="my-kops-state-store-$(date +%s)" 
REGION="ap-south-1"
ZONE="ap-south-1a"
CLUSTER_NAME="mykopscluster.k8s.local"

echo "---------------------------------------------------------"
echo "Starting kops and kubectl setup for $CLUSTER_NAME"
echo "---------------------------------------------------------"

# 1. Install kops
if ! command -v kops &> /dev/null; then
    echo "Installing kops..."
    curl -LO https://github.com/kubernetes/kops/releases/latest/download/kops-linux-amd64
    chmod +x kops-linux-amd64
    sudo mv kops-linux-amd64 /usr/local/bin/kops
else
    echo "kops already installed: $(kops version --short)"
fi

# 2. Install kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl
else
    echo "kubectl already installed: $(kubectl version --client --output=yaml | grep gitVersion)"
fi

# 3. Setup Environment Variables & Persistence
echo "Setting up environment variables..."
export KOPS_CLUSTER_NAME=$CLUSTER_NAME
export KOPS_STATE_STORE="s3://$BUCKET_NAME"

# Add to bashrc if not already there
grep -qxF "export KOPS_CLUSTER_NAME=$CLUSTER_NAME" ~/.bashrc || echo "export KOPS_CLUSTER_NAME=$CLUSTER_NAME" >> ~/.bashrc
grep -qxF "export KOPS_STATE_STORE=s3://$BUCKET_NAME" ~/.bashrc || echo "export KOPS_STATE_STORE=s3://$BUCKET_NAME" >> ~/.bashrc

# 4. Create S3 Bucket (State Store)
echo "Creating S3 bucket: $BUCKET_NAME in $REGION..."
aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"

# 5. Generate SSH Key (ED25519)
if [ ! -f ~/.ssh/id_ed25519_kops ]; then
    echo "Generating SSH key for cluster access..."
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_kops -N ""
else
    echo "SSH key already exists at ~/.ssh/id_ed25519_kops"
fi

# 6. Create Cluster Definition (Single AZ)
echo "Defining cluster configuration..."
kops create cluster \
    --name="${KOPS_CLUSTER_NAME}" \
    --cloud=aws \
    --state="${KOPS_STATE_STORE}" \
    --zones="${ZONE}" \
    --node-count=2 \
    --node-size=t3.medium \
    --control-plane-size=t3.medium \
    --ssh-public-key=~/.ssh/id_ed25519_kops.pub

# 7. Build the Cluster
echo "Applying configuration (this will take a few minutes)..."
kops update cluster --name "${KOPS_CLUSTER_NAME}" --yes --admin

echo "---------------------------------------------------------"
echo "SETUP INITIATED SUCCESSFULLY"
echo "---------------------------------------------------------"
echo "1. Run: source ~/.bashrc"
echo "2. Wait 5-10 mins, then run: kops validate cluster --wait 15m"
echo "3. To delete everything later, run: "
echo "   kops delete cluster --name \$KOPS_CLUSTER_NAME --yes"
echo "   aws s3 rb \$KOPS_STATE_STORE --force"
