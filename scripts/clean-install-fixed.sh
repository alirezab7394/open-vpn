#!/bin/bash

# OpenVPN Clean Installation Script (Fixed)
# This script performs a complete clean installation of OpenVPN server with UI
# Fixed to handle easy-rsa.vars configuration issue

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== OpenVPN Clean Installation Script (Fixed) ===${NC}"
echo -e "${YELLOW}This will completely reset your OpenVPN installation!${NC}"
echo -e "${YELLOW}All existing clients and configurations will be lost!${NC}"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Confirm clean installation
echo -e "${RED}Are you sure you want to proceed with clean installation? (y/N)${NC}"
read -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Get server IP
echo -e "${BLUE}Enter your server public IP address:${NC}"
read -r SERVER_IP
if [ -z "$SERVER_IP" ]; then
    echo -e "${RED}Server IP is required!${NC}"
    exit 1
fi

echo -e "${GREEN}Using server IP: $SERVER_IP${NC}"
echo ""

# 1. Stop and remove everything
echo -e "${BLUE}1. Stopping and removing existing containers...${NC}"
if command_exists docker; then
    docker-compose down --volumes --remove-orphans 2>/dev/null || echo "No containers to stop"
    docker system prune -f 2>/dev/null || echo "Could not prune system"
    echo -e "${GREEN}✓ Containers stopped and removed${NC}"
else
    echo -e "${RED}✗ Docker not available${NC}"
    exit 1
fi
echo ""

# 2. Fix docker-compose.yml by recreating it properly
echo -e "${BLUE}2. Recreating docker-compose.yml with proper formatting...${NC}"
if [ -f "docker-compose.yml" ]; then
    cp docker-compose.yml docker-compose.yml.backup
    echo "Backup created: docker-compose.yml.backup"
fi

cat > docker-compose.yml << 'EOF'
services:
  openvpn-server:
    image: d3vilh/openvpn-server:latest
    container_name: openvpn-server
    restart: unless-stopped
    ports:
      - "1194:1194/udp"
      - "2080:2080"
    volumes:
      - ./data/pki:/etc/openvpn/pki
      - ./data/clients:/etc/openvpn/clients
      - ./data/logs:/var/log/openvpn
      - ./configs/server.conf:/etc/openvpn/server.conf
      - ./config/easy-rsa.vars:/etc/openvpn/config/easy-rsa.vars
      - ./scripts/connect.sh:/etc/openvpn/connect.sh
      - ./scripts/disconnect.sh:/etc/openvpn/disconnect.sh
    environment:
      - OPENVPN_PORT=1194
      - PROTOCOL=udp
      - EASYRSA_KEY_SIZE=2048
      - EASYRSA_CA_EXPIRE=3650
      - EASYRSA_CERT_EXPIRE=825
    privileged: true
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    devices:
      - /dev/net/tun:/dev/net/tun
    sysctls:
      - net.ipv4.ip_forward=1
    networks:
      - openvpn-network

  openvpn-ui:
    image: d3vilh/openvpn-ui:latest
    container_name: openvpn-ui
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./data/pki:/etc/openvpn/pki
      - ./data/clients:/etc/openvpn/clients
      - ./data/db:/opt/openvpn-ui/db
      - ./data/logs:/var/log/openvpn
    environment:
      - OPENVPN_ADMIN_USERNAME=admin
      - OPENVPN_ADMIN_PASSWORD=UI_passw0rd
      - OPENVPN_MANAGEMENT_ADDRESS=openvpn-server
      - OPENVPN_MANAGEMENT_PORT=2080
      - OPENVPN_SERVER_PORT=1194
      - OPENVPN_PROTO=udp
    depends_on:
      - openvpn-server
    networks:
      - openvpn-network

  nginx:
    image: nginx:alpine
    container_name: openvpn-nginx
    restart: unless-stopped
    ports:
      - "443:443"
      - "801:80"
    volumes:
      - ./ssl:/etc/ssl/certs
      - ./configs/nginx.conf:/etc/nginx/nginx.conf
    depends_on:
      - openvpn-ui
    networks:
      - openvpn-network

networks:
  openvpn-network:
    driver: bridge
EOF

echo -e "${GREEN}✓ docker-compose.yml recreated with proper formatting${NC}"
echo ""

# 3. Clean directories
echo -e "${BLUE}3. Cleaning directories...${NC}"
sudo rm -rf data/ ssl/ config/ 2>/dev/null || echo "Some directories didn't exist"
mkdir -p data/{pki,clients,logs,db}
mkdir -p ssl config
chmod 755 data data/pki data/clients data/logs data/db ssl config
echo -e "${GREEN}✓ Directories cleaned and created${NC}"
echo ""

# 4. Create easy-rsa.vars configuration
echo -e "${BLUE}4. Creating easy-rsa.vars configuration...${NC}"
cat > config/easy-rsa.vars << 'EOF'
# Easy-RSA configuration for OpenVPN
set_var EASYRSA_REQ_COUNTRY     "US"
set_var EASYRSA_REQ_PROVINCE    "State"
set_var EASYRSA_REQ_CITY        "City"
set_var EASYRSA_REQ_ORG         "OpenVPN"
set_var EASYRSA_REQ_EMAIL       "admin@openvpn.local"
set_var EASYRSA_REQ_OU          "OpenVPN Server"
set_var EASYRSA_KEY_SIZE        2048
set_var EASYRSA_ALGO            rsa
set_var EASYRSA_CA_EXPIRE       3650
set_var EASYRSA_CERT_EXPIRE     825
set_var EASYRSA_REQ_CN          "OpenVPN-CA"
EOF

echo -e "${GREEN}✓ easy-rsa.vars configuration created${NC}"
echo ""

# 5. Create nginx configuration
echo -e "${BLUE}5. Creating nginx configuration...${NC}"
mkdir -p configs
cat > configs/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    upstream openvpn-ui {
        server openvpn-ui:8080;
    }

    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass http://openvpn-ui;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $server_name;
            proxy_set_header X-Forwarded-Port $server_port;
            
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            
            proxy_connect_timeout       300;
            proxy_send_timeout          300;
            proxy_read_timeout          300;
            send_timeout                300;
            
            proxy_buffer_size          128k;
            proxy_buffers              4 256k;
            proxy_busy_buffers_size    256k;
        }
    }
}
EOF

echo -e "${GREEN}✓ Nginx configuration created${NC}"
echo ""

# 6. Create placeholder scripts if they don't exist
echo -e "${BLUE}6. Creating placeholder scripts...${NC}"
if [ ! -f "scripts/connect.sh" ]; then
    cat > scripts/connect.sh << 'EOF'
#!/bin/bash
# OpenVPN connect script
echo "Client connected: $1"
EOF
    chmod +x scripts/connect.sh
    echo -e "${GREEN}✓ connect.sh created${NC}"
else
    echo -e "${GREEN}✓ connect.sh already exists${NC}"
fi

if [ ! -f "scripts/disconnect.sh" ]; then
    cat > scripts/disconnect.sh << 'EOF'
#!/bin/bash
# OpenVPN disconnect script
echo "Client disconnected: $1"
EOF
    chmod +x scripts/disconnect.sh
    echo -e "${GREEN}✓ disconnect.sh created${NC}"
else
    echo -e "${GREEN}✓ disconnect.sh already exists${NC}"
fi
echo ""

# 7. Start OpenVPN server with proper initialization
echo -e "${BLUE}7. Starting OpenVPN server...${NC}"
docker-compose up -d openvpn-server
echo "Waiting for OpenVPN server to initialize..."
sleep 20

# Check if OpenVPN server is running
if ! docker-compose ps openvpn-server | grep -q "Up"; then
    echo -e "${RED}✗ OpenVPN server failed to start${NC}"
    echo "Logs:"
    docker-compose logs openvpn-server
    exit 1
fi

echo -e "${GREEN}✓ OpenVPN server started${NC}"
echo ""

# 8. Initialize OpenVPN manually
echo -e "${BLUE}8. Initializing OpenVPN configuration...${NC}"
echo "Generating OpenVPN configuration..."
docker-compose exec openvpn-server ovpn_genconfig -u udp://$SERVER_IP

echo "Initializing PKI (this may take a while)..."
echo -e "${YELLOW}When prompted, enter a strong passphrase for CA key${NC}"
echo -e "${YELLOW}When asked for Common Name, press Enter to use default${NC}"
docker-compose exec openvpn-server ovpn_initpki

echo -e "${GREEN}✓ OpenVPN initialized${NC}"
echo ""

# 9. Start OpenVPN-UI
echo -e "${BLUE}9. Starting OpenVPN-UI...${NC}"
docker-compose up -d openvpn-ui
echo "Waiting for OpenVPN-UI to start..."
sleep 15

# Check if OpenVPN-UI is running
if ! docker-compose ps openvpn-ui | grep -q "Up"; then
    echo -e "${RED}✗ OpenVPN-UI failed to start${NC}"
    echo "Logs:"
    docker-compose logs openvpn-ui
    exit 1
fi

echo -e "${GREEN}✓ OpenVPN-UI started${NC}"
echo ""

# 10. Start nginx
echo -e "${BLUE}10. Starting nginx proxy...${NC}"
docker-compose up -d nginx
echo "Waiting for nginx to start..."
sleep 10

# Check if nginx is running
if ! docker-compose ps nginx | grep -q "Up"; then
    echo -e "${RED}✗ nginx failed to start${NC}"
    echo "Logs:"
    docker-compose logs nginx
    exit 1
fi

echo -e "${GREEN}✓ nginx started${NC}"
echo ""

# 11. Test connectivity
echo -e "${BLUE}11. Testing connectivity...${NC}"
if command_exists curl; then
    echo "Testing OpenVPN-UI direct access..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080" | grep -q "200"; then
        echo -e "${GREEN}✓ OpenVPN-UI accessible on port 8080${NC}"
    else
        echo -e "${YELLOW}⚠ OpenVPN-UI not accessible on port 8080${NC}"
    fi
    
    echo "Testing nginx proxy..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:801" | grep -q "200"; then
        echo -e "${GREEN}✓ nginx proxy working on port 801${NC}"
    else
        echo -e "${YELLOW}⚠ nginx proxy not working on port 801${NC}"
    fi
else
    echo -e "${YELLOW}⚠ curl not available for testing${NC}"
fi
echo ""

# 12. Final status check
echo -e "${BLUE}12. Final status check...${NC}"
echo "Container status:"
docker-compose ps
echo ""

# 13. Create first client for testing
echo -e "${BLUE}13. Creating test client...${NC}"
echo -e "${YELLOW}Creating a test client to verify client configuration works...${NC}"
docker-compose exec openvpn-server easyrsa build-client-full test-client nopass
echo -e "${GREEN}✓ Test client created${NC}"
echo ""

# 14. Show final information
echo -e "${GREEN}=== Clean Installation Complete ===${NC}"
echo ""
echo -e "${GREEN}OpenVPN Server Information:${NC}"
echo "  - Server IP: $SERVER_IP"
echo "  - Protocol: UDP"
echo "  - Port: 1194"
echo ""
echo -e "${GREEN}Web Dashboard Access:${NC}"
echo "  - Main dashboard: http://$SERVER_IP:801"
echo "  - Direct OpenVPN-UI: http://$SERVER_IP:8080"
echo "  - Client configuration: http://$SERVER_IP:8080/ov/clientconfig"
echo ""
echo -e "${GREEN}Login Credentials:${NC}"
echo "  - Username: admin"
echo "  - Password: UI_passw0rd"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "1. Open your browser and go to: http://$SERVER_IP:8080"
echo "2. Login with the credentials above"
echo "3. Navigate to client configuration or try: http://$SERVER_IP:8080/ov/clientconfig"
echo "4. Create your first client configuration"
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo "- The test client 'test-client' has been created for testing"
echo "- Make sure your firewall allows ports 1194/UDP, 8080/TCP, and 801/TCP"
echo "- Your CA passphrase is required for creating new clients"
echo ""
echo -e "${GREEN}To create new clients via command line:${NC}"
echo "docker-compose exec openvpn-server easyrsa build-client-full CLIENT_NAME nopass"
echo "docker-compose exec openvpn-server ovpn_getclient CLIENT_NAME > CLIENT_NAME.ovpn"
echo ""
echo -e "${GREEN}Installation completed successfully!${NC}" 