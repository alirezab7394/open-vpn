#!/bin/bash

# OpenVPN Backup Script
# This script creates encrypted backups of OpenVPN configuration and certificates

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
BACKUP_BASE_DIR="/backup/openvpn"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_BASE_DIR}/${DATE}"
RETENTION_DAYS=30

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --full         Create full backup (default)"
    echo "  -c, --config-only  Backup only configuration files"
    echo "  -r, --restore      Restore from backup"
    echo "  -l, --list         List available backups"
    echo "  -d, --delete       Delete old backups"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -f              # Create full backup"
    echo "  $0 -c              # Backup only configs"
    echo "  $0 -r backup_name  # Restore from backup"
    echo "  $0 -l              # List backups"
    echo "  $0 -d              # Delete old backups"
}

# Function to create backup directories
create_backup_dirs() {
    print_info "Creating backup directories..."
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/pki"
    mkdir -p "$BACKUP_DIR/configs"
    mkdir -p "$BACKUP_DIR/clients"
    mkdir -p "$BACKUP_DIR/ssl"
    mkdir -p "$BACKUP_DIR/db"
}

# Function to backup PKI (certificates)
backup_pki() {
    print_info "Backing up PKI certificates..."
    
    if [[ -d "${OPENVPN_DIR}/data/pki" ]]; then
        cp -r "${OPENVPN_DIR}/data/pki"/* "${BACKUP_DIR}/pki/"
        print_success "PKI certificates backed up"
    else
        print_warning "PKI directory not found"
    fi
}

# Function to backup configuration files
backup_configs() {
    print_info "Backing up configuration files..."
    
    if [[ -d "${OPENVPN_DIR}/configs" ]]; then
        cp -r "${OPENVPN_DIR}/configs"/* "${BACKUP_DIR}/configs/"
        print_success "Configuration files backed up"
    else
        print_warning "Configs directory not found"
    fi
    
    # Backup docker-compose.yml
    if [[ -f "docker-compose.yml" ]]; then
        cp docker-compose.yml "${BACKUP_DIR}/"
        print_success "Docker Compose configuration backed up"
    fi
}

# Function to backup client configurations
backup_clients() {
    print_info "Backing up client configurations..."
    
    if [[ -d "${OPENVPN_DIR}/data/clients" ]]; then
        cp -r "${OPENVPN_DIR}/data/clients"/* "${BACKUP_DIR}/clients/" 2>/dev/null || true
        print_success "Client configurations backed up"
    else
        print_warning "Client directory not found"
    fi
}

# Function to backup SSL certificates
backup_ssl() {
    print_info "Backing up SSL certificates..."
    
    if [[ -d "${OPENVPN_DIR}/ssl" ]]; then
        cp -r "${OPENVPN_DIR}/ssl"/* "${BACKUP_DIR}/ssl/" 2>/dev/null || true
        print_success "SSL certificates backed up"
    else
        print_warning "SSL directory not found"
    fi
}

# Function to backup database
backup_database() {
    print_info "Backing up database..."
    
    if [[ -d "${OPENVPN_DIR}/data/db" ]]; then
        cp -r "${OPENVPN_DIR}/data/db"/* "${BACKUP_DIR}/db/" 2>/dev/null || true
        print_success "Database backed up"
    else
        print_warning "Database directory not found"
    fi
}

# Function to create backup metadata
create_backup_metadata() {
    print_info "Creating backup metadata..."
    
    cat > "${BACKUP_DIR}/backup_info.txt" << EOF
OpenVPN Server Backup Information
=================================

Backup Date: $(date)
Backup Type: $1
Server IP: $(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
Hostname: $(hostname)
OS: $(lsb_release -d | cut -f2 2>/dev/null || echo "Unknown")
Docker Version: $(docker --version 2>/dev/null || echo "Unknown")

Backup Contents:
- PKI Certificates: $(ls -la "${BACKUP_DIR}/pki" 2>/dev/null | wc -l || echo "0") files
- Configuration Files: $(ls -la "${BACKUP_DIR}/configs" 2>/dev/null | wc -l || echo "0") files
- Client Configurations: $(ls -la "${BACKUP_DIR}/clients" 2>/dev/null | wc -l || echo "0") files
- SSL Certificates: $(ls -la "${BACKUP_DIR}/ssl" 2>/dev/null | wc -l || echo "0") files
- Database Files: $(ls -la "${BACKUP_DIR}/db" 2>/dev/null | wc -l || echo "0") files

OpenVPN Status:
$(docker ps --filter "name=openvpn" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not running")

Backup Size: $(du -sh "${BACKUP_DIR}" | cut -f1)
EOF

    print_success "Backup metadata created"
}

# Function to compress and encrypt backup
compress_and_encrypt() {
    print_info "Compressing and encrypting backup..."
    
    # Create compressed archive
    cd "$BACKUP_BASE_DIR"
    tar -czf "${DATE}.tar.gz" "$DATE"
    
    # Encrypt archive
    if command -v gpg >/dev/null 2>&1; then
        read -s -p "Enter encryption password: " PASSWORD
        echo
        echo "$PASSWORD" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 "${DATE}.tar.gz"
        
        # Remove unencrypted files
        rm -f "${DATE}.tar.gz"
        rm -rf "$DATE"
        
        print_success "Backup compressed and encrypted: ${DATE}.tar.gz.gpg"
    else
        print_warning "GPG not available, backup not encrypted"
        print_success "Backup compressed: ${DATE}.tar.gz"
    fi
}

# Function to create full backup
create_full_backup() {
    print_info "Creating full backup..."
    
    create_backup_dirs
    backup_pki
    backup_configs
    backup_clients
    backup_ssl
    backup_database
    create_backup_metadata "Full"
    compress_and_encrypt
    
    print_success "Full backup completed: ${BACKUP_BASE_DIR}/${DATE}.tar.gz"
}

# Function to create config-only backup
create_config_backup() {
    print_info "Creating configuration backup..."
    
    create_backup_dirs
    backup_configs
    create_backup_metadata "Configuration Only"
    compress_and_encrypt
    
    print_success "Configuration backup completed: ${BACKUP_BASE_DIR}/${DATE}.tar.gz"
}

# Function to list available backups
list_backups() {
    print_info "Available backups:"
    
    if [[ -d "$BACKUP_BASE_DIR" ]]; then
        echo "Backup Location: $BACKUP_BASE_DIR"
        echo ""
        echo "Available backups:"
        ls -la "$BACKUP_BASE_DIR"/*.tar.gz* 2>/dev/null | awk '{print $9 " (" $5 " bytes) " $6 " " $7 " " $8}' || echo "No backups found"
    else
        print_warning "Backup directory does not exist: $BACKUP_BASE_DIR"
    fi
}

# Function to delete old backups
delete_old_backups() {
    print_info "Deleting backups older than $RETENTION_DAYS days..."
    
    if [[ -d "$BACKUP_BASE_DIR" ]]; then
        DELETED_COUNT=$(find "$BACKUP_BASE_DIR" -name "*.tar.gz*" -mtime +$RETENTION_DAYS -delete -print | wc -l)
        
        if [[ $DELETED_COUNT -gt 0 ]]; then
            print_success "Deleted $DELETED_COUNT old backup(s)"
        else
            print_info "No old backups to delete"
        fi
    else
        print_warning "Backup directory does not exist: $BACKUP_BASE_DIR"
    fi
}

# Function to restore from backup
restore_backup() {
    local BACKUP_NAME="$1"
    
    if [[ -z "$BACKUP_NAME" ]]; then
        print_error "Backup name required for restore"
        list_backups
        exit 1
    fi
    
    print_info "Restoring from backup: $BACKUP_NAME"
    
    # Check if backup exists
    if [[ ! -f "${BACKUP_BASE_DIR}/${BACKUP_NAME}" ]]; then
        print_error "Backup not found: ${BACKUP_BASE_DIR}/${BACKUP_NAME}"
        exit 1
    fi
    
    # Confirm restore
    print_warning "This will overwrite current OpenVPN configuration!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Restore cancelled"
        exit 0
    fi
    
    # Stop OpenVPN services
    print_info "Stopping OpenVPN services..."
    docker-compose down 2>/dev/null || true
    
    # Create restore directory
    RESTORE_DIR="/tmp/openvpn-restore-$$"
    mkdir -p "$RESTORE_DIR"
    
    # Decrypt and extract backup
    cd "$RESTORE_DIR"
    
    if [[ "$BACKUP_NAME" == *.gpg ]]; then
        # Encrypted backup
        read -s -p "Enter decryption password: " PASSWORD
        echo
        echo "$PASSWORD" | gpg --batch --yes --passphrase-fd 0 --decrypt "${BACKUP_BASE_DIR}/${BACKUP_NAME}" | tar -xz
    else
        # Unencrypted backup
        tar -xzf "${BACKUP_BASE_DIR}/${BACKUP_NAME}"
    fi
    
    # Find extracted directory
    EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "20*" | head -1)
    
    if [[ -z "$EXTRACTED_DIR" ]]; then
        print_error "Could not find extracted backup directory"
        exit 1
    fi
    
    # Restore files
    print_info "Restoring files..."
    
    # Backup current configuration
    if [[ -d "$OPENVPN_DIR" ]]; then
        cp -r "$OPENVPN_DIR" "${OPENVPN_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Current configuration backed up"
    fi
    
    # Restore PKI
    if [[ -d "${EXTRACTED_DIR}/pki" ]]; then
        mkdir -p "${OPENVPN_DIR}/data/pki"
        cp -r "${EXTRACTED_DIR}/pki"/* "${OPENVPN_DIR}/data/pki/"
        print_success "PKI restored"
    fi
    
    # Restore configurations
    if [[ -d "${EXTRACTED_DIR}/configs" ]]; then
        mkdir -p "${OPENVPN_DIR}/configs"
        cp -r "${EXTRACTED_DIR}/configs"/* "${OPENVPN_DIR}/configs/"
        print_success "Configurations restored"
    fi
    
    # Restore clients
    if [[ -d "${EXTRACTED_DIR}/clients" ]]; then
        mkdir -p "${OPENVPN_DIR}/data/clients"
        cp -r "${EXTRACTED_DIR}/clients"/* "${OPENVPN_DIR}/data/clients/"
        print_success "Client configurations restored"
    fi
    
    # Restore SSL
    if [[ -d "${EXTRACTED_DIR}/ssl" ]]; then
        mkdir -p "${OPENVPN_DIR}/ssl"
        cp -r "${EXTRACTED_DIR}/ssl"/* "${OPENVPN_DIR}/ssl/"
        print_success "SSL certificates restored"
    fi
    
    # Restore database
    if [[ -d "${EXTRACTED_DIR}/db" ]]; then
        mkdir -p "${OPENVPN_DIR}/data/db"
        cp -r "${EXTRACTED_DIR}/db"/* "${OPENVPN_DIR}/data/db/"
        print_success "Database restored"
    fi
    
    # Restore docker-compose.yml
    if [[ -f "${EXTRACTED_DIR}/docker-compose.yml" ]]; then
        cp "${EXTRACTED_DIR}/docker-compose.yml" ./
        print_success "Docker Compose configuration restored"
    fi
    
    # Set proper permissions
    chmod -R 600 "${OPENVPN_DIR}/data/pki/private"
    chmod -R 644 "${OPENVPN_DIR}/data/pki/issued"
    chmod -R 644 "${OPENVPN_DIR}/data/pki"/*.crt
    
    # Cleanup
    rm -rf "$RESTORE_DIR"
    
    # Start services
    print_info "Starting OpenVPN services..."
    docker-compose up -d
    
    print_success "Restore completed successfully!"
    print_warning "Please verify the restoration by checking the dashboard and testing connections"
}

# Function to setup automated backups
setup_automated_backup() {
    print_info "Setting up automated backup..."
    
    # Create cron job for daily backups
    CRON_JOB="0 2 * * * /opt/openvpn-server/scripts/backup.sh -f >/dev/null 2>&1"
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    
    print_success "Automated backup scheduled (daily at 2 AM)"
    print_info "To view cron jobs: crontab -l"
}

# Main function
main() {
    # Create backup base directory
    mkdir -p "$BACKUP_BASE_DIR"
    
    # Parse command line arguments
    if [[ $# -eq 0 ]]; then
        create_full_backup
        exit 0
    fi
    
    case "$1" in
        -f|--full)
            create_full_backup
            ;;
        -c|--config-only)
            create_config_backup
            ;;
        -r|--restore)
            restore_backup "$2"
            ;;
        -l|--list)
            list_backups
            ;;
        -d|--delete)
            delete_old_backups
            ;;
        -a|--automated)
            setup_automated_backup
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