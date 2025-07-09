#!/bin/bash

# OpenVPN-UI Diagnostic Script
# This script helps diagnose issues with the OpenVPN-UI dashboard

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== OpenVPN-UI Diagnostic Script ===${NC}"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to test URL
test_url() {
    local url="$1"
    local description="$2"
    
    echo -e "${BLUE}Testing: $description${NC}"
    echo -e "URL: $url"
    
    if command_exists curl; then
        response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$response" = "200" ]; then
            echo -e "${GREEN}✓ SUCCESS - HTTP $response${NC}"
        elif [ "$response" = "000" ]; then
            echo -e "${RED}✗ FAILED - Connection refused or timeout${NC}"
        else
            echo -e "${YELLOW}⚠ WARNING - HTTP $response${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ curl not available, skipping HTTP test${NC}"
    fi
    echo ""
}

# 1. Check Docker containers
echo -e "${GREEN}1. Checking Docker containers status${NC}"
if command_exists docker; then
    docker-compose ps 2>/dev/null || echo "Docker Compose not available or not in correct directory"
else
    echo -e "${RED}Docker not available${NC}"
fi
echo ""

# 2. Check Docker logs
echo -e "${GREEN}2. Checking container logs (last 10 lines)${NC}"
if command_exists docker; then
    echo -e "${BLUE}--- OpenVPN-UI Logs ---${NC}"
    docker-compose logs --tail=10 openvpn-ui 2>/dev/null || echo "OpenVPN-UI container not found"
    echo ""
    
    echo -e "${BLUE}--- Nginx Logs ---${NC}"
    docker-compose logs --tail=10 nginx 2>/dev/null || echo "Nginx container not found"
    echo ""
    
    echo -e "${BLUE}--- OpenVPN Server Logs ---${NC}"
    docker-compose logs --tail=10 openvpn-server 2>/dev/null || echo "OpenVPN-Server container not found"
fi
echo ""

# 3. Check port bindings
echo -e "${GREEN}3. Checking port bindings${NC}"
if command_exists netstat; then
    echo "Active ports (OpenVPN related):"
    netstat -tulpn 2>/dev/null | grep -E ":(8080|443|1194|8080)" || echo "No matching ports found"
elif command_exists ss; then
    echo "Active ports (OpenVPN related):"
    ss -tulpn 2>/dev/null | grep -E ":(8080|443|1194|8080)" || echo "No matching ports found"
else
    echo "Neither netstat nor ss available"
fi
echo ""

# 4. Test various URLs
echo -e "${GREEN}4. Testing URL accessibility${NC}"

# Test direct OpenVPN-UI access
test_url "http://localhost:8080" "Direct OpenVPN-UI access"
test_url "http://localhost:8080/login" "OpenVPN-UI login page"

# Test through nginx
test_url "http://localhost:8080" "Nginx proxy to OpenVPN-UI"
test_url "http://localhost:8080/login" "Login through nginx"
test_url "http://localhost:8080/ov/clientconfig" "Client config page through nginx"

# Test with actual server IP if available
if command_exists hostname; then
    SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "")
    if [ -n "$SERVER_IP" ]; then
        test_url "http://$SERVER_IP:8080" "External access to nginx"
        test_url "http://$SERVER_IP:8080/ov/clientconfig" "External access to client config"
    fi
fi

# 5. Check nginx configuration
echo -e "${GREEN}5. Checking nginx configuration${NC}"
if [ -f "configs/nginx.conf" ]; then
    echo -e "${GREEN}✓ nginx.conf file exists${NC}"
    
    # Test nginx config syntax if possible
    if command_exists docker; then
        echo "Testing nginx configuration syntax:"
        docker-compose exec nginx nginx -t 2>/dev/null || echo "Could not test nginx config (container not running?)"
    fi
else
    echo -e "${RED}✗ nginx.conf file missing${NC}"
fi
echo ""

# 6. Check OpenVPN-UI specific endpoints
echo -e "${GREEN}6. Checking OpenVPN-UI specific endpoints${NC}"
if command_exists curl; then
    echo "Checking available routes on OpenVPN-UI:"
    
    # Try to get the main page and look for client-related links
    response=$(curl -s "http://localhost:8080" 2>/dev/null || echo "")
    if echo "$response" | grep -q "client"; then
        echo -e "${GREEN}✓ OpenVPN-UI main page accessible and contains client references${NC}"
    else
        echo -e "${YELLOW}⚠ OpenVPN-UI main page may not be fully functional${NC}"
    fi
    
    # Test various possible client config routes
    echo ""
    echo "Testing different possible client config routes:"
    test_url "http://localhost:8080/clients" "Direct /clients route"
    test_url "http://localhost:8080/client" "Direct /client route"
    test_url "http://localhost:8080/ov/clientconfig" "Direct /ov/clientconfig route"
    test_url "http://localhost:8080/clientconfig" "Direct /clientconfig route"
fi
echo ""

# 7. Check if OpenVPN server is properly initialized
echo -e "${GREEN}7. Checking OpenVPN server initialization${NC}"
if command_exists docker; then
    echo "Checking if PKI is initialized:"
    if docker-compose exec openvpn-server ls -la /etc/openvpn/pki/ 2>/dev/null | grep -q "ca.crt"; then
        echo -e "${GREEN}✓ PKI appears to be initialized${NC}"
    else
        echo -e "${RED}✗ PKI may not be initialized${NC}"
        echo "You may need to initialize PKI manually:"
        echo "docker-compose exec openvpn-server ovpn_genconfig -u udp://YOUR_SERVER_IP"
        echo "docker-compose exec openvpn-server ovpn_initpki"
    fi
fi
echo ""

# 8. Recommendations
echo -e "${GREEN}8. Recommendations${NC}"
echo "Based on the diagnostic results above:"
echo ""
echo "If containers are not running:"
echo "  → Run: docker-compose up -d"
echo ""
echo "If nginx configuration is missing:"
echo "  → Run: cp configs/nginx-http-only.conf configs/nginx.conf"
echo ""
echo "If OpenVPN-UI is not accessible directly:"
echo "  → Check OpenVPN-UI container logs for errors"
echo "  → Verify the container is running and healthy"
echo ""
echo "If /ov/clientconfig specifically doesn't work:"
echo "  → Try accessing /clients or /client instead"
echo "  → Check if the OpenVPN-UI version uses different routing"
echo ""
echo "If PKI is not initialized:"
echo "  → Run the PKI initialization commands shown above"
echo ""
echo -e "${YELLOW}For more detailed troubleshooting, see docs/TROUBLESHOOTING.md${NC}" 