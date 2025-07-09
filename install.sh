#!/bin/bash

# VPN Server Installation Script
# Supports both Outline VPN and OpenVPN
# For Ubuntu 18.04+

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored output
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

print_choice() {
    echo -e "${PURPLE}$1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# VPN Type Selection
print_header "VPN Server Setup"
echo ""
print_status "Choose your VPN solution:"
echo ""
print_choice "1) Outline VPN (Recommended)"
echo "   - Modern, fast, and censorship-resistant"
echo "   - Uses Shadowsocks protocol"
echo "   - Great for restrictive networks"
echo "   - Easy to manage"
echo ""
print_choice "2) OpenVPN"
echo "   - Traditional, mature, and stable"
echo "   - Highly configurable"
echo "   - Certificate-based authentication"
echo "   - Enterprise features"
echo ""
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
        print_error "Invalid choice. Please run the script again."
        exit 1
        ;;
esac

# Get server information
print_header "$VPN_NAME Server Setup"
echo ""
print_status "Gathering server information..."

# Get public IP
PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "127.0.0.1")
print_status "Detected public IP: $PUBLIC_IP"

# Get server hostname
SERVER_HOSTNAME=$(hostname -f)
print_status "Server hostname: $SERVER_HOSTNAME"

# Ask for domain name (optional)
echo ""
read -p "Enter domain name (optional, press Enter to use IP): " DOMAIN_NAME
if [[ -z "$DOMAIN_NAME" ]]; then
    DOMAIN_NAME=$PUBLIC_IP
fi

# Ask for admin password
echo ""
read -s -p "Enter admin password for web UI: " ADMIN_PASSWORD
echo ""
read -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
echo ""

if [[ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]]; then
    print_error "Passwords do not match!"
    exit 1
fi

# Update system
print_header "Updating System"
apt update && apt upgrade -y

# Install required packages
print_status "Installing required packages..."
apt install -y curl wget git ufw fail2ban htop

# Install Docker
print_header "Installing Docker"
if ! command -v docker &> /dev/null; then
    print_status "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker $USER
    systemctl enable docker
    systemctl start docker
    rm get-docker.sh
else
    print_status "Docker is already installed"
fi

# Install Docker Compose
print_header "Installing Docker Compose"
if ! command -v docker-compose &> /dev/null; then
    print_status "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
else
    print_status "Docker Compose is already installed"
fi

# Configure firewall
print_header "Configuring Firewall"
print_status "Setting up UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 8080/tcp  # Web UI
ufw allow 8443/tcp  # Web UI SSL
ufw allow 1024:65535/udp  # Outline VPN ports
ufw --force enable

# Create directories
print_status "Creating directories..."
mkdir -p /opt/outline
mkdir -p /opt/outline/data
mkdir -p /opt/outline/ssl
mkdir -p /opt/outline/ui

# Generate SSL certificate (self-signed)
print_header "Generating SSL Certificate"
print_status "Creating self-signed SSL certificate..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /opt/outline/ssl/server.key \
    -out /opt/outline/ssl/server.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN_NAME"

# Set permissions
chown -R root:root /opt/outline
chmod -R 755 /opt/outline
chmod 600 /opt/outline/ssl/server.key

# Create environment file
print_status "Creating environment configuration..."
cat > /opt/outline/.env << EOF
# Outline VPN Server Configuration
PUBLIC_IP=$PUBLIC_IP
DOMAIN_NAME=$DOMAIN_NAME
ADMIN_PASSWORD=$ADMIN_PASSWORD
SSL_CERT_PATH=/opt/outline/ssl/server.crt
SSL_KEY_PATH=/opt/outline/ssl/server.key
DATA_PATH=/opt/outline/data
EOF

# Copy project files to /opt/outline
print_status "Copying project files..."
cp ${VPN_TYPE}/docker-compose.yml /opt/outline/
cp -r ${VPN_TYPE}/ui/* /opt/outline/ui/ 2>/dev/null || true
cp -r ${VPN_TYPE}/api/* /opt/outline/api/ 2>/dev/null || true
cp -r ${VPN_TYPE}/configs/* /opt/outline/configs/ 2>/dev/null || true

# Copy nginx configuration
if [[ -f "${VPN_TYPE}/nginx.conf" ]]; then
    cp ${VPN_TYPE}/nginx.conf /opt/outline/
else
    # Create basic nginx config for OpenVPN
    cat > /opt/outline/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }
    
    server {
        listen 443 ssl;
        server_name _;
        
        ssl_certificate /etc/nginx/ssl/server.crt;
        ssl_certificate_key /etc/nginx/ssl/server.key;
        
        root /usr/share/nginx/html;
        index index.html;
        
        location / {
            try_files $uri $uri/ /index.html;
        }
        
        location /api/ {
            proxy_pass http://openvpn-api:3000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF
fi

# Create additional directories for OpenVPN if needed
if [[ "$VPN_TYPE" == "openvpn" ]]; then
    mkdir -p /opt/outline/data/openvpn
    mkdir -p /opt/outline/data/ca
    mkdir -p /opt/outline/scripts
    
    # Create OpenVPN initialization script
    cat > /opt/outline/scripts/init-openvpn.sh << 'EOF'
#!/bin/bash
# Initialize OpenVPN server
cd /etc/openvpn
if [ ! -f "server.conf" ]; then
    echo "Initializing OpenVPN server..."
    # Basic OpenVPN server configuration will be created here
fi
EOF
    chmod +x /opt/outline/scripts/init-openvpn.sh
fi

# Start services
print_header "Starting Services"
cd /opt/outline
docker-compose up -d

# Wait for services to start
print_status "Waiting for services to start..."
sleep 10

# Show completion message
print_header "Installation Complete!"
echo ""
print_status "$VPN_NAME Server is now running!"
echo ""
echo "🌐 Web UI Access:"
echo "   HTTP:  http://$PUBLIC_IP:8080"
echo "   HTTPS: https://$DOMAIN_NAME:8443"
echo ""
echo "🔐 Admin Credentials:"
echo "   Username: admin"
echo "   Password: $ADMIN_PASSWORD"
echo ""

if [[ "$VPN_TYPE" == "outline" ]]; then
    echo "📱 Client Setup (Outline VPN):"
    echo "   1. Download Outline app from getoutline.org"
    echo "   2. Use the web UI to create access keys"
    echo "   3. Share QR codes with clients"
    echo ""
elif [[ "$VPN_TYPE" == "openvpn" ]]; then
    echo "📱 Client Setup (OpenVPN):"
    echo "   1. Download OpenVPN client from openvpn.net"
    echo "   2. Use the web UI to create client certificates"
    echo "   3. Download .ovpn files or scan QR codes"
    echo "   4. Import configurations into OpenVPN client"
    echo ""
    echo "🔧 OpenVPN Specific:"
    echo "   Server Port: 1194/udp"
    echo "   Management UI: Features certificate management"
    echo "   Access Server: Alternative UI available at :943"
    echo ""
fi

echo "📋 Management Commands:"
echo "   Status:  sudo docker-compose -f /opt/outline/docker-compose.yml ps"
echo "   Logs:    sudo docker-compose -f /opt/outline/docker-compose.yml logs -f"
echo "   Restart: sudo docker-compose -f /opt/outline/docker-compose.yml restart"
echo "   Stop:    sudo docker-compose -f /opt/outline/docker-compose.yml down"
echo ""
echo "🔥 Firewall Status:"
ufw status
echo ""
print_warning "Please save your admin password securely!"
print_warning "Consider setting up a proper SSL certificate for production use."
echo ""
print_status "Installation completed successfully!"
echo ""
if [[ "$VPN_TYPE" == "outline" ]]; then
    print_status "Outline VPN is great for bypassing censorship and works well in restrictive networks."
elif [[ "$VPN_TYPE" == "openvpn" ]]; then
    print_status "OpenVPN provides enterprise-grade features and extensive configuration options."
fi 