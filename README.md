# Outline VPN Server Setup with Web UI

A complete setup for Outline VPN server on Ubuntu with a modern web-based management interface.

## 🚀 Features

- ✅ **One-click installation** - Automated setup script
- ✅ **Modern Web UI** - Beautiful Bootstrap-based interface
- ✅ **User Management** - Create, delete, and manage VPN users
- ✅ **QR Code Generation** - Easy mobile setup with QR codes
- ✅ **Real-time Monitoring** - Server stats and connection monitoring
- ✅ **SSL/TLS Support** - Secure HTTPS access
- ✅ **Docker-based** - Easy deployment and management
- ✅ **Automatic Backups** - Built-in backup system
- ✅ **API Access** - RESTful API for automation
- ✅ **Responsive Design** - Works on desktop and mobile

## 📋 Requirements

- **Ubuntu 18.04+** server
- **Root access** (sudo privileges)
- **Public IP address**
- **2GB RAM minimum** (recommended 4GB)
- **20GB disk space**
- **Domain name** (optional, for SSL)

## 🏃 Quick Start

### Option 1: Automated Installation (Recommended)

```bash
# Download the repository
git clone https://github.com/yourusername/outline-vpn-server.git
cd outline-vpn-server

# Make installation script executable
chmod +x install.sh

# Run the installer
sudo ./install.sh
```

### Option 2: Manual Installation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Clone and setup
git clone https://github.com/yourusername/outline-vpn-server.git
cd outline-vpn-server
sudo docker-compose up -d
```

## 🌐 Access Your Server

After installation, access your server:

- **Web UI (HTTP)**: `http://your-server-ip:8080`
- **Web UI (HTTPS)**: `https://your-domain.com:8443`
- **API Endpoint**: `http://your-server-ip:8080/api`

**Default Credentials:**

- Username: `admin`
- Password: `[set during installation]`

## 📱 Client Setup

### Mobile Devices

1. Download the Outline app from:
   - [Google Play Store](https://play.google.com/store/apps/details?id=org.outline.android.client)
   - [Apple App Store](https://apps.apple.com/app/outline-app/id1356177741)
2. Scan the QR code from the web UI
3. Connect!

### Desktop/Laptop

1. Download Outline client from [getoutline.org](https://getoutline.org/get-started/)
2. Copy the access key from the web UI
3. Add server and connect

## 🛠️ Management

Use the included management script for easy server management:

```bash
# Start services
sudo ./manage.sh start

# Stop services
sudo ./manage.sh stop

# Restart services
sudo ./manage.sh restart

# Check status
sudo ./manage.sh status

# View logs
sudo ./manage.sh logs

# Create backup
sudo ./manage.sh backup

# Update system
sudo ./manage.sh update
```

## 🔧 Configuration

### Environment Variables

Edit the `.env` file to customize your setup:

```bash
# Server Configuration
PUBLIC_IP=your.server.ip
DOMAIN_NAME=your.domain.com
ADMIN_PASSWORD=your_secure_password

# SSL Configuration
SSL_CERT_PATH=/opt/outline/ssl/server.crt
SSL_KEY_PATH=/opt/outline/ssl/server.key

# Data Directory
DATA_PATH=/opt/outline/data
```

### Firewall Configuration

The installer automatically configures UFW, but you can manually set:

```bash
# Allow SSH
sudo ufw allow ssh

# Allow Web UI
sudo ufw allow 8080/tcp
sudo ufw allow 8443/tcp

# Allow VPN traffic
sudo ufw allow 1024:65535/udp

# Enable firewall
sudo ufw enable
```

## 📊 Monitoring

Access monitoring dashboards:

- **Prometheus**: `http://your-server-ip:9090`
- **Grafana**: `http://your-server-ip:3001`
  - Username: `admin`
  - Password: `[your admin password]`

## 🔒 Security

### Best Practices

1. **Change default passwords** immediately
2. **Use SSL certificates** for production
3. **Enable firewall** (UFW/iptables)
4. **Regular updates** with `./manage.sh update`
5. **Monitor logs** regularly
6. **Create regular backups**

### SSL Certificate Setup

For production, use Let's Encrypt:

```bash
# Install certbot
sudo apt install certbot

# Get certificate
sudo certbot certonly --standalone -d your.domain.com

# Update paths in .env file
SSL_CERT_PATH=/etc/letsencrypt/live/your.domain.com/fullchain.pem
SSL_KEY_PATH=/etc/letsencrypt/live/your.domain.com/privkey.pem

# Restart services
sudo ./manage.sh restart
```

## 📈 API Documentation

The server provides a RESTful API for automation:

### Endpoints

```bash
# Get server stats
GET /api/server/stats

# List users
GET /api/users

# Create user
POST /api/users
{
  "name": "John Doe",
  "dataLimit": 100
}

# Get user details
GET /api/users/{id}

# Delete user
DELETE /api/users/{id}

# Update user
PUT /api/users/{id}
{
  "name": "Jane Doe",
  "dataLimit": 200
}
```

## 🔍 Troubleshooting

### Common Issues

**Port Conflicts**

```bash
# Check port usage
sudo netstat -tlnp | grep :8080
sudo netstat -tlnp | grep :8443
```

**Docker Issues**

```bash
# Check Docker status
sudo systemctl status docker

# Restart Docker
sudo systemctl restart docker

# View container logs
sudo docker-compose logs -f
```

**SSL Certificate Issues**

```bash
# Check certificate validity
openssl x509 -in /opt/outline/ssl/server.crt -text -noout

# Regenerate self-signed certificate
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/outline/ssl/server.key \
  -out /opt/outline/ssl/server.crt
```

**Connection Issues**

```bash
# Check firewall status
sudo ufw status

# Test connectivity
telnet your-server-ip 8080
```

## 🧪 Development

For development and testing:

```bash
# Install dependencies
cd api && npm install

# Run in development mode
npm run dev

# Run tests
npm test
```

## 🤝 Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Outline VPN](https://getoutline.org/) - The underlying VPN technology
- [Jigsaw](https://jigsaw.google.com/) - For creating Outline
- [Bootstrap](https://getbootstrap.com/) - For the beautiful UI
- [Docker](https://www.docker.com/) - For containerization

## 📞 Support

If you need help:

1. Check the [troubleshooting section](#🔍-troubleshooting)
2. Search existing [GitHub issues](https://github.com/yourusername/outline-vpn-server/issues)
3. Create a new issue with detailed information
4. Join our [Discord community](https://discord.gg/your-invite)

---

⭐ **Star this repository if you find it useful!**
