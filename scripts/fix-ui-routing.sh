#!/bin/bash

# OpenVPN-UI Routing Fix Script
# This script attempts to fix common issues with the OpenVPN-UI dashboard routing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== OpenVPN-UI Routing Fix Script ===${NC}"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 1. Ensure nginx.conf exists
echo -e "${BLUE}1. Checking nginx configuration...${NC}"
if [ ! -f "configs/nginx.conf" ]; then
    echo -e "${YELLOW}⚠ nginx.conf missing, creating from HTTP-only template${NC}"
    if [ -f "configs/nginx-http-only.conf" ]; then
        cp configs/nginx-http-only.conf configs/nginx.conf
        echo -e "${GREEN}✓ Created nginx.conf${NC}"
    else
        echo -e "${RED}✗ nginx-http-only.conf template not found${NC}"
        echo "Please ensure the nginx configuration files exist."
        exit 1
    fi
else
    echo -e "${GREEN}✓ nginx.conf exists${NC}"
fi
echo ""

# 2. Create necessary directories
echo -e "${BLUE}2. Creating required directories...${NC}"
mkdir -p data/{pki,clients,logs,db}
echo -e "${GREEN}✓ Directories created${NC}"
echo ""

# 3. Stop and restart containers
echo -e "${BLUE}3. Restarting containers...${NC}"
if command_exists docker; then
    echo "Stopping containers..."
    docker-compose down 2>/dev/null || echo "No containers to stop"
    
    echo "Starting containers..."
    docker-compose up -d
    
    echo "Waiting for containers to be ready..."
    sleep 10
    
    echo -e "${GREEN}✓ Containers restarted${NC}"
else
    echo -e "${RED}✗ Docker not available${NC}"
    exit 1
fi
echo ""

# 4. Check container health
echo -e "${BLUE}4. Checking container health...${NC}"
if docker-compose ps | grep -q "Up"; then
    echo -e "${GREEN}✓ Containers are running${NC}"
else
    echo -e "${RED}✗ Some containers may not be running${NC}"
    echo "Container status:"
    docker-compose ps
fi
echo ""

# 5. Initialize OpenVPN if needed
echo -e "${BLUE}5. Checking OpenVPN initialization...${NC}"
if ! docker-compose exec openvpn-server ls -la /etc/openvpn/pki/ca.crt >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ OpenVPN PKI not initialized, initializing...${NC}"
    
    # Get server IP
    echo "Enter your server IP address:"
    read -r SERVER_IP
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="localhost"
    fi
    
    echo "Initializing OpenVPN configuration..."
    docker-compose exec openvpn-server ovpn_genconfig -u udp://$SERVER_IP
    
    echo "Initializing PKI (this may take a while)..."
    docker-compose exec openvpn-server ovpn_initpki
    
    echo -e "${GREEN}✓ OpenVPN initialized${NC}"
else
    echo -e "${GREEN}✓ OpenVPN already initialized${NC}"
fi
echo ""

# 6. Test accessibility
echo -e "${BLUE}6. Testing accessibility...${NC}"
if command_exists curl; then
    # Test direct OpenVPN-UI access
    echo "Testing direct OpenVPN-UI access..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080" | grep -q "200"; then
        echo -e "${GREEN}✓ OpenVPN-UI accessible directly${NC}"
    else
        echo -e "${YELLOW}⚠ OpenVPN-UI not accessible directly${NC}"
    fi
    
    # Test through nginx
    echo "Testing access through nginx..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080" | grep -q "200"; then
        echo -e "${GREEN}✓ Nginx proxy working${NC}"
    else
        echo -e "${YELLOW}⚠ Nginx proxy not working${NC}"
    fi
else
    echo -e "${YELLOW}⚠ curl not available for testing${NC}"
fi
echo ""

# 7. Show final status and instructions
echo -e "${GREEN}=== Fix Complete ===${NC}"
echo ""
echo "Access URLs:"
echo "  - Main dashboard: http://your-server-ip:8080"
echo "  - Direct OpenVPN-UI: http://your-server-ip:8080"
echo "  - Client configuration: http://your-server-ip:8080/ov/clientconfig"
echo ""
echo "Default login credentials:"
echo "  - Username: admin"
echo "  - Password: UI_passw0rd"
echo ""
echo "If you still can't access /ov/clientconfig, try these alternatives:"
echo "  - http://your-server-ip:8080/clients"
echo "  - http://your-server-ip:8080/client"
echo "  - Access the main dashboard and look for 'Clients' or 'Add Client' menu"
echo ""
echo "For further troubleshooting, run:"
echo "  chmod +x scripts/diagnose-ui.sh && ./scripts/diagnose-ui.sh"
echo ""
echo -e "${YELLOW}Note: Replace 'your-server-ip' with your actual server IP address${NC}" 