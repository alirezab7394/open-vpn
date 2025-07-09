# High-Performance OpenVPN Server Setup

A complete OpenVPN server setup with web dashboard for Ubuntu VPS, optimized for high speed and performance.

## Features

- **High-Performance OpenVPN Server**: Optimized for speed with UDP, AES-128-GCM encryption
- **Web Dashboard**: Easy-to-use web interface for client management
- **Docker-based**: Containerized setup for easy deployment and management
- **Security Hardened**: Best practices for VPN security
- **Multi-Client Support**: Easy client configuration generation
- **Performance Monitoring**: Built-in monitoring and logging

## Quick Start

1. **Prerequisites**
   - Ubuntu 20.04+ VPS with root access
   - Minimum 1GB RAM, 1 CPU core
   - Public IP address
   - Domain name (optional but recommended)

2. **Installation**
   ```bash
   git clone <your-repo>
   cd openvpn-server-setup
   chmod +x install.sh
   ./install.sh
   ```

3. **Access Dashboard**
   - Web UI: `https://your-server-ip:8080`
   - Default credentials: `admin` / `UI_passw0rd`

## Project Structure

```
openvpn-server-setup/
├── README.md
├── install.sh                 # Main installation script
├── docker-compose.yml         # Docker services configuration
├── configs/
│   ├── server.conf            # OpenVPN server configuration
│   ├── firewall.sh            # UFW firewall rules
│   └── easy-rsa.vars          # Certificate generation variables
├── scripts/
│   ├── performance-tuning.sh  # Performance optimization script
│   ├── client-generator.sh    # Client configuration generator
│   ├── backup.sh              # Backup configuration script
│   └── monitoring.sh          # Server monitoring script
├── templates/
│   ├── client-template.ovpn   # Client configuration template
│   └── nginx.conf             # Nginx configuration for SSL
├── ssl/
│   └── generate-certs.sh      # SSL certificate generation
└── docs/
    ├── PERFORMANCE.md         # Performance optimization guide
    ├── SECURITY.md            # Security best practices
    └── TROUBLESHOOTING.md     # Common issues and solutions
```

## Performance Optimizations

- **UDP Protocol**: Faster than TCP for VPN traffic
- **AES-128-GCM**: Optimal balance of security and performance
- **Buffer Optimization**: Increased send/receive buffers
- **MTU Optimization**: Reduced packet fragmentation
- **Compression Disabled**: For better performance on modern hardware

## Dashboard Features

- **Client Management**: Add, remove, and monitor clients
- **Server Status**: Real-time server performance metrics
- **Log Monitoring**: View OpenVPN logs and connection status
- **Configuration Download**: Easy client config generation
- **SSL Security**: Secure web interface access

## Security Features

- **Strong Encryption**: AES-256-GCM with SHA-256 authentication
- **Certificate-based Authentication**: RSA 2048-bit certificates
- **Firewall Integration**: UFW firewall configuration
- **Access Control**: IP-based restrictions and user management
- **Secure Dashboard**: SSL-encrypted web interface

## Supported Clients

- **Windows**: OpenVPN GUI, OpenVPN Connect
- **macOS**: Viscosity, OpenVPN Connect
- **Linux**: OpenVPN client, NetworkManager
- **Android**: OpenVPN Connect, OpenVPN for Android
- **iOS**: OpenVPN Connect

## Monitoring & Maintenance

- **Server Metrics**: CPU, memory, and network usage
- **Client Connections**: Active connections and bandwidth
- **Log Analysis**: Automated log rotation and analysis
- **Backup System**: Automated configuration backups

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Support

For issues and questions:
- Check the [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- Review [Performance Guide](docs/PERFORMANCE.md)
- Check [Security Guide](docs/SECURITY.md)

## License

MIT License - see LICENSE file for details 