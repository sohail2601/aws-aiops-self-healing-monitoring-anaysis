#!/bin/bash

# =========================================================
# KOPS KUBERNETES CLUSTER SETUP ON AWS
# Region: ap-south-1
# Cluster: sohail.k8s.local
# =========================================================

set -e

REGION="ap-south-1"
BUCKET="kops-bkt-1321"
CLUSTER="sohail.k8s.local"
ZONE="ap-south-1a"

CONTROL_PLANE_TYPE="t3.small"
NODE_TYPE="t3.small"

echo "======================================"
echo "1. Installing required packages"
echo "======================================"

yum install -y  wget unzip

echo "======================================"
echo "2. Installing AWS CLI"
echo "======================================"

if ! command -v aws >/dev/null 2>&1; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
fi

aws --version

echo "======================================"
echo "3. Checking AWS IAM role"
echo "======================================"

aws sts get-caller-identity

echo "======================================"
echo "4. Creating S3 bucket if required"
echo "======================================"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "S3 bucket already exists: $BUCKET"
else
    aws s3api create-bucket \
        --bucket "$BUCKET" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"
fi

echo "======================================"
echo "5. Enabling S3 versioning"
echo "======================================"

aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --versioning-configuration Status=Enabled

echo "======================================"
echo "6. Setting KOPS state store"
echo "======================================"

export KOPS_STATE_STORE="s3://$BUCKET"

echo "KOPS_STATE_STORE=$KOPS_STATE_STORE"

echo "======================================"
echo "7. Installing KOPS"
echo "======================================"

if ! command -v kops >/dev/null 2>&1; then
    curl -Lo /tmp/kops \
        https://github.com/kubernetes/kops/releases/download/v1.36.2/kops-linux-amd64

    chmod +x /tmp/kops
    mv /tmp/kops /usr/local/bin/kops
fi

kops version

echo "======================================"
echo "8. Installing kubectl"
echo "======================================"

if ! command -v kubectl >/dev/null 2>&1; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
fi

kubectl version --client

echo "======================================"
echo "9. Checking whether cluster already exists"
echo "======================================"

if kops get cluster \
    --name="$CLUSTER" \
    --state="$KOPS_STATE_STORE" >/dev/null 2>&1; then

    echo "Cluster already exists."
    echo "Skipping cluster creation."

else

    echo "Creating KOPS cluster..."

    kops create cluster \
        --name="$CLUSTER" \
        --state="$KOPS_STATE_STORE" \
        --zones="$ZONE" \
        --control-plane-count=1 \
        --control-plane-size="$CONTROL_PLANE_TYPE" \
        --node-count=2 \
        --node-size="$NODE_TYPE"

    echo "======================================"
    echo "10. Updating cluster"
    echo "======================================"

    kops update cluster \
        --name="$CLUSTER" \
        --state="$KOPS_STATE_STORE" \
        --yes

fi

echo "======================================"
echo "11. Exporting kubeconfig"
echo "======================================"

kops export kubeconfig \
    --name="$CLUSTER" \
    --state="$KOPS_STATE_STORE" \
    --admin

echo "======================================"
echo "12. Waiting for Kubernetes cluster"
echo "======================================"

kops validate cluster \
    --name="$CLUSTER" \
    --state="$KOPS_STATE_STORE" \
    --wait 10m

echo "======================================"
echo "13. Kubernetes Nodes"
echo "======================================"

kubectl get nodes -o wide

echo "======================================"
echo "KOPS CLUSTER SETUP COMPLETED"
echo "======================================"
