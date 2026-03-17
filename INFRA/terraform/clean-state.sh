#!/bin/bash

###############################################################################
# Clean Fresh Start — Reset Terraform State
###############################################################################

set -e

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║            Terraform Fresh Start — Clean State Reset           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

TERRAFORM_DIR="$(dirname "$0")"
cd "$TERRAFORM_DIR"

echo "This will remove local Terraform state files and prepare for fresh deployment."
echo ""
echo "Options:"
echo "1. Keep backend storage (recommended) — deletes local state only"
echo "2. Delete everything — removes backend storage too (full reset)"
echo "3. Cancel"
echo ""

read -p "Choose (1-3): " choice

case $choice in
    1)
        echo ""
        echo "Removing local Terraform files..."
        rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
        echo "✓ Local state removed"
        echo ""
        echo "Ready to deploy fresh. Run:"
        echo "  bash deploy.sh app --skip-images"
        ;;
    2)
        echo ""
        echo "⚠️  WARNING: This will delete the entire backend storage account"
        read -p "Type 'yes' to proceed: " confirm
        if [ "$confirm" = "yes" ]; then
            # Get storage account name from backend.conf or use default
            if [ -f "backend.conf" ]; then
                SA_NAME=$(grep "storage_account_name" backend.conf | cut -d'"' -f2)
            else
                SA_NAME="tfstatesqlie43d9f59"
            fi
            
            echo ""
            echo "Deleting storage account: $SA_NAME"
            az storage account delete \
              --name "$SA_NAME" \
              --resource-group rg-sqli-tfstate \
              --yes 2>/dev/null || echo "⚠️  Storage account not found or already deleted"
            
            echo "Removing local files..."
            rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl backend.conf
            
            echo "✓ Complete reset done"
            echo ""
            echo "Ready for fresh deployment. Run:"
            echo "  bash deploy.sh app --skip-images"
        else
            echo "Cancelled."
        fi
        ;;
    3)
        echo "Cancelled."
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
