#!/bin/bash

# VPN Server Management Script
# Supports both Outline VPN and OpenVPN
# Usage: ./manage.sh {start|stop|restart|status|logs|backup|update}

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect VPN type based on available configurations
if [[ -f "$SCRIPT_DIR/outline/docker-compose.yml" ]] && [[ -f "$SCRIPT_DIR/openvpn/docker-compose.yml" ]]; then
    echo "Multiple VPN configurations found. Please specify which one to manage:"
    echo "1) Outline VPN"
    echo "2) OpenVPN"
    read -p "Enter your choice (1 or 2): " VPN_CHOICE
    
    case $VPN_CHOICE in
        1)
            VPN_TYPE="outline"
            VPN_NAME="Outline VPN"
            ;;
        2)
            VPN_TYPE="openvpn"
            VPN_NAME="OpenVPN"
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
elif [[ -f "$SCRIPT_DIR/outline/docker-compose.yml" ]]; then
    VPN_TYPE="outline"
    VPN_NAME="Outline VPN"
elif [[ -f "$SCRIPT_DIR/openvpn/docker-compose.yml" ]]; then
    VPN_TYPE="openvpn"
    VPN_NAME="OpenVPN"
else
    echo "No VPN configuration found. Please run install.sh first."
    exit 1
fi

COMPOSE_FILE="$SCRIPT_DIR/$VPN_TYPE/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/$VPN_TYPE/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

check_requirements() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed"
        exit 1
    fi
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
}

start_services() {
    print_header "Starting $VPN_NAME Server"
    
    # Check if services are already running
    if docker-compose -f "$COMPOSE_FILE" ps | grep -q "Up"; then
        print_warning "Some services are already running"
    fi
    
    # Start services
    docker-compose -f "$COMPOSE_FILE" up -d
    
    # Wait for services to be ready
    print_status "Waiting for services to start..."
    sleep 10
    
    # Check service status
    docker-compose -f "$COMPOSE_FILE" ps
    
    print_status "$VPN_NAME services started successfully!"
    print_status "Web UI: http://localhost:8080"
    print_status "Web UI (SSL): https://localhost:8443"
    
    if [[ "$VPN_TYPE" == "openvpn" ]]; then
        print_status "OpenVPN Access Server: https://localhost:943"
        print_status "OpenVPN Port: 1194/udp"
    fi
}

stop_services() {
    print_header "Stopping $VPN_NAME Server"
    
    docker-compose -f "$COMPOSE_FILE" down
    
    print_status "$VPN_NAME services stopped successfully!"
}

restart_services() {
    print_header "Restarting $VPN_NAME Server"
    
    stop_services
    sleep 5
    start_services
}

show_status() {
    print_header "Service Status"
    
    docker-compose -f "$COMPOSE_FILE" ps
    
    print_header "Docker Stats"
    docker stats --no-stream $(docker-compose -f "$COMPOSE_FILE" ps -q)
}

show_logs() {
    print_header "Service Logs"
    
    if [ -z "$2" ]; then
        docker-compose -f "$COMPOSE_FILE" logs -f
    else
        docker-compose -f "$COMPOSE_FILE" logs -f "$2"
    fi
}

backup_data() {
    print_header "Backing Up $VPN_NAME Data"
    
    BACKUP_DIR="$SCRIPT_DIR/backups"
    BACKUP_FILE="$BACKUP_DIR/${VPN_TYPE}-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    mkdir -p "$BACKUP_DIR"
    
    print_status "Creating backup: $BACKUP_FILE"
    
    # Create backup based on VPN type
    if [[ "$VPN_TYPE" == "outline" ]]; then
        tar -czf "$BACKUP_FILE" \
            --exclude='backups' \
            --exclude='node_modules' \
            --exclude='*.log' \
            -C "$SCRIPT_DIR" \
            outline/ \
            install.sh \
            manage.sh
    elif [[ "$VPN_TYPE" == "openvpn" ]]; then
        tar -czf "$BACKUP_FILE" \
            --exclude='backups' \
            --exclude='node_modules' \
            --exclude='*.log' \
            -C "$SCRIPT_DIR" \
            openvpn/ \
            install.sh \
            manage.sh
    fi
    
    print_status "Backup created successfully: $BACKUP_FILE"
}

update_system() {
    print_header "Updating $VPN_NAME Server"
    
    # Pull latest images
    print_status "Pulling latest Docker images..."
    docker-compose -f "$COMPOSE_FILE" pull
    
    # Restart services with new images
    print_status "Restarting services..."
    docker-compose -f "$COMPOSE_FILE" up -d
    
    # Clean up old images
    print_status "Cleaning up old images..."
    docker image prune -f
    
    print_status "$VPN_NAME update completed successfully!"
}

show_help() {
    echo "Outline VPN Server Management Script"
    echo ""
    echo "Usage: $0 {start|stop|restart|status|logs|backup|update|help}"
    echo ""
    echo "Commands:"
    echo "  start    - Start all services"
    echo "  stop     - Stop all services"
    echo "  restart  - Restart all services"
    echo "  status   - Show service status"
    echo "  logs     - Show service logs (optional: specify service name)"
    echo "  backup   - Create backup of data and configuration"
    echo "  update   - Update to latest version"
    echo "  help     - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 start"
    echo "  $0 logs outline-server"
    echo "  $0 backup"
}

# Main script logic
case "$1" in
    start)
        check_requirements
        start_services
        ;;
    stop)
        check_requirements
        stop_services
        ;;
    restart)
        check_requirements
        restart_services
        ;;
    status)
        check_requirements
        show_status
        ;;
    logs)
        check_requirements
        show_logs "$@"
        ;;
    backup)
        check_requirements
        backup_data
        ;;
    update)
        check_requirements
        update_system
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac 