#!/bin/bash

# Headscale Native Installation Script
# For Ubuntu 20.04+ without Docker

set -e

echo "🚀 Installing Headscale VPN Server (Native)..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}Don't run this script as root${NC}"
   exit 1
fi

# Update system
update_system() {
    echo -e "${YELLOW}Updating system...${NC}"
    sudo apt update && sudo apt upgrade -y
}

# Install dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing dependencies...${NC}"
    sudo apt install -y wget curl git sqlite3 nginx certbot python3-certbot-nginx
}

# Install Headscale
install_headscale() {
    echo -e "${YELLOW}Installing Headscale...${NC}"
    
    # Get latest release
    HEADSCALE_VERSION=$(curl -s https://api.github.com/repos/juanfont/headscale/releases/latest | grep -Po '"tag_name": "v\K[^"]*')
    
    # Download and install
    wget "https://github.com/juanfont/headscale/releases/download/v${HEADSCALE_VERSION}/headscale_${HEADSCALE_VERSION}_linux_amd64.tar.gz"
    tar -xzf "headscale_${HEADSCALE_VERSION}_linux_amd64.tar.gz"
    sudo mv headscale /usr/local/bin/
    rm "headscale_${HEADSCALE_VERSION}_linux_amd64.tar.gz"
    
    # Create user and directories
    sudo useradd --system --shell /usr/sbin/nologin --home-dir /var/lib/headscale --create-home headscale
    sudo mkdir -p /etc/headscale /var/lib/headscale /var/log/headscale
    sudo chown -R headscale:headscale /etc/headscale /var/lib/headscale /var/log/headscale
}

# Generate configuration
generate_config() {
    echo -e "${YELLOW}Generating configuration...${NC}"
    
    read -p "Enter your server domain: " SERVER_DOMAIN
    read -p "Enter admin email: " ADMIN_EMAIL
    
    sudo tee /etc/headscale/config.yaml > /dev/null << EOF
server_url: https://${SERVER_DOMAIN}
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 127.0.0.1:9090
grpc_listen_addr: 0.0.0.0:50443
grpc_allow_insecure: false

private_key_path: /var/lib/headscale/private.key
noise:
  private_key_path: /var/lib/headscale/noise_private.key

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
db_path: /var/lib/headscale/db.sqlite

acme_url: https://acme-v02.api.letsencrypt.org/directory
acme_email: ${ADMIN_EMAIL}

tls_letsencrypt_hostname: ${SERVER_DOMAIN}
tls_letsencrypt_cache_dir: /var/lib/headscale/cache
tls_letsencrypt_challenge_type: HTTP-01
tls_letsencrypt_listen: ":http"

log:
  format: text
  level: info

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

    sudo chown headscale:headscale /etc/headscale/config.yaml
}

# Create systemd service
create_systemd_service() {
    echo -e "${YELLOW}Creating systemd service...${NC}"
    
    sudo tee /etc/systemd/system/headscale.service > /dev/null << EOF
[Unit]
Description=Headscale VPN Server
After=network.target

[Service]
Type=simple
User=headscale
Group=headscale
ExecStart=/usr/local/bin/headscale serve
Restart=always
RestartSec=5
WorkingDirectory=/var/lib/headscale
Environment=HOME=/var/lib/headscale

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable headscale
}

# Configure Nginx
configure_nginx() {
    echo -e "${YELLOW}Configuring Nginx...${NC}"
    
    sudo tee /etc/nginx/sites-available/headscale > /dev/null << EOF
server {
    listen 80;
    server_name ${SERVER_DOMAIN};
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${SERVER_DOMAIN};
    
    ssl_certificate /etc/letsencrypt/live/${SERVER_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${SERVER_DOMAIN}/privkey.pem;
    
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    sudo ln -sf /etc/nginx/sites-available/headscale /etc/nginx/sites-enabled/
    sudo nginx -t
}

# Setup SSL certificate
setup_ssl() {
    echo -e "${YELLOW}Setting up SSL certificate...${NC}"
    sudo certbot --nginx -d ${SERVER_DOMAIN} --non-interactive --agree-tos --email ${ADMIN_EMAIL}
}

# Create management scripts
create_management_scripts() {
    echo -e "${YELLOW}Creating management scripts...${NC}"
    
    cat > manage-headscale.sh << 'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_help() {
    echo "Headscale Management Script"
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  start                    Start Headscale service"
    echo "  stop                     Stop Headscale service"
    echo "  restart                  Restart Headscale service"
    echo "  status                   Show service status"
    echo "  logs                     Show logs"
    echo "  create-user <username>   Create a new user"
    echo "  list-users               List all users"
    echo "  delete-user <username>   Delete a user"
    echo "  list-nodes               List all nodes"
    echo "  register <user> <key>    Register a machine"
    echo "  help                     Show this help"
}

case "$1" in
    start)
        echo -e "${GREEN}Starting Headscale...${NC}"
        sudo systemctl start headscale
        ;;
    stop)
        echo -e "${YELLOW}Stopping Headscale...${NC}"
        sudo systemctl stop headscale
        ;;
    restart)
        echo -e "${YELLOW}Restarting Headscale...${NC}"
        sudo systemctl restart headscale
        ;;
    status)
        sudo systemctl status headscale
        ;;
    logs)
        sudo journalctl -u headscale -f
        ;;
    create-user)
        if [ -z "$2" ]; then
            echo -e "${RED}Please provide a username${NC}"
            exit 1
        fi
        sudo headscale users create $2
        ;;
    list-users)
        sudo headscale users list
        ;;
    delete-user)
        if [ -z "$2" ]; then
            echo -e "${RED}Please provide a username${NC}"
            exit 1
        fi
        sudo headscale users destroy $2
        ;;
    list-nodes)
        sudo headscale nodes list
        ;;
    register)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${RED}Please provide username and machine key${NC}"
            exit 1
        fi
        sudo headscale nodes register --user $2 --key $3
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        ;;
esac
EOF

    chmod +x manage-headscale.sh
}

# Main installation process
main() {
    echo -e "${GREEN}🚀 Headscale Native Installation${NC}"
    echo ""
    
    update_system
    install_dependencies
    install_headscale
    generate_config
    create_systemd_service
    configure_nginx
    setup_ssl
    create_management_scripts
    
    # Start services
    sudo systemctl start headscale
    sudo systemctl restart nginx
    
    echo ""
    echo -e "${GREEN}✅ Installation complete!${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Create a user: ./manage-headscale.sh create-user myuser"
    echo "2. Install Tailscale on client devices"
    echo "3. Register clients with: tailscale up --login-server=https://${SERVER_DOMAIN}"
    echo "4. Access your VPN at: https://${SERVER_DOMAIN}"
    echo ""
    echo -e "${YELLOW}Management commands:${NC}"
    echo "./manage-headscale.sh help"
}

main "$@" 