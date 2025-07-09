# WireGuard VPN Server Setup

A complete WireGuard VPN server solution for Ubuntu with a modern web interface for easy management.

## Features

- **🚀 Easy Installation**: One-command setup script
- **🌐 Web Interface**: Modern, responsive web UI for managing clients
- **📱 QR Code Generation**: Instant QR codes for mobile device setup
- **🔐 Secure Authentication**: JWT-based authentication with bcrypt password hashing
- **📊 Real-time Monitoring**: Live server status and client connection monitoring
- **🐳 Docker Support**: Containerized deployment option
- **📈 Monitoring**: Prometheus and Grafana integration
- **🔄 Auto-restart**: Systemd service integration
- **📝 Comprehensive Logging**: Detailed logs for troubleshooting

## Quick Start

### Prerequisites

- Ubuntu 20.04 or later
- Root access or sudo privileges
- Internet connection
- Open ports: 51820 (WireGuard), 8080 (Web Interface)

### Installation

1. **Clone the repository**:

   ```bash
   git clone https://github.com/alirezab7394/open-vpn.git
   cd wireguard-server-setup
   ```

2. **Run the installation script**:

   ```bash
   sudo chmod +x install.sh
   sudo ./install.sh
   ```

3. **Access the web interface**:
   Open your browser and navigate to: `http://YOUR_SERVER_IP:8080`

   **Default credentials:**

   - Username: `admin`
   - Password: `admin`

## Web Interface

The web interface provides:

### Dashboard

- **Server Status**: Real-time server status monitoring
- **Connected Clients**: Number of active connections
- **Server Uptime**: System uptime information
- **Network Information**: VPN network details

### Client Management

- **Add Clients**: Create new VPN client configurations
- **Remove Clients**: Delete existing clients
- **View Configurations**: Display client config files and QR codes
- **Download Configs**: Download client configuration files

### Server Control

- **Restart Server**: Restart the WireGuard service
- **View Logs**: Access system and WireGuard logs
- **Server Information**: Display server configuration details

## Management Commands

Use the `wg-manage` command for CLI management:

```bash
# Add a new client
sudo wg-manage add-client john

# Remove a client
sudo wg-manage remove-client john

# List all clients
sudo wg-manage list-clients

# Show client configuration
sudo wg-manage show-client john

# Show server status
sudo wg-manage status

# Restart services
sudo wg-manage restart

# Create backup
sudo wg-manage backup

# View logs
sudo wg-manage logs
```

## Docker Deployment

### Using Docker Compose

1. **Navigate to the project directory**:

   ```bash
   cd wireguard-server-setup
   ```

2. **Build and start services**:

   ```bash
   docker-compose up -d
   ```

3. **Access services**:
   - Web Interface: `http://localhost:8080`
   - Prometheus: `http://localhost:9090`
   - Grafana: `http://localhost:3000`

### Docker Services

- **wireguard**: WireGuard VPN server
- **wireguard-web**: Web interface
- **nginx**: Reverse proxy (optional)
- **prometheus**: Metrics collection
- **grafana**: Monitoring dashboard
- **redis**: Session storage
- **node-exporter**: System metrics

## Configuration

### Server Configuration

Main configuration file: `/etc/wireguard/wg0.conf`

```ini
[Interface]
PrivateKey = [SERVER_PRIVATE_KEY]
Address = 10.8.0.1/24
ListenPort = 51820
SaveConfig = true

# NAT rules for client traffic
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
# Client configurations will be added here
```

### Environment Variables

Web interface environment variables in `/opt/wireguard-server/config.env`:

```bash
SERVER_IP=YOUR_SERVER_IP
PRIVATE_KEY=YOUR_SERVER_PRIVATE_KEY
WIREGUARD_PORT=51820
WEB_PORT=8080
WG_INTERFACE=wg0
INSTALL_DIR=/opt/wireguard-server
CONFIG_DIR=/etc/wireguard
NEXT_IP=2
```

### Firewall Configuration

The installation script automatically configures UFW:

```bash
# Allow SSH
sudo ufw allow ssh

# Allow WireGuard
sudo ufw allow 51820/udp

# Allow web interface
sudo ufw allow 8080/tcp

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

## Client Setup

### Desktop Clients

1. **Download WireGuard client**:

   - Windows: https://www.wireguard.com/install/
   - macOS: https://www.wireguard.com/install/
   - Linux: `sudo apt install wireguard`

2. **Import configuration**:
   - Download the `.conf` file from the web interface
   - Import into WireGuard client

### Mobile Clients

1. **Download WireGuard app**:

   - iOS: App Store
   - Android: Google Play Store

2. **Scan QR code**:
   - Open the app and scan the QR code from the web interface

## Monitoring

### Prometheus Metrics

Access Prometheus at `http://YOUR_SERVER_IP:9090` to view:

- WireGuard connection metrics
- System resource usage
- Network traffic statistics
- Service health status

### Grafana Dashboard

Access Grafana at `http://YOUR_SERVER_IP:3000`:

- **Default credentials**: admin/admin
- Pre-configured dashboards for WireGuard monitoring
- Real-time visualizations of VPN metrics

## Security

### Best Practices

1. **Change default passwords**:

   ```bash
   # Generate new JWT secret
   openssl rand -hex 32

   # Update admin password
   # Edit /opt/wireguard-server/web/server.js
   ```

2. **Enable HTTPS**:

   - Use Let's Encrypt certificates
   - Configure nginx reverse proxy
   - Update firewall rules

3. **Regular updates**:

   ```bash
   sudo apt update && sudo apt upgrade
   ```

4. **Monitor logs**:
   ```bash
   sudo journalctl -u wg-quick@wg0 -f
   sudo journalctl -u wireguard-web -f
   ```

## Troubleshooting

### Common Issues

1. **WireGuard service not starting**:

   ```bash
   sudo systemctl status wg-quick@wg0
   sudo journalctl -u wg-quick@wg0
   ```

2. **Web interface not accessible**:

   ```bash
   sudo systemctl status wireguard-web
   sudo netstat -tlnp | grep :8080
   ```

3. **Clients cannot connect**:

   ```bash
   sudo wg show
   sudo iptables -L -n
   ```

4. **DNS resolution issues**:
   ```bash
   # Check DNS configuration in client config
   # Verify server can resolve DNS
   nslookup google.com
   ```

### Logs

- **Installation log**: `/var/log/wireguard-install.log`
- **WireGuard service**: `journalctl -u wg-quick@wg0`
- **Web interface**: `journalctl -u wireguard-web`
- **System logs**: `/var/log/syslog`

### Performance Tuning

1. **Optimize kernel parameters**:

   ```bash
   echo 'net.core.default_qdisc = fq' >> /etc/sysctl.conf
   echo 'net.ipv4.tcp_congestion_control = bbr' >> /etc/sysctl.conf
   sysctl -p
   ```

2. **Increase file limits**:
   ```bash
   echo '* soft nofile 65535' >> /etc/security/limits.conf
   echo '* hard nofile 65535' >> /etc/security/limits.conf
   ```

## Backup and Restore

### Create Backup

```bash
sudo wg-manage backup
```

### Restore from Backup

```bash
sudo tar -xzf /opt/wireguard-server/backups/wireguard_backup_TIMESTAMP.tar.gz -C /
sudo systemctl restart wg-quick@wg0
sudo systemctl restart wireguard-web
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: Report bugs and request features on GitHub
- **Documentation**: Additional documentation in the `/docs` folder
- **Community**: Join our discussions on GitHub

## Acknowledgments

- WireGuard® is a registered trademark of Jason A. Donenfeld
- Built with love using Node.js, Express, and Bootstrap
- Monitoring powered by Prometheus and Grafana
