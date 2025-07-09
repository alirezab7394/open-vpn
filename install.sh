#!/bin/bash

# High-Performance OpenVPN Server Setup Script
# Author: OpenVPN Server Setup Project
# Description: Automated installation script for OpenVPN server with web dashboard

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
OPENVPN_PORT=1194
DASHBOARD_PORT=8080
PROTOCOL="udp"
ENCRYPTION="AES-128-GCM"
AUTH="SHA256"
DH_KEY_SIZE=2048
RSA_KEY_SIZE=2048

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Function to check Ubuntu version
check_ubuntu_version() {
    if [[ ! -f /etc/lsb-release ]]; then
        print_error "This script is designed for Ubuntu systems"
        exit 1
    fi
    
    source /etc/lsb-release
    if [[ "${DISTRIB_ID}" != "Ubuntu" ]]; then
        print_error "This script is designed for Ubuntu systems"
        exit 1
    fi
    
    print_success "Ubuntu ${DISTRIB_RELEASE} detected"
}

# Function to update system
update_system() {
    print_status "Updating system packages..."
    apt-get update -y
    apt-get upgrade -y
    print_success "System updated successfully"
}

# Function to install dependencies
install_dependencies() {
    print_status "Installing dependencies..."
    apt-get install -y \
        curl \
        wget \
        git \
        ufw \
        openssl \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https
    print_success "Dependencies installed successfully"
}

# Function to install Docker
install_docker() {
    print_status "Installing Docker..."
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index
    apt-get update -y
    
    # Install Docker
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker installed successfully"
}

# Function to install Docker Compose
install_docker_compose() {
    print_status "Installing Docker Compose..."
    
    # Download Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # Make it executable
    chmod +x /usr/local/bin/docker-compose
    
    # Create symbolic link
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    print_success "Docker Compose installed successfully"
}

# Function to configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    # Enable UFW
    ufw --force enable
    
    # Allow SSH
    ufw allow ssh
    
    # Allow OpenVPN
    ufw allow ${OPENVPN_PORT}/${PROTOCOL}
    
    # Allow dashboard
    ufw allow ${DASHBOARD_PORT}/tcp
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    print_success "Firewall configured successfully"
}

# Function to create directory structure
create_directories() {
    print_status "Creating directory structure..."
    
    # Create necessary directories
    mkdir -p /opt/openvpn-server/{data,configs,scripts,ssl,docs}
    mkdir -p /opt/openvpn-server/data/{pki,clients,logs,db}
    
    # Set permissions
    chmod 755 /opt/openvpn-server
    chmod 700 /opt/openvpn-server/data/pki
    
    print_success "Directory structure created successfully"
}

# Function to generate server configuration
generate_server_config() {
    print_status "Generating server configuration..."
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me)
    
    # Create server configuration
    cat > /opt/openvpn-server/configs/server.conf << EOF
# OpenVPN Server Configuration
# High-Performance Setup

# Network settings
port ${OPENVPN_PORT}
proto ${PROTOCOL}
dev tun

# Certificates and keys
ca pki/ca.crt
cert pki/issued/server.crt
key pki/private/server.key
dh pki/dh.pem
tls-crypt pki/ta.key

# Server network
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist pki/ipp.txt

# Routing
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

# Performance optimizations
fast-io
sndbuf 0
rcvbuf 0
push "sndbuf 393216"
push "rcvbuf 393216"

# Security settings
cipher ${ENCRYPTION}
auth ${AUTH}
tls-version-min 1.2
tls-cipher TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256
remote-cert-tls client

# Connection settings
keepalive 10 120
persist-key
persist-tun
user nobody
group nogroup

# Logging
log-append /var/log/openvpn/server.log
status /var/log/openvpn/status.log
verb 3
mute 20

# Performance tweaks
txqueuelen 1000
topology subnet
client-config-dir /etc/openvpn/ccd

# Compression (disabled for performance)
compress

# Management interface
management 0.0.0.0 2080

# Exit notification
explicit-exit-notify 1
EOF

    print_success "Server configuration generated successfully"
}

# Function to create Docker Compose configuration
create_docker_compose() {
    print_status "Creating Docker Compose configuration..."
    
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  openvpn-server:
    image: d3vilh/openvpn-server:latest
    container_name: openvpn-server
    restart: unless-stopped
    ports:
      - "${OPENVPN_PORT}:1194/udp"
      - "2080:2080"
    volumes:
      - /opt/openvpn-server/data/pki:/etc/openvpn/pki
      - /opt/openvpn-server/data/clients:/etc/openvpn/clients
      - /opt/openvpn-server/data/logs:/var/log/openvpn
      - /opt/openvpn-server/configs/server.conf:/etc/openvpn/server.conf
    environment:
      - OPENVPN_SERVER_IP=${SERVER_IP}
      - OPENVPN_PORT=${OPENVPN_PORT}
      - PROTOCOL=${PROTOCOL}
    privileged: true
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    devices:
      - /dev/net/tun
    sysctls:
      - net.ipv4.ip_forward=1
    networks:
      - openvpn-network

  openvpn-ui:
    image: d3vilh/openvpn-ui:latest
    container_name: openvpn-ui
    restart: unless-stopped
    ports:
      - "${DASHBOARD_PORT}:8080"
    volumes:
      - /opt/openvpn-server/data/pki:/etc/openvpn/pki
      - /opt/openvpn-server/data/clients:/etc/openvpn/clients
      - /opt/openvpn-server/data/db:/opt/openvpn-ui/db
      - /opt/openvpn-server/data/logs:/var/log/openvpn
    environment:
      - OPENVPN_ADMIN_USERNAME=admin
      - OPENVPN_ADMIN_PASSWORD=UI_passw0rd
      - OPENVPN_MANAGEMENT_ADDRESS=openvpn-server
      - OPENVPN_MANAGEMENT_PORT=2080
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
    volumes:
      - /opt/openvpn-server/ssl:/etc/ssl/certs
      - /opt/openvpn-server/configs/nginx.conf:/etc/nginx/nginx.conf
    depends_on:
      - openvpn-ui
    networks:
      - openvpn-network

networks:
  openvpn-network:
    driver: bridge
EOF

    print_success "Docker Compose configuration created successfully"
}

# Function to generate SSL certificates
generate_ssl_certificates() {
    print_status "Generating SSL certificates..."
    
    # Create SSL directory
    mkdir -p /opt/openvpn-server/ssl
    
    # Generate self-signed certificate for dashboard
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /opt/openvpn-server/ssl/nginx.key \
        -out /opt/openvpn-server/ssl/nginx.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=${SERVER_IP}"
    
    print_success "SSL certificates generated successfully"
}

# Function to create nginx configuration
create_nginx_config() {
    print_status "Creating Nginx configuration..."
    
    cat > /opt/openvpn-server/configs/nginx.conf << EOF
events {
    worker_connections 1024;
}

http {
    upstream openvpn-ui {
        server openvpn-ui:8080;
    }
    
    server {
        listen 443 ssl;
        server_name ${SERVER_IP};
        
        ssl_certificate /etc/ssl/certs/nginx.crt;
        ssl_certificate_key /etc/ssl/certs/nginx.key;
        
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        
        location / {
            proxy_pass http://openvpn-ui;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOF

    print_success "Nginx configuration created successfully"
}

# Function to start services
start_services() {
    print_status "Starting OpenVPN services..."
    
    # Start services
    docker-compose up -d
    
    # Wait for services to start
    sleep 10
    
    print_success "OpenVPN services started successfully"
}

# Function to display final information
display_final_info() {
    print_success "OpenVPN Server Setup Complete!"
    echo
    echo "=================================="
    echo "   OpenVPN Server Information"
    echo "=================================="
    echo "Server IP: ${SERVER_IP}"
    echo "OpenVPN Port: ${OPENVPN_PORT}/${PROTOCOL}"
    echo "Dashboard URL: https://${SERVER_IP}:${DASHBOARD_PORT}"
    echo "Dashboard Credentials:"
    echo "  Username: admin"
    echo "  Password: UI_passw0rd"
    echo
    echo "Configuration files location: /opt/openvpn-server/"
    echo
    echo "Next steps:"
    echo "1. Access the dashboard at https://${SERVER_IP}:${DASHBOARD_PORT}"
    echo "2. Change the default admin password"
    echo "3. Create client configurations"
    echo "4. Download client config files"
    echo
    echo "For troubleshooting, check the logs:"
    echo "  docker-compose logs -f"
    echo
    print_warning "Remember to change the default dashboard password!"
}

# Main execution
main() {
    print_status "Starting OpenVPN Server Setup..."
    
    check_root
    check_ubuntu_version
    update_system
    install_dependencies
    install_docker
    install_docker_compose
    configure_firewall
    create_directories
    generate_server_config
    create_docker_compose
    generate_ssl_certificates
    create_nginx_config
    start_services
    display_final_info
    
    print_success "Installation completed successfully!"
}

# Run main function
main "$@" 