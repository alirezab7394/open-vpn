#!/bin/bash

# OpenVPN Server Native Installation with Web Interface
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

log "Starting OpenVPN native setup for IP: $SERVER_IP"

# Update system
log "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install OpenVPN and Easy-RSA
log "Installing OpenVPN and Easy-RSA..."
apt-get install -y openvpn easy-rsa nginx php-fpm php-mysql mysql-server curl wget unzip

# Configure MySQL
log "Configuring MySQL..."
mysql_secure_installation

# Set up Easy-RSA
log "Setting up Easy-RSA..."
make-cadir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa

# Configure Easy-RSA variables
cat > vars << EOF
export KEY_COUNTRY="US"
export KEY_PROVINCE="CA"
export KEY_CITY="SanFrancisco"
export KEY_ORG="OpenVPN"
export KEY_EMAIL="admin@example.com"
export KEY_OU="IT"
export KEY_NAME="server"
export KEY_SIZE=4096
export CA_EXPIRE=3650
export KEY_EXPIRE=3650
EOF

# Build CA
log "Building Certificate Authority..."
source vars
./clean-all
./build-ca --batch
./build-key-server --batch server
./build-dh
openvpn --genkey --secret keys/ta.key

# Create server configuration
log "Creating server configuration..."
cat > /etc/openvpn/server.conf << EOF
port 1194
proto udp
dev tun
ca easy-rsa/keys/ca.crt
cert easy-rsa/keys/server.crt
key easy-rsa/keys/server.key
dh easy-rsa/keys/dh4096.pem
tls-auth easy-rsa/keys/ta.key 0
auth SHA256
cipher AES-256-GCM
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
comp-lzo
persist-key
persist-tun
status openvpn-status.log
log-append /var/log/openvpn.log
verb 3
mute 20
fast-io
sndbuf 0
rcvbuf 0
push "comp-lzo"
EOF

# Enable IP forwarding
log "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# Configure firewall
log "Configuring firewall..."
ufw --force enable
ufw allow OpenSSH
ufw allow 1194/udp
ufw allow 80/tcp
ufw allow 443/tcp

# Add NAT rules
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
iptables -A FORWARD -i tun0 -o eth0 -s 10.8.0.0/24 -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Save iptables rules
iptables-save > /etc/iptables/rules.v4

# Install OpenVPN-Admin web interface
log "Installing OpenVPN-Admin web interface..."
cd /var/www/html
wget https://github.com/Chocobozzz/OpenVPN-Admin/archive/master.zip
unzip master.zip
mv OpenVPN-Admin-master openvpn-admin
chown -R www-data:www-data openvpn-admin

# Configure OpenVPN-Admin
cd openvpn-admin
cp config/config.conf.template config/config.conf

# Update configuration
cat > config/config.conf << EOF
<?php
\$config = array(
    'db' => array(
        'host' => 'localhost',
        'user' => 'openvpn',
        'pass' => 'openvpn123',
        'name' => 'openvpn'
    ),
    'openvpn' => array(
        'path' => '/etc/openvpn/',
        'server' => '/etc/openvpn/server.conf',
        'log' => '/var/log/openvpn.log',
        'status' => '/etc/openvpn/openvpn-status.log'
    ),
    'rsa' => array(
        'path' => '/etc/openvpn/easy-rsa/',
        'vars' => '/etc/openvpn/easy-rsa/vars',
        'keys' => '/etc/openvpn/easy-rsa/keys/'
    ),
    'admin' => array(
        'username' => 'admin',
        'password' => 'admin'
    )
);
?>
EOF

# Create database
log "Creating database..."
mysql -u root -p << EOF
CREATE DATABASE openvpn;
CREATE USER 'openvpn'@'localhost' IDENTIFIED BY 'openvpn123';
GRANT ALL PRIVILEGES ON openvpn.* TO 'openvpn'@'localhost';
FLUSH PRIVILEGES;
EOF

# Import database schema
mysql -u openvpn -popenvpn123 openvpn < sql/schema.sql

# Configure Nginx
log "Configuring Nginx..."
cat > /etc/nginx/sites-available/openvpn-admin << EOF
server {
    listen 80;
    server_name $SERVER_IP;
    root /var/www/html/openvpn-admin;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

ln -s /etc/nginx/sites-available/openvpn-admin /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Start services
log "Starting services..."
systemctl enable openvpn@server
systemctl start openvpn@server
systemctl restart nginx
systemctl restart php7.4-fpm

# Create client management scripts
log "Creating client management scripts..."
cat > /usr/local/bin/ovpn-add-client << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: ovpn-add-client <client-name>"
    exit 1
fi

cd /etc/openvpn/easy-rsa
source vars
./build-key --batch $1

# Create client config
cat > /etc/openvpn/clients/$1.ovpn << EOL
client
dev tun
proto udp
remote SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert $1.crt
key $1.key
tls-auth ta.key 1
cipher AES-256-GCM
auth SHA256
comp-lzo
verb 3
EOL

# Replace SERVER_IP with actual IP
sed -i "s/SERVER_IP/$SERVER_IP/g" /etc/openvpn/clients/$1.ovpn

echo "Client $1 created successfully!"
echo "Configuration file: /etc/openvpn/clients/$1.ovpn"
EOF

chmod +x /usr/local/bin/ovpn-add-client

# Create clients directory
mkdir -p /etc/openvpn/clients

log "Setup complete!"
echo ""
echo "=========================================="
echo "OpenVPN Server Setup Complete!"
echo "=========================================="
echo "Server IP: $SERVER_IP"
echo "OpenVPN Port: 1194 (UDP)"
echo "Web Interface: http://$SERVER_IP"
echo "Default Web Login: admin/admin"
echo ""
echo "Commands:"
echo "  Add client: ovpn-add-client <name>"
echo "  View logs: tail -f /var/log/openvpn.log"
echo "  Restart: systemctl restart openvpn@server"
echo ""
echo "IMPORTANT: Change the web interface password!"
echo "=========================================="