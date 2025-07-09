#!/bin/bash

# Headscale Docker Setup Script
# For Ubuntu 20.04+ with Docker and web interface

set -e

echo "🚀 Installing Headscale VPN Server with Web Interface..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}Don't run this script as root${NC}"
   exit 1
fi

# Install Docker if not present
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Installing Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
        echo -e "${GREEN}Docker installed. Please logout and login again.${NC}"
    fi
}

# Install Docker Compose if not present
install_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}Installing Docker Compose...${NC}"
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
}

# Create directory structure
setup_directories() {
    echo -e "${YELLOW}Setting up directories...${NC}"
    mkdir -p headscale/{config,data}
    mkdir -p headscale-ui
    mkdir -p logs
}

# Generate configuration
generate_config() {
    echo -e "${YELLOW}Generating Headscale configuration...${NC}"
    
    read -p "Enter your server domain/IP: " SERVER_URL
    read -p "Enter admin email: " ADMIN_EMAIL
    
    cat > headscale/config/config.yaml << EOF
server_url: https://${SERVER_URL}
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 0.0.0.0:9090
grpc_listen_addr: 0.0.0.0:50443
grpc_allow_insecure: false

private_key_path: /etc/headscale/private.key
noise:
  private_key_path: /etc/headscale/noise_private.key

ip_prefixes:
  - fd7a:115c:a1e0::/48
  - 100.64.0.0/10

derp:
  server:
    enabled: true
    region_id: 999
    region_code: "headscale"
    region_name: "Headscale Embedded DERP"
    stun_listen_addr: "0.0.0.0:3478"
  urls:
    - https://controlplane.tailscale.com/derpmap/default
  paths: []
  auto_update_enabled: true
  update_frequency: 24h

disable_check_updates: false
ephemeral_node_inactivity_timeout: 30m
node_update_check_interval: 10s

db_type: sqlite3
db_path: /etc/headscale/db.sqlite

acme_url: https://acme-v02.api.letsencrypt.org/directory
acme_email: ${ADMIN_EMAIL}

tls_letsencrypt_hostname: ${SERVER_URL}
tls_letsencrypt_cache_dir: /var/lib/headscale/cache
tls_letsencrypt_challenge_type: HTTP-01
tls_letsencrypt_listen: ":http"

tls_cert_path: ""
tls_key_path: ""

log:
  format: text
  level: info

policy:
  path: ""
  
dns_config:
  override_local_dns: true
  nameservers:
    - 1.1.1.1
    - 8.8.8.8
  domains: []
  magic_dns: true
  base_domain: headscale.local

unix_socket: /var/run/headscale/headscale.sock
unix_socket_permission: "0770"
EOF
}

# Create docker-compose.yml
create_docker_compose() {
    echo -e "${YELLOW}Creating Docker Compose configuration...${NC}"
    
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  headscale:
    container_name: headscale
    image: headscale/headscale:latest
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "9090:9090"
      - "50443:50443"
      - "3478:3478/udp"
    volumes:
      - ./headscale/config:/etc/headscale
      - ./headscale/data:/var/lib/headscale
      - ./logs:/var/log/headscale
    command: headscale serve
    networks:
      - headscale-net

  headscale-ui:
    container_name: headscale-ui
    image: ghcr.io/gurucomputing/headscale-ui:latest
    restart: unless-stopped
    ports:
      - "8000:80"
    environment:
      - HEADSCALE_URL=http://headscale:8080
      - SCRIPT_NAME=/admin
    depends_on:
      - headscale
    networks:
      - headscale-net

  nginx:
    container_name: headscale-nginx
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./nginx/certs:/etc/nginx/certs
    depends_on:
      - headscale
      - headscale-ui
    networks:
      - headscale-net

networks:
  headscale-net:
    driver: bridge

volumes:
  headscale-data:
  headscale-config:
EOF
}

# Create nginx configuration
create_nginx_config() {
    echo -e "${YELLOW}Creating Nginx configuration...${NC}"
    
    mkdir -p nginx/certs
    
    cat > nginx/nginx.conf << EOF
events {
    worker_connections 1024;
}

http {
    upstream headscale {
        server headscale:8080;
    }
    
    upstream headscale-ui {
        server headscale-ui:80;
    }

    server {
        listen 80;
        server_name _;
        
        location / {
            return 301 https://\$server_name\$request_uri;
        }
    }

    server {
        listen 443 ssl http2;
        server_name _;
        
        ssl_certificate /etc/nginx/certs/fullchain.pem;
        ssl_certificate_key /etc/nginx/certs/privkey.pem;
        
        location / {
            proxy_pass http://headscale;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
        
        location /admin {
            proxy_pass http://headscale-ui;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOF
}

# Create management scripts
create_management_scripts() {
    echo -e "${YELLOW}Creating management scripts...${NC}"
    
    cat > start-server.sh << 'EOF'
#!/bin/bash
echo "🚀 Starting Headscale VPN Server..."
docker-compose up -d
echo "✅ Server started!"
echo "🌐 Web Interface: http://localhost:8000/admin"
echo "📊 Headscale API: http://localhost:8080"
echo "📈 Metrics: http://localhost:9090"
EOF

    cat > stop-server.sh << 'EOF'
#!/bin/bash
echo "🛑 Stopping Headscale VPN Server..."
docker-compose down
echo "✅ Server stopped!"
EOF

    cat > manage-users.sh << 'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_help() {
    echo "Headscale User Management"
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  create-user <username>    Create a new user"
    echo "  list-users               List all users"
    echo "  delete-user <username>   Delete a user"
    echo "  list-nodes               List all nodes"
    echo "  register-node <user>     Get registration command"
    echo "  help                     Show this help"
}

create_user() {
    if [ -z "$1" ]; then
        echo -e "${RED}Please provide a username${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Creating user: $1${NC}"
    docker-compose exec headscale headscale users create $1
}

list_users() {
    echo -e "${YELLOW}Current users:${NC}"
    docker-compose exec headscale headscale users list
}

delete_user() {
    if [ -z "$1" ]; then
        echo -e "${RED}Please provide a username${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Deleting user: $1${NC}"
    docker-compose exec headscale headscale users destroy $1
}

list_nodes() {
    echo -e "${YELLOW}Current nodes:${NC}"
    docker-compose exec headscale headscale nodes list
}

register_node() {
    if [ -z "$1" ]; then
        echo -e "${RED}Please provide a username${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Registration command for user $1:${NC}"
    echo -e "${GREEN}Run this on the client device:${NC}"
    echo "tailscale up --login-server=http://$(hostname -I | awk '{print $1}'):8080 --accept-routes --accept-dns=false"
    echo ""
    echo -e "${GREEN}Then approve the machine:${NC}"
    docker-compose exec headscale headscale nodes register --user $1 --key [machine-key]
}

case "$1" in
    create-user)
        create_user $2
        ;;
    list-users)
        list_users
        ;;
    delete-user)
        delete_user $2
        ;;
    list-nodes)
        list_nodes
        ;;
    register-node)
        register_node $2
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        ;;
esac
EOF

    cat > logs.sh << 'EOF'
#!/bin/bash
echo "📋 Headscale Logs (Press Ctrl+C to exit)"
docker-compose logs -f headscale
EOF

    # Make scripts executable
    chmod +x start-server.sh stop-server.sh manage-users.sh logs.sh
}

# Main installation process
main() {
    echo -e "${GREEN}🚀 Headscale VPN Server Installation${NC}"
    echo -e "${YELLOW}This will install Headscale with web interface${NC}"
    echo ""
    
    install_docker
    install_docker_compose
    setup_directories
    generate_config
    create_docker_compose
    create_nginx_config
    create_management_scripts
    
    echo ""
    echo -e "${GREEN}✅ Installation complete!${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Start the server: ./start-server.sh"
    echo "2. Create a user: ./manage-users.sh create-user myuser"
    echo "3. Access web interface: http://your-server-ip:8000/admin"
    echo "4. Install Tailscale on client devices"
    echo ""
    echo -e "${YELLOW}For detailed setup instructions, see the documentation${NC}"
}

main "$@" 