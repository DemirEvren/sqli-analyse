#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Kubernetes Port Forward Manager                    ║${NC}"
echo -e "${BLUE}║     (Grafana, Locust, Prometheus)                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to check if a port is already forwarded
check_port_forward() {
    local port=$1
    local name=$2
    if lsof -i :$port &>/dev/null; then
        echo -e "${YELLOW}⚠ Port $port already in use (likely $name)${NC}"
        return 0
    else
        return 1
    fi
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
    
    # Check if port is already in use
    if check_port_forward $local_port "$name"; then
        echo -e "${GREEN}✓ $name is already running on localhost:$local_port${NC}"
        return 0
    fi
    
    # Start port forward in background
    kubectl --context $context port-forward -n $namespace svc/$service $local_port:$remote_port > /dev/null 2>&1 &
    local pf_pid=$!
    
    # Wait a moment for port forward to start
    sleep 2
    
    # Verify it's running
    if check_port_forward $local_port "$name"; then
        echo -e "${GREEN}✓ $name started successfully on localhost:$local_port (PID: $pf_pid)${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to start $name on localhost:$local_port${NC}"
        kill $pf_pid 2>/dev/null || true
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
        
        # Grafana (app cluster)
        forward_port "k3d-shelfware-app" "monitoring" "monitoring-stack-grafana" "3000" "80" "Grafana"
        
        # Locust (loadtest cluster)
        forward_port "k3d-shelfware-loadtest" "locust" "locust-master" "8089" "8089" "Locust"
        
        # Prometheus (app cluster)
        forward_port "k3d-shelfware-app" "monitoring" "monitoring-stack-kube-prom-prometheus" "9090" "9090" "Prometheus"
        
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║         Port Forwards Ready!                           ║${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║ Grafana:     http://localhost:3000                     ║${NC}"
        echo -e "${GREEN}║ Locust:      http://localhost:8089                     ║${NC}"
        echo -e "${GREEN}║ Prometheus:  http://localhost:9090                     ║${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
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
        echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
        exit 1
        ;;
esac
