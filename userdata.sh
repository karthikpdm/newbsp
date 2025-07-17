#!/bin/bash
# userdata.sh - Minimal bootstrap script for EKS worker nodes
# EKS-optimized AMI already has all required components pre-installed

# Exit on any error
set -e

# Variables passed from Terraform
CLUSTER_NAME="${cluster_name}"
BOOTSTRAP_ARGUMENTS="${bootstrap_arguments}"

# Log bootstrap process
exec > >(tee /var/log/user-data.log) 2>&1

echo "=========================================="
echo "Starting EKS Node Bootstrap"
echo "Cluster: $CLUSTER_NAME"
echo "Arguments: $BOOTSTRAP_ARGUMENTS"
echo "Timestamp: $(date)"
echo "=========================================="

# **THE ONLY REQUIRED COMMAND**
# This joins the node to the EKS cluster
echo "Bootstrapping node to join EKS cluster..."
/etc/eks/bootstrap.sh "$CLUSTER_NAME" $BOOTSTRAP_ARGUMENTS

# Verify bootstrap success
if [ $? -eq 0 ]; then
    echo "✅ Bootstrap successful!"
    echo "Node joined cluster: $CLUSTER_NAME"
else
    echo "❌ Bootstrap failed!"
    exit 1
fi

echo "=========================================="
echo "✅ EKS NODE READY"
echo "=========================================="