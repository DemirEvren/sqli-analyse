# ─── Outputs ──────────────────────────────────────────────────────────────────

output "resource_group_name" {
  description = "Azure resource group containing all shelfware resources (pre-created by admin)."
  value       = data.azurerm_resource_group.main.name
}

output "app_cluster_name" {
  value = module.aks_app.cluster_name
}

output "app_cluster_fqdn" {
  value = module.aks_app.cluster_fqdn
}

output "app_cluster_kubeconfig_path" {
  description = "Path to the app cluster kubeconfig. Set KUBECONFIG to this value."
  value       = module.aks_app.kubeconfig_path
}

output "loadtest_cluster_name" {
  value = var.deploy_loadtest_cluster ? module.aks_loadtest[0].cluster_name : null
}

output "loadtest_cluster_fqdn" {
  value = var.deploy_loadtest_cluster ? module.aks_loadtest[0].cluster_fqdn : null
}

output "loadtest_cluster_kubeconfig_path" {
  value = var.deploy_loadtest_cluster ? module.aks_loadtest[0].kubeconfig_path : null
}

output "merged_kubeconfig_path" {
  description = "Merged kubeconfig with both clusters. export KUBECONFIG=<this value>"
  value       = "${path.root}/kubeconfigs/merged.yaml"
}

output "nat_public_ip" {
  description = "Outbound NAT IP for both AKS clusters. Whitelist this in external APIs."
  value       = module.networking.nat_public_ip
}

output "log_analytics_workspace_id" {
  value = module.monitoring.log_analytics_workspace_id
}

output "next_steps" {
  description = "Instructions for completing the deployment after terraform apply."
  value       = <<-EOT
    ═══ Next steps after terraform apply ═══════════════════════════════════════

    1. Export the merged kubeconfig:
         export KUBECONFIG=${path.root}/kubeconfigs/merged.yaml

    2. Run the bootstrap script to install ArgoCD and deploy all workloads:
         cd ${path.root}
         ./bootstrap-aks.sh

    3. Verify:
         kubectl get applications -n argocd --context ${var.app_cluster_name}
         kubectl get pods -A --context ${var.app_cluster_name}

    4. Get the ingress IP and add DNS entries:
         INGRESS_IP=$(kubectl get svc ingress-nginx-controller \
           -n ingress-nginx \
           --context ${var.app_cluster_name} \
           -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
         echo "$INGRESS_IP  shelfware.local test.shelfware.local"
         # Add the above line to /etc/hosts OR configure your Azure DNS zone.

    NOTE: Container images are pulled from ghcr.io (not ACR).
          The ghcr-credentials Kubernetes secret is created by Terraform.
          No ACR login or AcrPull role assignment needed.

    ════════════════════════════════════════════════════════════════════════════
  EOT
}
