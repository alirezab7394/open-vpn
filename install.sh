#!/bin/bash

# WireGuard VPN Server Installation Script for Ubuntu
# This script sets up a complete WireGuard VPN server with web interface

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
WIREGUARD_PORT="51820"
WEB_PORT="8080"
WG_INTERFACE="wg0"
INSTALL_DIR="/opt/wireguard-server"
CONFIG_DIR="/etc/wireguard"
LOG_FILE="/var/log/wireguard-install.log"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Check Ubuntu version
check_ubuntu_version() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        print_error "This script is designed for Ubuntu"
        exit 1
    fi
    
    VERSION=$(lsb_release -rs)
    if [[ $(echo "$VERSION >= 20.04" | bc) -eq 1 ]]; then
        print_status "Ubuntu version $VERSION is supported"
    else
        print_error "Ubuntu version $VERSION is not supported. Minimum version is 20.04"
        exit 1
    fi
}

# Update system
update_system() {
    print_status "Updating system packages..."
    apt-get update -y
    apt-get upgrade -y
}

# Install WireGuard and dependencies
install_wireguard() {
    print_status "Installing WireGuard and dependencies..."
    apt-get install -y wireguard wireguard-tools iptables-persistent netfilter-persistent
    apt-get install -y qrencode curl wget openssl jq bc
    
    # Install Docker and Docker Compose
    if ! command -v docker &> /dev/null; then
        print_status "Installing Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        systemctl enable docker
        systemctl start docker
    fi
    
    # Install Node.js for web interface
    if ! command -v node &> /dev/null; then
        print_status "Installing Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt-get install -y nodejs
    fi
}

# Configure IP forwarding
configure_ip_forwarding() {
    print_status "Configuring IP forwarding..."
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
    sysctl -p
}

# Generate server keys
generate_server_keys() {
    print_status "Generating server keys..."
    wg genkey | tee /etc/wireguard/private.key | wg pubkey | tee /etc/wireguard/public.key
    chmod 600 /etc/wireguard/private.key
    chmod 644 /etc/wireguard/public.key
}

# Create WireGuard configuration
create_wireguard_config() {
    print_status "Creating WireGuard configuration..."
    
    # Get server IP
    SERVER_IP=$(curl -s ipv4.icanhazip.com)
    PRIVATE_KEY=$(cat /etc/wireguard/private.key)
    
    # Create directory structure
    mkdir -p $INSTALL_DIR/{clients,configs,web,logs}
    
    # Create server configuration
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = 10.8.0.1/24
ListenPort = $WIREGUARD_PORT
SaveConfig = true
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j MASQUERADE; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

EOF
    
    # Store configuration variables
    cat > $INSTALL_DIR/config.env <<EOF
SERVER_IP=$SERVER_IP
PRIVATE_KEY=$PRIVATE_KEY
WIREGUARD_PORT=$WIREGUARD_PORT
WEB_PORT=$WEB_PORT
WG_INTERFACE=$WG_INTERFACE
INSTALL_DIR=$INSTALL_DIR
CONFIG_DIR=$CONFIG_DIR
NEXT_IP=2
EOF
}

# Setup firewall
setup_firewall() {
    print_status "Setting up firewall..."
    
    # Enable UFW
    ufw enable
    
    # Allow SSH
    ufw allow ssh
    
    # Allow WireGuard port
    ufw allow $WIREGUARD_PORT/udp
    
    # Allow web interface
    ufw allow $WEB_PORT/tcp
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Reload firewall
    ufw reload
}

# Install web interface
install_web_interface() {
    print_status "Setting up web interface..."
    
    # Copy web files
    cp -r wireguard/web/* $INSTALL_DIR/web/
    
    # Install dependencies
    cd $INSTALL_DIR/web
    npm install
    
    # Create systemd service for web interface
    cat > /etc/systemd/system/wireguard-web.service <<EOF
[Unit]
Description=WireGuard Web Interface
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/web
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable wireguard-web
}

# Enable and start services
enable_services() {
    print_status "Enabling and starting services..."
    
    # Enable WireGuard
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
    
    # Start web interface
    systemctl start wireguard-web
    
    # Check service status
    if systemctl is-active --quiet wg-quick@wg0; then
        print_status "WireGuard service is running"
    else
        print_error "WireGuard service failed to start"
        exit 1
    fi
    
    if systemctl is-active --quiet wireguard-web; then
        print_status "Web interface is running"
    else
        print_error "Web interface failed to start"
        exit 1
    fi
}

# Create management script
create_management_script() {
    print_status "Creating management script..."
    cp manage.sh /usr/local/bin/wg-manage
    chmod +x /usr/local/bin/wg-manage
}

# Display final information
display_final_info() {
    print_status "Installation completed successfully!"
    echo ""
    echo "WireGuard VPN Server Configuration:"
    echo "  Server IP: $(curl -s ipv4.icanhazip.com)"
    echo "  WireGuard Port: $WIREGUARD_PORT"
    echo "  Web Interface: http://$(curl -s ipv4.icanhazip.com):$WEB_PORT"
    echo ""
    echo "Management commands:"
    echo "  wg-manage add-client <client_name> - Add new client"
    echo "  wg-manage remove-client <client_name> - Remove client"
    echo "  wg-manage list-clients - List all clients"
    echo "  wg-manage status - Show server status"
    echo ""
    echo "Configuration files are stored in: $INSTALL_DIR"
    echo "WireGuard configuration: /etc/wireguard/wg0.conf"
    echo "Installation log: $LOG_FILE"
}

# Main installation function
main() {
    echo "Starting WireGuard VPN Server Installation..."
    echo "This will install and configure a complete WireGuard VPN server with web interface."
    echo ""
    
    check_root
    check_ubuntu_version
    update_system
    install_wireguard
    configure_ip_forwarding
    generate_server_keys
    create_wireguard_config
    setup_firewall
    install_web_interface
    enable_services
    create_management_script
    display_final_info
    
    print_status "Installation completed successfully!"
}

# Run main function and log output
main 2>&1 | tee $LOG_FILE 