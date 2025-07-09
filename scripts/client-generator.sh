#!/bin/bash

# OpenVPN Client Configuration Generator
# This script generates client configuration files for OpenVPN

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
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

# Configuration
OPENVPN_DIR="/opt/openvpn-server"
PKI_DIR="${OPENVPN_DIR}/data/pki"
CLIENT_DIR="${OPENVPN_DIR}/data/clients"
TEMPLATE_DIR="${OPENVPN_DIR}/templates"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTION] CLIENT_NAME"
    echo ""
    echo "Options:"
    echo "  -c, --create    Create a new client certificate and configuration"
    echo "  -r, --revoke    Revoke a client certificate"
    echo "  -l, --list      List all client certificates"
    echo "  -s, --show      Show client configuration"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -c john-laptop"
    echo "  $0 -r john-laptop"
    echo "  $0 -l"
    echo "  $0 -s john-laptop"
}

# Function to get server IP
get_server_ip() {
    # Try multiple methods to get public IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
    
    if [[ -z "$SERVER_IP" ]]; then
        # Fallback to local IP
        SERVER_IP=$(ip route get 8.8.8.8 | awk '{print $7}' | head -1)
    fi
    
    if [[ -z "$SERVER_IP" ]]; then
        print_error "Could not determine server IP address"
        exit 1
    fi
    
    echo "$SERVER_IP"
}

# Function to create client certificate
create_client_cert() {
    local CLIENT_NAME="$1"
    
    print_info "Creating client certificate for: $CLIENT_NAME"
    
    # Check if client already exists
    if [[ -f "${PKI_DIR}/issued/${CLIENT_NAME}.crt" ]]; then
        print_warning "Client certificate already exists for: $CLIENT_NAME"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Aborted."
            exit 0
        fi
    fi
    
    # Create client certificate using easyrsa
    docker exec openvpn-server easyrsa build-client-full "$CLIENT_NAME" nopass
    
    print_success "Client certificate created successfully"
}

# Function to create client configuration
create_client_config() {
    local CLIENT_NAME="$1"
    local SERVER_IP="$2"
    
    print_info "Creating client configuration for: $CLIENT_NAME"
    
    # Create client configuration directory
    mkdir -p "${CLIENT_DIR}/${CLIENT_NAME}"
    
    # Create client configuration file
    cat > "${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn" << EOF
# OpenVPN Client Configuration
# Generated for: $CLIENT_NAME
# Server: $SERVER_IP
# Date: $(date)

client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-128-GCM
auth SHA256
tls-version-min 1.2
key-direction 1
verb 3
mute 20

# Performance optimizations
fast-io
sndbuf 0
rcvbuf 0

# Compression
compress

# Connection settings
keepalive 10 120
ping-timer-rem
ping-restart 120

# Security settings
remote-cert-tls server
tls-version-min 1.2

<ca>
$(cat "${PKI_DIR}/ca.crt")
</ca>

<cert>
$(cat "${PKI_DIR}/issued/${CLIENT_NAME}.crt")
</cert>

<key>
$(cat "${PKI_DIR}/private/${CLIENT_NAME}.key")
</key>

<tls-crypt>
$(cat "${PKI_DIR}/ta.key")
</tls-crypt>
EOF
    
    # Set permissions
    chmod 600 "${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    
    print_success "Client configuration created: ${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
}

# Function to create mobile-friendly configuration
create_mobile_config() {
    local CLIENT_NAME="$1"
    local SERVER_IP="$2"
    
    print_info "Creating mobile-friendly configuration for: $CLIENT_NAME"
    
    # Create mobile configuration with different settings
    cat > "${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}-mobile.ovpn" << EOF
# OpenVPN Mobile Client Configuration
# Generated for: $CLIENT_NAME
# Server: $SERVER_IP
# Date: $(date)

client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-128-GCM
auth SHA256
tls-version-min 1.2
key-direction 1
verb 3
mute 20

# Mobile optimizations
fast-io
connect-retry-max 5
connect-timeout 10
server-poll-timeout 8
explicit-exit-notify 1

# Compression
compress

# Connection settings for mobile
keepalive 10 60
ping-timer-rem
ping-restart 60

# Handle connection drops better on mobile
float
pull-filter ignore "block-outside-dns"
pull-filter ignore "dhcp-option DNS"
dhcp-option DNS 8.8.8.8
dhcp-option DNS 8.8.4.4

<ca>
$(cat "${PKI_DIR}/ca.crt")
</ca>

<cert>
$(cat "${PKI_DIR}/issued/${CLIENT_NAME}.crt")
</cert>

<key>
$(cat "${PKI_DIR}/private/${CLIENT_NAME}.key")
</key>

<tls-crypt>
$(cat "${PKI_DIR}/ta.key")
</tls-crypt>
EOF
    
    # Set permissions
    chmod 600 "${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}-mobile.ovpn"
    
    print_success "Mobile configuration created: ${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}-mobile.ovpn"
}

# Function to create QR code for mobile
create_qr_code() {
    local CLIENT_NAME="$1"
    
    if command -v qrencode >/dev/null 2>&1; then
        print_info "Creating QR code for mobile configuration..."
        
        # Create QR code
        qrencode -t PNG -o "${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}-qr.png" \
            -r "${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}-mobile.ovpn"
        
        print_success "QR code created: ${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}-qr.png"
    else
        print_warning "qrencode not installed. Install with: apt install qrencode"
    fi
}

# Function to list all clients
list_clients() {
    print_info "Listing all client certificates:"
    
    if [[ -d "${PKI_DIR}/issued" ]]; then
        echo "Active clients:"
        ls -la "${PKI_DIR}/issued" | grep -v "server.crt" | grep ".crt" | awk '{print $9}' | sed 's/.crt$//' | sort
    else
        print_warning "No client certificates found"
    fi
    
    echo
    
    if [[ -d "${PKI_DIR}/revoked" ]]; then
        echo "Revoked clients:"
        ls -la "${PKI_DIR}/revoked" | grep ".crt" | awk '{print $9}' | sed 's/.crt$//' | sort
    fi
}

# Function to revoke client certificate
revoke_client() {
    local CLIENT_NAME="$1"
    
    print_info "Revoking client certificate for: $CLIENT_NAME"
    
    # Check if client exists
    if [[ ! -f "${PKI_DIR}/issued/${CLIENT_NAME}.crt" ]]; then
        print_error "Client certificate not found: $CLIENT_NAME"
        exit 1
    fi
    
    # Revoke certificate
    docker exec openvpn-server easyrsa revoke "$CLIENT_NAME"
    docker exec openvpn-server easyrsa gen-crl
    
    # Remove client configuration
    if [[ -d "${CLIENT_DIR}/${CLIENT_NAME}" ]]; then
        rm -rf "${CLIENT_DIR}/${CLIENT_NAME}"
        print_success "Client configuration removed"
    fi
    
    print_success "Client certificate revoked: $CLIENT_NAME"
    print_warning "Restart OpenVPN server to apply changes"
}

# Function to show client configuration
show_client_config() {
    local CLIENT_NAME="$1"
    
    if [[ -f "${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn" ]]; then
        print_info "Client configuration for: $CLIENT_NAME"
        echo "File: ${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
        echo
        echo "--- Configuration ---"
        cat "${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    else
        print_error "Client configuration not found: $CLIENT_NAME"
        exit 1
    fi
}

# Function to create complete client package
create_client_package() {
    local CLIENT_NAME="$1"
    local SERVER_IP="$2"
    
    print_info "Creating complete client package for: $CLIENT_NAME"
    
    # Create client certificate
    create_client_cert "$CLIENT_NAME"
    
    # Create configurations
    create_client_config "$CLIENT_NAME" "$SERVER_IP"
    create_mobile_config "$CLIENT_NAME" "$SERVER_IP"
    
    # Create QR code
    create_qr_code "$CLIENT_NAME"
    
    # Create instructions file
    cat > "${CLIENT_DIR}/${CLIENT_NAME}/README.txt" << EOF
OpenVPN Client Configuration Package
Generated for: $CLIENT_NAME
Date: $(date)

Files included:
- ${CLIENT_NAME}.ovpn - Standard desktop configuration
- ${CLIENT_NAME}-mobile.ovpn - Mobile-optimized configuration
- ${CLIENT_NAME}-qr.png - QR code for mobile import (if available)
- README.txt - This file

Installation Instructions:

Windows:
1. Download and install OpenVPN GUI from https://openvpn.net/community-downloads/
2. Copy ${CLIENT_NAME}.ovpn to C:\Program Files\OpenVPN\config\
3. Right-click OpenVPN GUI icon and select "Connect"

macOS:
1. Download and install Viscosity from https://www.sparklabs.com/viscosity/
2. Import ${CLIENT_NAME}.ovpn into Viscosity
3. Connect to the VPN

Linux:
1. Install OpenVPN: sudo apt install openvpn
2. Connect using: sudo openvpn --config ${CLIENT_NAME}.ovpn

Android:
1. Install OpenVPN Connect from Google Play Store
2. Import ${CLIENT_NAME}-mobile.ovpn or scan the QR code

iOS:
1. Install OpenVPN Connect from App Store
2. Import ${CLIENT_NAME}-mobile.ovpn via iTunes File Sharing or email

Server Information:
- Server IP: $SERVER_IP
- Port: 1194
- Protocol: UDP
- Encryption: AES-128-GCM
- Authentication: SHA256

For support, contact your system administrator.
EOF
    
    print_success "Complete client package created in: ${CLIENT_DIR}/${CLIENT_NAME}/"
    print_info "Package contents:"
    ls -la "${CLIENT_DIR}/${CLIENT_NAME}/"
}

# Main function
main() {
    # Check if directories exist
    if [[ ! -d "$OPENVPN_DIR" ]]; then
        print_error "OpenVPN directory not found: $OPENVPN_DIR"
        print_error "Please run the main installation script first"
        exit 1
    fi
    
    # Parse command line arguments
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    case "$1" in
        -c|--create)
            if [[ -z "$2" ]]; then
                print_error "Client name required"
                show_usage
                exit 1
            fi
            CLIENT_NAME="$2"
            SERVER_IP=$(get_server_ip)
            create_client_package "$CLIENT_NAME" "$SERVER_IP"
            ;;
        -r|--revoke)
            if [[ -z "$2" ]]; then
                print_error "Client name required"
                show_usage
                exit 1
            fi
            CLIENT_NAME="$2"
            revoke_client "$CLIENT_NAME"
            ;;
        -l|--list)
            list_clients
            ;;
        -s|--show)
            if [[ -z "$2" ]]; then
                print_error "Client name required"
                show_usage
                exit 1
            fi
            CLIENT_NAME="$2"
            show_client_config "$CLIENT_NAME"
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 