#!/bin/bash

# Fix YAML Error in docker-compose.yml
# This script recreates the docker-compose.yml file with proper formatting

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Fixing YAML Error in docker-compose.yml ===${NC}"
echo ""

# Stop any running containers first
echo -e "${BLUE}1. Stopping existing containers...${NC}"
docker-compose down --remove-orphans 2>/dev/null || echo "No containers to stop"
echo -e "${GREEN}✓ Containers stopped${NC}"
echo ""

# Backup existing docker-compose.yml
echo -e "${BLUE}2. Backing up existing docker-compose.yml...${NC}"
if [ -f "docker-compose.yml" ]; then
    cp docker-compose.yml docker-compose.yml.backup
    echo -e "${GREEN}✓ Backup created: docker-compose.yml.backup${NC}"
else
    echo -e "${YELLOW}⚠ No existing docker-compose.yml found${NC}"
fi
echo ""

# Create a properly formatted docker-compose.yml
echo -e "${BLUE}3. Creating new docker-compose.yml...${NC}"
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

echo -e "${GREEN}✓ New docker-compose.yml created${NC}"
echo ""

# Validate the YAML syntax
echo -e "${BLUE}4. Validating YAML syntax...${NC}"
if command -v docker-compose >/dev/null 2>&1; then
    if docker-compose config >/dev/null 2>&1; then
        echo -e "${GREEN}✓ YAML syntax is valid${NC}"
    else
        echo -e "${RED}✗ YAML syntax is invalid${NC}"
        echo "Errors:"
        docker-compose config
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ docker-compose not available for validation${NC}"
fi
echo ""

# Create required directories
echo -e "${BLUE}5. Creating required directories...${NC}"
mkdir -p data/{pki,clients,logs,db}
mkdir -p ssl config configs scripts
chmod 755 data data/pki data/clients data/logs data/db ssl config configs scripts
echo -e "${GREEN}✓ Directories created${NC}"
echo ""

# Create easy-rsa.vars if it doesn't exist
echo -e "${BLUE}6. Creating easy-rsa.vars configuration...${NC}"
if [ ! -f "config/easy-rsa.vars" ]; then
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
    echo -e "${GREEN}✓ easy-rsa.vars created${NC}"
else
    echo -e "${GREEN}✓ easy-rsa.vars already exists${NC}"
fi
echo ""

# Create nginx.conf if it doesn't exist
echo -e "${BLUE}7. Creating nginx configuration...${NC}"
if [ ! -f "configs/nginx.conf" ]; then
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
    echo -e "${GREEN}✓ nginx.conf created${NC}"
else
    echo -e "${GREEN}✓ nginx.conf already exists${NC}"
fi
echo ""

# Create dummy scripts if they don't exist
echo -e "${BLUE}8. Creating placeholder scripts...${NC}"
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

# Final validation
echo -e "${BLUE}9. Final validation...${NC}"
if docker-compose config >/dev/null 2>&1; then
    echo -e "${GREEN}✓ docker-compose.yml is valid and ready to use${NC}"
else
    echo -e "${RED}✗ docker-compose.yml validation failed${NC}"
    docker-compose config
    exit 1
fi
echo ""

echo -e "${GREEN}=== YAML Error Fixed Successfully ===${NC}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Run the clean installation script:"
echo "   ./scripts/clean-install-fixed.sh"
echo ""
echo "2. Or start containers manually:"
echo "   docker-compose up -d openvpn-server"
echo "   # Wait for initialization, then:"
echo "   docker-compose up -d openvpn-ui nginx"
echo ""
echo -e "${YELLOW}Note: The old docker-compose.yml has been backed up as docker-compose.yml.backup${NC}" 