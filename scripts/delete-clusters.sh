#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          k3d Cluster Deletion Tool                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if k3d is installed
if ! command -v k3d &> /dev/null; then
    echo -e "${RED}✗ k3d is not installed${NC}"
    exit 1
fi

# Get list of clusters
CLUSTERS=$(k3d cluster list 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")

if [ -z "$CLUSTERS" ]; then
    echo -e "${YELLOW}⚠ No k3d clusters found${NC}"
    exit 0
fi

echo -e "${YELLOW}Found the following k3d clusters:${NC}"
echo ""

# Display clusters
counter=1
declare -a cluster_array
while IFS= read -r cluster; do
    if [ -n "$cluster" ]; then
        cluster_array+=("$cluster")
        echo "  $counter) $cluster"
        counter=$((counter + 1))
    fi
done <<< "$CLUSTERS"

echo ""
echo -e "${RED}⚠ WARNING: This will permanently delete all clusters and their data!${NC}"
echo ""

read -p "Are you sure you want to delete all clusters? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}Cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}Deleting clusters...${NC}"
echo ""

# Kill port forwards first
echo -e "${BLUE}→ Stopping port forwards...${NC}"
pkill -f "kubectl.*port-forward" 2>/dev/null || true
sleep 1
echo -e "${GREEN}✓ Port forwards stopped${NC}"
echo ""

# Delete each cluster
failed=0
for cluster in "${cluster_array[@]}"; do
    echo -e "${BLUE}→ Deleting cluster: $cluster${NC}"
    
    if k3d cluster delete "$cluster" 2>&1 | grep -q "deleted"; then
        echo -e "${GREEN}✓ Deleted: $cluster${NC}"
    else
        echo -e "${RED}✗ Failed to delete: $cluster${NC}"
        failed=$((failed + 1))
    fi
done

echo ""

# Verify deletion
remaining=$(k3d cluster list 2>/dev/null | tail -n +2 | wc -l || echo "0")

if [ "$remaining" -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         All clusters successfully deleted!              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  Some clusters failed to delete ($remaining remaining)   ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
    exit 1
fi
