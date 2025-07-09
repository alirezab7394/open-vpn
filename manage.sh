#!/bin/bash

# WireGuard VPN Server Management Script
# This script provides easy management for WireGuard VPN server

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/wireguard-server"
CONFIG_DIR="/etc/wireguard"
WG_INTERFACE="wg0"
CONFIG_FILE="$CONFIG_DIR/wg0.conf"
ENV_FILE="$INSTALL_DIR/config.env"
CLIENTS_DIR="$INSTALL_DIR/clients"

# Load configuration
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo -e "${RED}Error: Configuration file not found at $ENV_FILE${NC}"
    exit 1
fi

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

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Get next available IP
get_next_ip() {
    local next_ip
    if [[ -f "$ENV_FILE" ]]; then
        next_ip=$(grep "NEXT_IP" "$ENV_FILE" | cut -d'=' -f2)
        if [[ -z "$next_ip" ]]; then
            next_ip=2
        fi
    else
        next_ip=2
    fi
    echo "$next_ip"
}

# Update next IP
update_next_ip() {
    local new_ip=$1
    sed -i "s/NEXT_IP=.*/NEXT_IP=$new_ip/" "$ENV_FILE"
}

# Generate client configuration
generate_client_config() {
    local client_name=$1
    local client_ip=$2
    local client_private_key=$3
    local client_public_key=$4
    local server_public_key=$(cat /etc/wireguard/public.key)
    
    cat > "$CLIENTS_DIR/$client_name.conf" <<EOF
[Interface]
PrivateKey = $client_private_key
Address = 10.8.0.$client_ip/32
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = $server_public_key
Endpoint = $SERVER_IP:$WIREGUARD_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
}

# Add client
add_client() {
    local client_name=$1
    
    if [[ -z "$client_name" ]]; then
        print_error "Client name is required"
        return 1
    fi
    
    # Check if client already exists
    if [[ -f "$CLIENTS_DIR/$client_name.conf" ]]; then
        print_error "Client '$client_name' already exists"
        return 1
    fi
    
    # Create clients directory if it doesn't exist
    mkdir -p "$CLIENTS_DIR"
    
    # Get next available IP
    local next_ip=$(get_next_ip)
    
    # Generate client keys
    local client_private_key=$(wg genkey)
    local client_public_key=$(echo "$client_private_key" | wg pubkey)
    
    # Generate client configuration
    generate_client_config "$client_name" "$next_ip" "$client_private_key" "$client_public_key"
    
    # Add peer to server configuration
    cat >> "$CONFIG_FILE" <<EOF

# Client: $client_name
[Peer]
PublicKey = $client_public_key
AllowedIPs = 10.8.0.$next_ip/32
EOF
    
    # Generate QR code
    qrencode -t png -o "$CLIENTS_DIR/$client_name.png" < "$CLIENTS_DIR/$client_name.conf"
    
    # Update next IP
    update_next_ip $((next_ip + 1))
    
    # Restart WireGuard
    systemctl restart wg-quick@wg0
    
    print_status "Client '$client_name' added successfully"
    print_info "Configuration file: $CLIENTS_DIR/$client_name.conf"
    print_info "QR code: $CLIENTS_DIR/$client_name.png"
    print_info "Client IP: 10.8.0.$next_ip"
    
    # Show QR code in terminal
    echo ""
    echo "QR Code for mobile devices:"
    qrencode -t ansiutf8 < "$CLIENTS_DIR/$client_name.conf"
}

# Remove client
remove_client() {
    local client_name=$1
    
    if [[ -z "$client_name" ]]; then
        print_error "Client name is required"
        return 1
    fi
    
    # Check if client exists
    if [[ ! -f "$CLIENTS_DIR/$client_name.conf" ]]; then
        print_error "Client '$client_name' not found"
        return 1
    fi
    
    # Get client public key
    local client_public_key=$(grep "PublicKey" "$CLIENTS_DIR/$client_name.conf" | cut -d' ' -f3)
    
    # Remove client files
    rm -f "$CLIENTS_DIR/$client_name.conf"
    rm -f "$CLIENTS_DIR/$client_name.png"
    
    # Remove peer from server configuration
    sed -i "/# Client: $client_name/,/^$/d" "$CONFIG_FILE"
    
    # Restart WireGuard
    systemctl restart wg-quick@wg0
    
    print_status "Client '$client_name' removed successfully"
}

# List clients
list_clients() {
    if [[ ! -d "$CLIENTS_DIR" ]]; then
        print_info "No clients found"
        return 0
    fi
    
    local clients=$(ls -1 "$CLIENTS_DIR"/*.conf 2>/dev/null | wc -l)
    
    if [[ $clients -eq 0 ]]; then
        print_info "No clients found"
        return 0
    fi
    
    print_info "Active clients:"
    echo ""
    
    for config in "$CLIENTS_DIR"/*.conf; do
        if [[ -f "$config" ]]; then
            local client_name=$(basename "$config" .conf)
            local client_ip=$(grep "Address" "$config" | cut -d' ' -f3 | cut -d'/' -f1)
            local status="Connected"
            
            # Check if client is currently connected
            if ! wg show "$WG_INTERFACE" peers | grep -q "$(grep "PublicKey" "$config" | cut -d' ' -f3)"; then
                status="Disconnected"
            fi
            
            printf "%-20s %-15s %-15s\n" "$client_name" "$client_ip" "$status"
        fi
    done
}

# Show server status
show_status() {
    print_info "WireGuard VPN Server Status"
    echo ""
    
    # Service status
    if systemctl is-active --quiet wg-quick@wg0; then
        echo -e "Service Status: ${GREEN}Active${NC}"
    else
        echo -e "Service Status: ${RED}Inactive${NC}"
    fi
    
    # Interface status
    if ip link show "$WG_INTERFACE" &>/dev/null; then
        echo -e "Interface Status: ${GREEN}Up${NC}"
    else
        echo -e "Interface Status: ${RED}Down${NC}"
    fi
    
    # Server information
    echo "Server IP: $SERVER_IP"
    echo "Listen Port: $WIREGUARD_PORT"
    echo "Interface: $WG_INTERFACE"
    echo "Network: 10.8.0.0/24"
    echo ""
    
    # Connected peers
    local peers=$(wg show "$WG_INTERFACE" peers 2>/dev/null | wc -l)
    echo "Connected peers: $peers"
    
    if [[ $peers -gt 0 ]]; then
        echo ""
        echo "Peer details:"
        wg show "$WG_INTERFACE"
    fi
    
    # Traffic statistics
    echo ""
    echo "Traffic statistics:"
    wg show "$WG_INTERFACE" transfer 2>/dev/null | while read -r peer rx tx; do
        echo "Peer: $peer"
        echo "  Received: $rx"
        echo "  Sent: $tx"
        echo ""
    done
}

# Show client configuration
show_client_config() {
    local client_name=$1
    
    if [[ -z "$client_name" ]]; then
        print_error "Client name is required"
        return 1
    fi
    
    if [[ ! -f "$CLIENTS_DIR/$client_name.conf" ]]; then
        print_error "Client '$client_name' not found"
        return 1
    fi
    
    print_info "Configuration for client '$client_name':"
    echo ""
    cat "$CLIENTS_DIR/$client_name.conf"
    echo ""
    
    print_info "QR Code:"
    qrencode -t ansiutf8 < "$CLIENTS_DIR/$client_name.conf"
}

# Backup configuration
backup_config() {
    local backup_dir="$INSTALL_DIR/backups"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/wireguard_backup_$timestamp.tar.gz"
    
    mkdir -p "$backup_dir"
    
    tar -czf "$backup_file" -C / etc/wireguard opt/wireguard-server/clients
    
    print_status "Backup created: $backup_file"
}

# Restart services
restart_services() {
    print_status "Restarting WireGuard services..."
    
    systemctl restart wg-quick@wg0
    systemctl restart wireguard-web
    
    print_status "Services restarted successfully"
}

# Show logs
show_logs() {
    local lines=${1:-50}
    
    print_info "WireGuard service logs (last $lines lines):"
    journalctl -u wg-quick@wg0 -n "$lines" --no-pager
    
    echo ""
    print_info "Web interface logs:"
    journalctl -u wireguard-web -n "$lines" --no-pager
}

# Show help
show_help() {
    echo "WireGuard VPN Server Management Script"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  add-client <name>        Add new client"
    echo "  remove-client <name>     Remove client"
    echo "  list-clients             List all clients"
    echo "  show-client <name>       Show client configuration and QR code"
    echo "  status                   Show server status"
    echo "  restart                  Restart WireGuard services"
    echo "  backup                   Create configuration backup"
    echo "  logs [lines]             Show service logs (default: 50 lines)"
    echo "  help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 add-client john"
    echo "  $0 remove-client john"
    echo "  $0 list-clients"
    echo "  $0 show-client john"
    echo "  $0 status"
    echo "  $0 logs 100"
}

# Main function
main() {
    check_root
    
    case "${1:-}" in
        "add-client")
            add_client "${2:-}"
            ;;
        "remove-client")
            remove_client "${2:-}"
            ;;
        "list-clients")
            list_clients
            ;;
        "show-client")
            show_client_config "${2:-}"
            ;;
        "status")
            show_status
            ;;
        "restart")
            restart_services
            ;;
        "backup")
            backup_config
            ;;
        "logs")
            show_logs "${2:-50}"
            ;;
        "help"|"")
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 