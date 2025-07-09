#!/bin/bash

# OpenVPN Server Setup with Docker and Web Interface
# For Ubuntu VPS

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
fi

# Get server IP
SERVER_IP=$(curl -s ifconfig.me || curl -s ipecho.net/plain || curl -s icanhazip.com)
if [[ -z "$SERVER_IP" ]]; then
    read -p "Enter your server's public IP address: " SERVER_IP
fi

log "Starting OpenVPN Docker setup for IP: $SERVER_IP"

# Update system
log "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install Docker
log "Installing Docker..."
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Install Docker Compose
log "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create OpenVPN directory
mkdir -p /opt/openvpn
cd /opt/openvpn

# Create docker-compose.yml
log "Creating Docker Compose configuration..."
cat > docker-compose.yml << EOF
version: '3.8'

services:
  openvpn:
    image: kylemanna/openvpn:latest
    container_name: openvpn
    cap_add:
      - NET_ADMIN
    ports:
      - "1194:1194/udp"
    restart: unless-stopped
    volumes:
      - ./openvpn-data:/etc/openvpn
    environment:
      - OVPN_SERVER_URL=udp://$SERVER_IP:1194
      - OVPN_NETWORK=10.8.0.0
      - OVPN_SUBNET=255.255.255.0
      - OVPN_PROTO=udp
      - OVPN_CIPHER=AES-256-GCM
      - OVPN_AUTH=SHA256
      - OVPN_COMP_LZ4=yes
      - OVPN_TLS_CIPHER=TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256
    command: ovpn_run

  openvpn-admin:
    image: adamwalach/openvpn-admin:latest
    container_name: openvpn-admin
    ports:
      - "8080:8080"
    depends_on:
      - openvpn
    restart: unless-stopped
    volumes:
      - ./openvpn-data:/etc/openvpn
      - ./openvpn-admin-data:/opt/openvpn-admin
    environment:
      - OPENVPN_ADMIN_USERNAME=admin
      - OPENVPN_ADMIN_PASSWORD=admin
      - OPENVPN_SERVER_URL=$SERVER_IP:1194
      - OPENVPN_AUTH_METHOD=file
    command: /opt/openvpn-admin/openvpn-admin --bind-host=0.0.0.0 --bind-port=8080

volumes:
  openvpn-data:
  openvpn-admin-data:
EOF

# Create optimized OpenVPN configuration
log "Creating optimized OpenVPN configuration..."
mkdir -p openvpn-data
docker-compose run --rm openvpn ovpn_genconfig -u udp://$SERVER_IP:1194 -s 10.8.0.0/24 -p "route 192.168.1.0 255.255.255.0" -e "compress lz4" -e "cipher AES-256-GCM" -e "auth SHA256" -e "tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256" -e "tls-version-min 1.2" -e "fast-io" -e "sndbuf 0" -e "rcvbuf 0"

# Initialize PKI
log "Initializing PKI..."
docker-compose run --rm openvpn ovpn_initpki nopass

# Configure firewall
log "Configuring firewall..."
ufw --force enable
ufw allow OpenSSH
ufw allow 1194/udp
ufw allow 8080/tcp

# Enable IP forwarding
log "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# Start services
log "Starting OpenVPN services..."
docker-compose up -d

# Wait for services to start
log "Waiting for services to initialize..."
sleep 30

# Create systemd service for auto-start
log "Creating systemd service..."
cat > /etc/systemd/system/openvpn-docker.service << EOF
[Unit]
Description=OpenVPN Docker Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/openvpn
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable openvpn-docker.service

# Create helper scripts
log "Creating helper scripts..."
cat > /usr/local/bin/ovpn-add-client << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: ovpn-add-client <client-name>"
    exit 1
fi
cd /opt/openvpn
docker-compose run --rm openvpn easyrsa build-client-full $1 nopass
docker-compose run --rm openvpn ovpn_getclient $1 > $1.ovpn
echo "Client configuration saved to: $1.ovpn"
EOF

cat > /usr/local/bin/ovpn-revoke-client << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: ovpn-revoke-client <client-name>"
    exit 1
fi
cd /opt/openvpn
docker-compose run --rm openvpn easyrsa revoke $1
docker-compose run --rm openvpn easyrsa gen-crl
docker-compose restart openvpn
echo "Client $1 revoked"
EOF

chmod +x /usr/local/bin/ovpn-add-client
chmod +x /usr/local/bin/ovpn-revoke-client

# Create first client
log "Creating first client certificate..."
cd /opt/openvpn
docker-compose run --rm openvpn easyrsa build-client-full client1 nopass
docker-compose run --rm openvpn ovpn_getclient client1 > client1.ovpn

log "Setup complete!"
echo ""
echo "=========================================="
echo "OpenVPN Server Setup Complete!"
echo "=========================================="
echo "Server IP: $SERVER_IP"
echo "OpenVPN Port: 1194 (UDP)"
echo "Web Interface: http://$SERVER_IP:8080"
echo "Default Web Login: admin/admin"
echo ""
echo "Client certificate created: client1.ovpn"
echo ""
echo "Commands:"
echo "  Add client: ovpn-add-client <name>"
echo "  Revoke client: ovpn-revoke-client <name>"
echo "  View logs: docker-compose logs -f"
echo "  Restart: docker-compose restart"
echo ""
echo "IMPORTANT: Change the web interface password!"
echo "==========================================" 