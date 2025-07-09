# OpenVPN Server Setup with Web Interface

A fast and secure OpenVPN server setup for Ubuntu VPS with web-based management interface.

## Features

- **Fast Performance**: Optimized OpenVPN configuration with UDP protocol
- **Web Interface**: OpenVPN-Admin web panel for easy client management
- **Docker Support**: Containerized deployment option
- **Native Installation**: Traditional system-wide installation
- **Easy Client Management**: Generate, revoke, and manage client certificates
- **Security**: Modern encryption with perfect forward secrecy

## Quick Start

### Option 1: Docker Installation (Recommended)

```bash
chmod +x install-docker.sh
sudo ./install-docker.sh
```

### Option 2: Native Installation

```bash
chmod +x install-native.sh
sudo ./install-native.sh
```

## Requirements

- Ubuntu 18.04+ VPS
- Root access or sudo privileges
- Public IP address
- At least 1GB RAM
- Open ports: 1194 (OpenVPN), 8080 (Web Interface)

## Post-Installation

1. Access web interface: `http://your-server-ip:8080`
2. Default credentials: `admin/admin` (change immediately)
3. Create client certificates through the web interface
4. Download client configurations

## Performance Optimizations

- UDP protocol for faster speeds
- Optimized cipher suites
- Compressed LZ4 algorithm
- Multiple worker processes
- Kernel-level packet processing

## Security Features

- AES-256-GCM encryption
- RSA-4096 certificates
- Perfect Forward Secrecy
- TLS authentication
- Client certificate revocation

## Client Setup

See [docs/client-setup.md](docs/client-setup.md) for detailed client configuration instructions.

## Troubleshooting

Common issues and solutions are documented in [docs/troubleshooting.md](docs/troubleshooting.md).

## License

MIT License
