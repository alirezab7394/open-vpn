# Client Setup Guide

## Install Tailscale Client

### Windows

1. Download from: https://tailscale.com/download/windows
2. Install and run Tailscale

### macOS

1. Download from: https://tailscale.com/download/mac
2. Install and run Tailscale

### Linux

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### iOS/Android

Install from App Store/Play Store

## Connect to Your Headscale Server

### Command Line

```bash
tailscale up --login-server=https://your-server-domain.com
```

### Web Interface

1. Open Tailscale client
2. Go to Settings → Login Server
3. Enter: `https://your-server-domain.com`
4. Connect

## Approve Device

### Using Web Interface

1. Go to `https://your-server-domain.com:8000/admin`
2. See pending devices
3. Approve the device

### Using Command Line

```bash
./manage-users.sh list-nodes
sudo headscale nodes register --user username --key [machine-key]
```

## Test Connection

1. Check IP: `tailscale ip`
2. Test connectivity: `ping 100.64.0.1`
3. Check status: `tailscale status`

## Troubleshooting

### Common Issues

1. **Can't connect to server**

   - Check firewall ports: 8080, 50443, 3478
   - Verify domain/IP in config

2. **Device not appearing**

   - Restart Tailscale client
   - Check server logs: `./logs.sh`

3. **No internet access**
   - Enable IP forwarding on server
   - Check DNS settings

### Enable IP Forwarding (Server)

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Configure Firewall

```bash
sudo ufw allow 8080
sudo ufw allow 50443
sudo ufw allow 3478/udp
sudo ufw enable
```

```

This complete setup gives you:

## **Features:**
- **High Speed**: WireGuard-based mesh networking
- **Web Interface**: Modern React-based UI at port 8000
- **Easy Management**: Scripts for user/device management
- **SSL/TLS**: Automatic certificate setup
- **Docker Option**: Easy deployment and updates
- **Native Option**: Direct installation without Docker

## **Usage:**
1. **Install**: `./install-docker.sh` (or `./install-native.sh`)
2. **Start**: `./start-server.sh`
3. **Manage**: `./manage-users.sh create-user myuser`
4. **Access**: Web interface at `http://your-server:8000/admin`

## **Benefits over traditional VPN:**
- **Mesh networking**: Direct device-to-device connections
- **NAT traversal**: Works behind firewalls automatically
- **Zero-config**: Devices find each other automatically
- **Cross-platform**: Works on all devices
- **High performance**: WireGuard protocol

Would you like me to customize any part of this setup or add additional features?
```
