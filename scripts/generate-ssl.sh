#!/bin/bash

# SSL Certificate Generator for OpenVPN-UI
# This script generates self-signed SSL certificates for the nginx reverse proxy

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== OpenVPN-UI SSL Certificate Generator ===${NC}"

# Create SSL directory
SSL_DIR="./ssl"
mkdir -p "$SSL_DIR"

# Certificate details
COUNTRY="US"
STATE="State"
CITY="City"
ORGANIZATION="OpenVPN Server"
ORGANIZATIONAL_UNIT="IT Department"
COMMON_NAME="openvpn-server.local"
EMAIL="admin@openvpn-server.local"

# Get server IP or hostname
echo -e "${YELLOW}Enter your server IP or hostname (default: localhost):${NC}"
read -r SERVER_NAME
SERVER_NAME=${SERVER_NAME:-localhost}

# Generate private key
echo -e "${YELLOW}Generating private key...${NC}"
openssl genrsa -out "$SSL_DIR/server.key" 2048

# Generate certificate signing request
echo -e "${YELLOW}Generating certificate signing request...${NC}"
openssl req -new -key "$SSL_DIR/server.key" -out "$SSL_DIR/server.csr" -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=$SERVER_NAME/emailAddress=$EMAIL"

# Generate self-signed certificate
echo -e "${YELLOW}Generating self-signed certificate...${NC}"
openssl x509 -req -days 365 -in "$SSL_DIR/server.csr" -signkey "$SSL_DIR/server.key" -out "$SSL_DIR/server.crt" -extensions v3_req -extfile <(echo "
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $SERVER_NAME
DNS.2 = localhost
DNS.3 = openvpn-server.local
IP.1 = 127.0.0.1
")

# Set appropriate permissions
chmod 600 "$SSL_DIR/server.key"
chmod 644 "$SSL_DIR/server.crt"

# Clean up CSR file
rm -f "$SSL_DIR/server.csr"

echo -e "${GREEN}=== SSL certificates generated successfully! ===${NC}"
echo -e "${GREEN}Certificate: $SSL_DIR/server.crt${NC}"
echo -e "${GREEN}Private Key: $SSL_DIR/server.key${NC}"
echo -e "${YELLOW}Valid for: 365 days${NC}"
echo -e "${YELLOW}Server Name: $SERVER_NAME${NC}"
echo ""
echo -e "${GREEN}You can now restart the Docker containers:${NC}"
echo -e "${GREEN}docker-compose down && docker-compose up -d${NC}" 