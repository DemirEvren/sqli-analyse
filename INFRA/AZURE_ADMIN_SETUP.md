# Azure Admin Setup Guide

This document describes the **one-time setup** that the Azure subscription admin must perform before deployment engineers can use Terraform to deploy Shelfware.

## Overview

The deployment engineer has limited permissions (by design):
- ✅ Can create/manage VNets, AKS, monitoring, storage
- ❌ Cannot create role assignments (that requires higher privilege)

Therefore, **Azure admin must create 2 critical role assignments manually**. After that, the engineer can run `terraform apply` independently.

---

## Current Permissions

### Deployment Engineer Already Has (on main-infra RG):
- ✅ Network Contributor
- ✅ Azure Kubernetes Service Contributor Role  
- ✅ Log Analytics Contributor
- ✅ Monitoring Contributor

### Deployment Engineer Already Has (on tfstate RG):
- ✅ Storage Account Contributor
- ✅ Locks Contributor

### Deployment Engineer Does NOT Have:
- ❌ User Access Administrator (cannot create role assignments)

---

## What Azure Admin Needs to Do (One-Time Setup)

### Step 1: Create Resource Groups

```bash
# Main resource group (for VNet, AKS clusters, monitoring)
az group create \
  --name rg-sqli-main \
  --location westeurope

# Terraform state storage resource group
az group create \
  --name rg-sqli-tfstate \
  --location westeurope
```

### Step 2: Create the Two Critical Role Assignments

**Context**: AKS LoadBalancer services need to provision public IPs. This requires the AKS **kubelet identity** to have **Network Contributor** permission on the subnets. Without it, LoadBalancer IPs stay "pending" forever.

Since the deployment engineer cannot create role assignments (insufficient permissions), **you must create them manually**.

#### Step 2a: Get the AKS Cluster IDs (after Terraform creates them)

First, engineer runs `terraform apply`. Then you check:

```bash
# List all AKS clusters in the subscription
az aks list --output table

# You should see:
# Name             ResourceGroup    Location    
# shelfware-app    rg-sqli-main     westeurope
```

#### Step 2b: Get the Kubelet Identity Object IDs

```bash
# For the app cluster
APP_KUBELET_ID=$(az aks show \
  --resource-group rg-sqli-main \
  --name shelfware-app \
  --query "identity.principalId" -o tsv)

echo "App cluster kubelet identity: $APP_KUBELET_ID"

# For the loadtest cluster (if it exists)
LOADTEST_KUBELET_ID=$(az aks show \
  --resource-group rg-sqli-main \
  --name shelfware-loadtest \
  --query "identity.principalId" -o tsv 2>/dev/null || echo "")

if [ -n "$LOADTEST_KUBELET_ID" ]; then
  echo "Loadtest cluster kubelet identity: $LOADTEST_KUBELET_ID"
fi
```

#### Step 2c: Get Subnet IDs

```bash
# Get the app subnet ID
APP_SUBNET_ID=$(az network vnet subnet show \
  --resource-group rg-sqli-main \
  --vnet-name sqli-vnet \
  --name sqli-subnet-app \
  --query id -o tsv)

echo "App subnet: $APP_SUBNET_ID"

# Get the loadtest subnet ID (if needed)
LOADTEST_SUBNET_ID=$(az network vnet subnet show \
  --resource-group rg-sqli-main \
  --vnet-name sqli-vnet \
  --name sqli-subnet-loadtest \
  --query id -o tsv 2>/dev/null || echo "")

if [ -n "$LOADTEST_SUBNET_ID" ]; then
  echo "Loadtest subnet: $LOADTEST_SUBNET_ID"
fi
```

#### Step 2d: Create the Role Assignments

```bash
# Grant Network Contributor role to app cluster kubelet on app subnet
az role assignment create \
  --assignee $APP_KUBELET_ID \
  --role "Network Contributor" \
  --scope $APP_SUBNET_ID

echo "✅ Created role assignment for app cluster"

# Grant Network Contributor to loadtest cluster (if it exists)
if [ -n "$LOADTEST_KUBELET_ID" ] && [ -n "$LOADTEST_SUBNET_ID" ]; then
  az role assignment create \
    --assignee $LOADTEST_KUBELET_ID \
    --role "Network Contributor" \
    --scope $LOADTEST_SUBNET_ID
  
  echo "✅ Created role assignment for loadtest cluster"
fi
```

---

## Complete Step-by-Step Process

| When | Who | What |
|------|-----|------|
| **Once** | Admin | Run Step 1: Create resource groups |
| **Iteration 1** | Engineer | Run `terraform apply` |
| **Once** | Admin | Run Steps 2a-2d: Create role assignments |
| **From now on** | Engineer | Run `terraform apply` whenever needed (no admin involvement) |

---

## Why This Approach?

### Alternative 1: Grant engineer User Access Administrator
❌ Too risky — allows unrestricted role assignment across the subscription
❌ Violates principle of least privilege

### Alternative 2: Have admin create role assignments each time
❌ Not scalable — admin must manually intervene on every `terraform apply`

### This Approach (Admin creates once, Engineer applies many times)
✅ Secure — engineer has only necessary permissions
✅ Scalable — terraform can run independently after one-time setup
✅ Efficient — admin effort is minimal and one-time

---

## Verification

After admin creates the role assignments, engineer runs:

```bash
cd kubernetes-app/INFRA/terraform
terraform apply
```

Then verify LoadBalancer is provisioned:

```bash
export KUBECONFIG=kubernetes-app/INFRA/terraform/kubeconfigs/merged-admin.yaml

# Should show a public IP (not "pending")
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  --context shelfware-app-admin \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

If it's still pending after 5 minutes, check:

```bash
kubectl describe svc ingress-nginx-controller -n ingress-nginx \
  --context shelfware-app-admin | grep -A 10 "Events:"
```

If you see `LinkedAuthorizationFailed`, the role assignment wasn't created successfully.

---

## Troubleshooting

### "LinkedAuthorizationFailed" error

**Cause**: Role assignment wasn't created or is incorrect.

**Fix**: 
1. Verify the kubelet identity object ID is correct
2. Verify the subnet ID is correct
3. Re-run the `az role assignment create` commands

### "Principal not found"

**Cause**: The AKS cluster hasn't been fully provisioned yet.

**Fix**: Wait 2-3 minutes after `terraform apply` completes, then run Step 2.

---

## Reference: Built-in Role IDs

| Role | ID |
|------|-----|
| Network Contributor | 4d97b98b-1d4f-4787-a291-c67834d212e7 |
| User Access Administrator | 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9 |
| Owner | 8e3af657-a8ff-443c-a75c-2fe8c4bcb635 |



