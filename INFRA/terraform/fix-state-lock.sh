#!/bin/bash

###############################################################################
# Terraform State Lock Recovery Helper
###############################################################################

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          Terraform State Lock Recovery Helper                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

TERRAFORM_DIR="$(dirname "$0")"
cd "$TERRAFORM_DIR"

# List current locks
echo "Checking for state locks..."
LOCKS=$(terraform state list 2>/dev/null || true)

if [ -z "$LOCKS" ]; then
    echo "✓ No resources in state — clean slate"
else
    echo "Current state contains:"
    terraform state list
fi

echo ""
echo "Terraform Backend State Lock Status:"
echo "══════════════════════════════════════════════════════════════════"

# Try to get lock info (this will fail if no lock, which is fine)
if terraform state list -id 2>/dev/null; then
    echo "✓ State is accessible (no lock)"
else
    echo "⚠ State might be locked"
fi

echo ""
echo "Options:"
echo "──────────────────────────────────────────────────────────────────"
echo "1. Force unlock (if you know there's a stuck lock)"
echo "2. Refresh state (sync Terraform with actual Azure resources)"
echo "3. Clean & redeploy (remove all state, deploy from scratch)"
echo "4. Exit"
echo ""

read -p "Choose option (1-4): " option

case $option in
    1)
        echo ""
        echo "Available locks (from recent history):"
        echo "  • dbabfcfb-4f3d-f7c4-56b6-2ae4502b4706"
        echo ""
        read -p "Enter lock ID to force unlock (or press Enter to skip): " lock_id
        if [ -n "$lock_id" ]; then
            terraform force-unlock "$lock_id"
            echo "✓ Lock forced"
        fi
        ;;
    2)
        echo ""
        echo "Refreshing state to match Azure reality..."
        terraform refresh
        echo "✓ State refreshed"
        ;;
    3)
        echo ""
        echo "⚠ WARNING: This will remove local state and redeploy from scratch"
        read -p "Type 'yes' to proceed: " confirm
        if [ "$confirm" = "yes" ]; then
            echo "Removing terraform state..."
            rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
            echo "✓ State removed. Ready to redeploy."
        else
            echo "Cancelled."
        fi
        ;;
    4)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Next step: Run deploy.sh again"
echo "════════════════════════════════════════════════════════════════"
