#!/bin/bash

# OpenVPN Performance Optimization Script

set -e

log() {
    echo -e "\e[32m[$(date +'%Y-%m-%d %H:%M:%S')] $1\e[0m"
}

log "Optimizing OpenVPN performance..."

# Kernel optimizations
log "Applying kernel optimizations..."
cat >> /etc/sysctl.conf << EOF

# OpenVPN Performance Optimizations
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.core.netdev_max_backlog = 5000
net.ipv4.ip_forward = 1
net.ipv4.tcp_congestion_control = bbr
EOF

sysctl -p

# CPU governor optimization
log "Setting CPU governor to performance..."
echo 'performance' | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# IRQ balance optimization
log "Optimizing IRQ balance..."
systemctl enable irqbalance
systemctl start irqbalance

# Add performance tuning to OpenVPN config
log "Adding performance tuning to OpenVPN configuration..."
cat >> /etc/openvpn/server.conf << EOF

# Performance optimizations
fast-io
sndbuf 393216
rcvbuf 393216
push "sndbuf 393216"
push "rcvbuf 393216"
explicit-exit-notify 1
comp-lzo adaptive
EOF

log "Performance optimization complete!"
log "Restart OpenVPN service to apply changes" 