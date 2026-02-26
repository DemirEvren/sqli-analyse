#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Kubernetes Port Forward Manager                    ║${NC}"
echo -e "${BLUE}║  (Grafana, Locust, Prometheus, ArgoCD, OpenCost)      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to check if a port is listening
port_is_listening() {
    local port=$1
    lsof -i :$port &>/dev/null
    return $?
}

# Function to forward a port
forward_port() {
    local context=$1
    local namespace=$2
    local service=$3
    local local_port=$4
    local remote_port=$5
    local name=$6
    
    echo -e "${BLUE}→ Setting up $name...${NC}"
    
    # Check if port is already listening (from previous run or other service)
    if port_is_listening $local_port; then
        echo -e "${GREEN}✓ $name is already available on localhost:$local_port${NC}"
        return 0
    fi
    
    # Verify context exists
    if ! kubectl config get-contexts $context &>/dev/null; then
        echo -e "${RED}✗ Context '$context' not found. Skipping $name.${NC}"
        return 1
    fi
    
    # Verify service exists
    if ! kubectl --context $context get svc $service -n $namespace &>/dev/null; then
        echo -e "${RED}✗ Service '$service' not found in namespace '$namespace'. Skipping $name.${NC}"
        return 1
    fi
    
    # Start port forward in background
    if kubectl --context $context port-forward -n $namespace svc/$service $local_port:$remote_port > /dev/null 2>&1 &
    then
        local pf_pid=$!
        
        # Wait a moment for port forward to start
        sleep 2
        
        # Verify it's listening
        if port_is_listening $local_port; then
            echo -e "${GREEN}✓ $name started on localhost:$local_port (PID: $pf_pid)${NC}"
            return 0
        else
            echo -e "${RED}✗ Failed to start port-forward for $name on localhost:$local_port${NC}"
            kill $pf_pid 2>/dev/null || true
            return 1
        fi
    else
        echo -e "${RED}✗ Failed to start port-forward for $name${NC}"
        return 1
    fi
}

# Menu
echo -e "${YELLOW}What would you like to do?${NC}"
echo "1) Deploy all port forwards (Grafana, Locust, Prometheus)"
echo "2) Close all port forwards"
echo ""
read -p "Enter choice (1 or 2): " choice

case $choice in
    1)
        echo ""
        echo -e "${BLUE}Starting port forwards...${NC}"
        echo ""
        
        # Track successes and failures
        success_count=0
        fail_count=0
        
        # Grafana (app cluster)
        forward_port "k3d-shelfware-app" "monitoring" "monitoring-stack-grafana" "3000" "80" "Grafana" && ((success_count++)) || ((fail_count++))
        
        # Locust (loadtest cluster)
        forward_port "k3d-shelfware-loadtest" "locust" "locust-master" "8089" "8089" "Locust" && ((success_count++)) || ((fail_count++))
        
        # Prometheus (app cluster) - using port 19090 to avoid conflict with OpenCost UI
        forward_port "k3d-shelfware-app" "monitoring" "monitoring-stack-kube-prom-prometheus" "19090" "9090" "Prometheus" && ((success_count++)) || ((fail_count++))
        
        # OpenCost (app cluster) - UI on port 9090
        forward_port "k3d-shelfware-app" "opencost" "opencost" "9090" "9090" "OpenCost" && ((success_count++)) || ((fail_count++))
        
        # ArgoCD (app cluster)
        forward_port "k3d-shelfware-app" "argocd" "argocd-server" "8080" "443" "ArgoCD" && ((success_count++)) || ((fail_count++))
        
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║         Port Forwards Ready!                           ║${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║ Grafana:     http://localhost:3000                     ║${NC}"
        echo -e "${GREEN}║ Locust:      http://localhost:8089                     ║${NC}"
        echo -e "${GREEN}║ Prometheus:  http://localhost:19090                    ║${NC}"
        echo -e "${GREEN}║ OpenCost:    http://localhost:9090                     ║${NC}"
        echo -e "${GREEN}║ ArgoCD:      https://localhost:8080                    ║${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║ Successful: $success_count | Failed: $fail_count                               ║${NC}"
        echo -e "${GREEN}║ Press Ctrl+C to stop port forwards                     ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # Keep script running to maintain port forwards
        wait
        ;;
    
    2)
        echo ""
        echo -e "${BLUE}Closing port forwards...${NC}"
        echo ""
        
        # Kill all kubectl port-forward processes
        pkill -f "kubectl.*port-forward" || true
        
        sleep 1
        
        echo -e "${GREEN}✓ All port forwards closed${NC}"
        echo ""
        ;;
    
    *)
        echo -e "${RED}✗ Invalid choice. Please enter 1 or 2.${NC}"
        exit 1
        ;;
esac

exit 0
