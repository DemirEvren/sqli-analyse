output "cluster_id" {
  value = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "cluster_fqdn" {
  value = azurerm_kubernetes_cluster.main.fqdn
}

output "kube_config_raw" {
  description = "Raw kubeconfig YAML. Sensitive — do not log."
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "kube_config" {
  description = "Structured kubeconfig for use in kubernetes/helm provider configs."
  value       = azurerm_kubernetes_cluster.main.kube_config[0]
  sensitive   = true
}

output "kube_admin_config" {
  description = "Admin kubeconfig — bypasses Azure RBAC, required when azure_rbac_enabled = true."
  value       = azurerm_kubernetes_cluster.main.kube_admin_config[0]
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Path to the written kubeconfig file."
  value       = local_file.kubeconfig.filename
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity (for RBAC assignments)."
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "oidc_issuer_url" {
  description = "OIDC Issuer URL for Workload Identity federation."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "node_resource_group" {
  value = azurerm_kubernetes_cluster.main.node_resource_group
}
