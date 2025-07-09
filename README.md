# Headscale VPN Server Setup

A self-hosted Tailscale control server with web interface for Ubuntu.

## Features

- **High Performance**: WireGuard-based mesh VPN
- **Web Interface**: Multiple UI options (Headscale-UI, Tailscale Web)
- **Easy Management**: Docker-based deployment
- **Automatic NAT Traversal**: Works behind firewalls
- **Cross-Platform**: Windows, macOS, Linux, iOS, Android clients

## Quick Start

### Option 1: Docker Setup (Recommended)

```bash
./install-docker.sh
```

### Option 2: Native Installation

```bash
./install-native.sh
```

## Web Interfaces

1. **Headscale-UI**: Modern React-based interface
2. **Tailscale Web**: Official Tailscale web client
3. **Command Line**: Full CLI management

## Usage

1. Start the server: `./start-server.sh`
2. Access web interface: `http://your-server-ip:8080`
3. Create users: `./manage-users.sh`
4. Add devices: Use the web interface or CLI

## Client Setup

Download Tailscale clients and point them to your Headscale server.

## Documentation

- [Installation Guide](docs/installation.md)
- [Configuration Guide](docs/configuration.md)
- [Troubleshooting](docs/troubleshooting.md)
