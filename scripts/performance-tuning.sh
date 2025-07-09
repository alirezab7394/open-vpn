#!/bin/bash

# OpenVPN Server Performance Tuning Script
# This script optimizes the system for high-performance OpenVPN usage

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

print_info "Starting OpenVPN performance tuning..."

# 1. Enable IP forwarding
print_info "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf

# 2. Optimize network buffer sizes
print_info "Optimizing network buffer sizes..."
cat >> /etc/sysctl.conf << EOF

# OpenVPN Performance Optimizations
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.core.netdev_max_backlog = 5000
net.core.netdev_budget = 600
EOF

# 3. Optimize connection tracking
print_info "Optimizing connection tracking..."
cat >> /etc/sysctl.conf << EOF

# Connection tracking optimizations
net.netfilter.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_generic_timeout = 120
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120
EOF

# 4. Optimize TCP settings
print_info "Optimizing TCP settings..."
cat >> /etc/sysctl.conf << EOF

# TCP optimizations
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_fin_timeout = 30
EOF

# 5. Optimize UDP settings
print_info "Optimizing UDP settings..."
cat >> /etc/sysctl.conf << EOF

# UDP optimizations
net.ipv4.udp_mem = 102400 873800 16777216
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
EOF

# 6. File descriptor limits
print_info "Optimizing file descriptor limits..."
cat >> /etc/security/limits.conf << EOF

# OpenVPN performance limits
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
root soft nofile 65535
root hard nofile 65535
root soft nproc 65535
root hard nproc 65535
EOF

# 7. Set CPU governor to performance
print_info "Setting CPU governor to performance..."
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    echo 'performance' > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    
    # Make it persistent
    echo 'GOVERNOR="performance"' >> /etc/default/cpufrequtils
fi

# 8. Optimize swappiness
print_info "Optimizing swappiness..."
echo 'vm.swappiness=10' >> /etc/sysctl.conf

# 9. Optimize dirty ratio
print_info "Optimizing dirty ratio..."
cat >> /etc/sysctl.conf << EOF

# Memory optimizations
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 1500
vm.dirty_writeback_centisecs = 250
EOF

# 10. IRQ affinity (if multiple cores available)
print_info "Optimizing IRQ affinity..."
CORES=$(nproc)
if [ $CORES -gt 1 ]; then
    # Create script to balance IRQs
    cat > /usr/local/bin/irq-balance.sh << 'EOF'
#!/bin/bash
# Simple IRQ balancing for network interfaces
for irq in $(cat /proc/interrupts | grep eth0 | cut -d: -f1); do
    echo 2 > /proc/irq/$irq/smp_affinity
done
EOF
    chmod +x /usr/local/bin/irq-balance.sh
    
    # Add to rc.local
    echo '/usr/local/bin/irq-balance.sh' >> /etc/rc.local
fi

# 11. Apply all settings
print_info "Applying all settings..."
sysctl -p

# 12. Create performance monitoring script
print_info "Creating performance monitoring script..."
cat > /usr/local/bin/openvpn-monitor.sh << 'EOF'
#!/bin/bash
# OpenVPN Performance Monitor

echo "=== OpenVPN Performance Monitor ==="
echo "Date: $(date)"
echo

# CPU Usage
echo "=== CPU Usage ==="
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "CPU Usage: " 100 - $1 "%"}'
echo

# Memory Usage
echo "=== Memory Usage ==="
free -h
echo

# Network Statistics
echo "=== Network Statistics ==="
cat /proc/net/dev | grep -E "(eth0|ens|enp)"
echo

# Connection Count
echo "=== Connection Count ==="
netstat -an | grep :1194 | wc -l | awk '{print "OpenVPN Connections: " $1}'
echo

# Top Processes
echo "=== Top Processes ==="
ps aux --sort=-%cpu | head -10
echo

# Load Average
echo "=== Load Average ==="
uptime
echo

# Disk Usage
echo "=== Disk Usage ==="
df -h /
echo
EOF

chmod +x /usr/local/bin/openvpn-monitor.sh

# 13. Create firewall optimization script
print_info "Creating firewall optimization script..."
cat > /usr/local/bin/firewall-optimize.sh << 'EOF'
#!/bin/bash
# OpenVPN Firewall Optimization

# Optimize iptables for OpenVPN
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
iptables -A INPUT -i tun+ -j ACCEPT
iptables -A FORWARD -i tun+ -j ACCEPT
iptables -A FORWARD -i tun+ -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o tun+ -m state --state RELATED,ESTABLISHED -j ACCEPT

# Optimize connection tracking
echo 1000000 > /proc/sys/net/netfilter/nf_conntrack_max
echo 120 > /proc/sys/net/netfilter/nf_conntrack_generic_timeout
echo 300 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established

# Save rules
iptables-save > /etc/iptables/rules.v4
EOF

chmod +x /usr/local/bin/firewall-optimize.sh

# 14. Create system health check
print_info "Creating system health check..."
cat > /usr/local/bin/health-check.sh << 'EOF'
#!/bin/bash
# System Health Check for OpenVPN

echo "=== System Health Check ==="
echo "Date: $(date)"
echo

# Check if OpenVPN is running
if pgrep openvpn > /dev/null; then
    echo "✓ OpenVPN is running"
else
    echo "✗ OpenVPN is not running"
fi

# Check if Docker is running
if systemctl is-active --quiet docker; then
    echo "✓ Docker is running"
else
    echo "✗ Docker is not running"
fi

# Check disk space
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $DISK_USAGE -lt 80 ]; then
    echo "✓ Disk usage is healthy ($DISK_USAGE%)"
else
    echo "⚠ Disk usage is high ($DISK_USAGE%)"
fi

# Check memory usage
MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
if [ $MEM_USAGE -lt 80 ]; then
    echo "✓ Memory usage is healthy ($MEM_USAGE%)"
else
    echo "⚠ Memory usage is high ($MEM_USAGE%)"
fi

# Check load average
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
CORES=$(nproc)
if (( $(echo "$LOAD_AVG < $CORES" | bc -l) )); then
    echo "✓ Load average is healthy ($LOAD_AVG)"
else
    echo "⚠ Load average is high ($LOAD_AVG)"
fi

echo
EOF

chmod +x /usr/local/bin/health-check.sh

# 15. Set up log rotation
print_info "Setting up log rotation..."
cat > /etc/logrotate.d/openvpn << 'EOF'
/var/log/openvpn/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 640 root root
    postrotate
        killall -USR1 openvpn || true
    endscript
}
EOF

print_info "Performance tuning completed successfully!"
print_info "System will be optimized after reboot, or run 'sysctl -p' to apply immediately."
print_info ""
print_info "Available monitoring tools:"
print_info "  - /usr/local/bin/openvpn-monitor.sh - Performance monitoring"
print_info "  - /usr/local/bin/health-check.sh - System health check"
print_info "  - /usr/local/bin/firewall-optimize.sh - Firewall optimization"
print_info ""
print_info "Run 'reboot' to apply all changes, or restart OpenVPN service." 