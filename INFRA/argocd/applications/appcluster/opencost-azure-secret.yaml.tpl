# ─── OpenCost Azure Cloud Integration ─────────────────────────────────────────
# This file is applied ONLY on AKS (not k3d) by bootstrap-aks.sh.
# It creates the Secret that OpenCost reads for Azure billing data.
#
# OpenCost uses these credentials to call the Azure Billing Rate Card API,
# which returns the REAL price for each VM type (including RI, savings plans,
# spot pricing). This eliminates the need for the kanalyzer billing API
# scaling-factor workaround.
#
# Prerequisites (admin must do this once):
#   1. Create an Azure AD App Registration (or use the Terraform SP)
#   2. Assign it "Cost Management Reader" role on the subscription:
#        az role assignment create \
#          --assignee <client-id> \
#          --role "Cost Management Reader" \
#          --scope /subscriptions/<subscription-id>
#   3. Set the values below (or pass via deploy.sh environment variables)
#
# See: https://www.opencost.io/docs/configuration/azure
# ─────────────────────────────────────────────────────────────────────────────
apiVersion: v1
kind: Secret
metadata:
  name: opencost-azure-creds
  namespace: opencost
  labels:
    app.kubernetes.io/name: opencost
    app.kubernetes.io/component: cloud-integration
type: Opaque
stringData:
  # These are populated by bootstrap-aks.sh from environment variables.
  # DO NOT hardcode real values here — this file is committed to Git.
  AZURE_SUBSCRIPTION_ID: "${AZURE_SUBSCRIPTION_ID}"
  AZURE_TENANT_ID: "${AZURE_TENANT_ID}"
  AZURE_CLIENT_ID: "${AZURE_CLIENT_ID}"
  AZURE_CLIENT_SECRET: "${AZURE_CLIENT_SECRET}"
