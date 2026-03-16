# Azure Admin Setup Guide

This document describes the **one-time setup** that the Azure subscription admin must perform before deployment engineers can use Terraform to deploy Shelfware.

## Who needs what?

### Azure Subscription Admin
The person who owns/manages the Azure subscription and can assign roles at the subscription level.

### Deployment Engineer
The person who runs `terraform apply` to deploy infrastructure (typically a DevOps engineer or SRE).

---

## Step 1: Grant the Deployment Engineer Required Roles

The deployment engineer needs to be granted **3 roles** at the **subscription level** (not resource group level):

### Role 1: User Access Administrator (or Owner)
**Why**: To create role assignments (RBAC) for AKS kubelet identities.

```bash
# Azure CLI command (run as subscription admin):
az role assignment create \
  --role "User Access Administrator" \
  --assignee <deployment-engineer-email-or-object-id> \
  --scope /subscriptions/<subscription-id>
```

**Alternative**: Grant "Owner" role instead (but more powerful — only if needed):
```bash
az role assignment create \
  --role "Owner" \
  --assignee <deployment-engineer-email-or-object-id> \
  --scope /subscriptions/<subscription-id>
```

### Role 2: Network Contributor
**Why**: To create VNets, subnets, NAT gateways, NSGs.

```bash
az role assignment create \
  --role "Network Contributor" \
  --assignee <deployment-engineer-email-or-object-id> \
  --scope /subscriptions/<subscription-id>
```

### Role 3: AKS Contributor Role
**Why**: To create/manage AKS clusters.

```bash
az role assignment create \
  --role "Azure Kubernetes Service Contributor Role" \
  --assignee <deployment-engineer-email-or-object-id> \
  --scope /subscriptions/<subscription-id>
```

### Role 4: Log Analytics Contributor (optional but recommended)
**Why**: To create and manage Log Analytics workspaces.

```bash
az role assignment create \
  --role "Log Analytics Contributor" \
  --assignee <deployment-engineer-email-or-object-id> \
  --scope /subscriptions/<subscription-id>
```

### Role 5: Monitoring Contributor (optional but recommended)
**Why**: To create diagnostic settings for AKS clusters.

```bash
az role assignment create \
  --role "Monitoring Contributor" \
  --assignee <deployment-engineer-email-or-object-id> \
  --scope /subscriptions/<subscription-id>
```

---

## Step 2: Create Resource Groups (Admin Only)

The admin creates resource groups that will be used by Terraform:

```bash
# Main resource group (for VNet, AKS clusters, Log Analytics)
az group create \
  --name rg-sqli-main \
  --location westeurope

# Terraform state storage resource group
az group create \
  --name rg-sqli-tfstate \
  --location westeurope
```

---

## Step 3: Deployment Engineer Runs Terraform

Once roles are granted, the deployment engineer can run:

```bash
cd kubernetes-app/INFRA/terraform
terraform init
terraform apply
```

Terraform will automatically:
1. ✅ Create VNet, subnets, NAT gateway
2. ✅ Create AKS clusters
3. ✅ Create role assignments (Network Contributor) for AKS kubelet identities on subnets
4. ✅ Provision LoadBalancer services with public IPs
5. ✅ Deploy monitoring stack

---

## Why the Role Assignments Are Needed

### The Problem
When an AKS LoadBalancer service is created, Kubernetes asks the underlying Azure cloud provider to provision a public IP and attach it to a network interface. This requires:

```
AKS Kubelet Identity → Network Contributor role on Subnet
```

Without this permission, Azure returns a `403 Forbidden` error, and the LoadBalancer IP remains "pending" forever.

### The Solution
Terraform now creates these role assignments automatically in `main.tf`:

```hcl
resource "azurerm_role_assignment" "aks_app_network_contributor" {
  scope              = module.networking.subnet_app_id
  role_definition_id = local.network_contributor_role_id
  principal_id       = module.aks_app.kubelet_identity_object_id
}
```

This means:
- ✅ **Permanent**: The role assignment is declarative, so it's recreated on every `terraform apply`
- ✅ **Automatic**: No manual Azure CLI commands needed after the first setup
- ✅ **Fresh Deploys**: Works on fresh teardown/redeploy cycles

---

## Verification

After `terraform apply` completes, verify the LoadBalancer IP is provisioned:

```bash
export KUBECONFIG=kubernetes-app/INFRA/terraform/kubeconfigs/merged-admin.yaml

# Should show a public IP (not "pending")
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  --context shelfware-app-admin \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

If it still shows `<pending>`, check the service events:

```bash
kubectl describe svc ingress-nginx-controller -n ingress-nginx \
  --context shelfware-app-admin | grep -A 10 Events:
```

If you see `LinkedAuthorizationFailed`, the role assignments weren't created (likely because the deployer doesn't have `User Access Administrator` role).

---

## Troubleshooting

### Error: "insufficient privileges" when creating role assignments

**Cause**: Deployment engineer doesn't have `User Access Administrator` role.

**Fix**: Ask Azure admin to run:
```bash
az role assignment create \
  --role "User Access Administrator" \
  --assignee <deployment-engineer-email> \
  --scope /subscriptions/<subscription-id>
```

### Error: "resource group not found"

**Cause**: Admin didn't create the resource groups.

**Fix**: Admin creates them:
```bash
az group create --name rg-sqli-main --location westeurope
az group create --name rg-sqli-tfstate --location westeurope
```

---

## Summary

| Step | Who | What |
|------|-----|------|
| 1 | Admin | Grant deployment engineer 3+ roles at subscription level |
| 2 | Admin | Create resource groups (`rg-sqli-main`, `rg-sqli-tfstate`) |
| 3 | Engineer | Run `terraform apply` |
| 4 | Engineer | Verify LoadBalancer IP is assigned (not pending) |

Once this is done, the deployment engineer can run `terraform apply` as many times as they want, and it will **automatically** handle all RBAC setup.

