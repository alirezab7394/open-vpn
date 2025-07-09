#!/bin/bash

# WireGuard Web Service Restart Script

echo "Restarting WireGuard Web Service..."

# Stop the service
sudo systemctl stop wireguard-web

# Wait a moment
sleep 2

# Start the service
sudo systemctl start wireguard-web

# Check status
echo "Service Status:"
sudo systemctl status wireguard-web --no-pager

# Show logs
echo -e "\nRecent Logs:"
sudo journalctl -u wireguard-web -n 10 --no-pager

echo -e "\nWeb interface should be available at: http://$(curl -s ifconfig.me):8080" 