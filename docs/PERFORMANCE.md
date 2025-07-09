# OpenVPN Performance Optimization Guide

This guide provides detailed information on optimizing OpenVPN server performance for high-speed connections.

## Quick Performance Checklist

- ✅ Use UDP protocol (default in our setup)
- ✅ Enable AES-128-GCM encryption (balance of security and speed)
- ✅ Disable compression for modern connections
- ✅ Optimize network buffers
- ✅ Use performance-optimized system settings
- ✅ Configure proper firewall rules
- ✅ Monitor system resources

## Performance Factors

### 1. Protocol Selection

**UDP vs TCP:**

- **UDP (Recommended)**: Faster, lower latency, better for real-time applications
- **TCP**: More reliable but slower, use only when UDP is blocked

**Configuration:**

```
proto udp
port 1194
```

### 2. Encryption Optimization

**Cipher Selection:**

- **AES-128-GCM**: Best balance of security and performance
- **AES-256-GCM**: Higher security but slower
- **ChaCha20-Poly1305**: Good for older hardware

**Configuration:**

```
cipher AES-128-GCM
auth SHA256
```

### 3. Network Buffer Optimization

**Buffer Settings:**

```
# Server configuration
sndbuf 0
rcvbuf 0
push "sndbuf 393216"
push "rcvbuf 393216"
fast-io
```

### 4. System-Level Optimizations

**Network Stack:**

```bash
# Increase network buffer sizes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# UDP optimizations
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
```

## Performance Monitoring

### 1. Built-in Monitoring

Run the performance monitoring script:

```bash
/usr/local/bin/openvpn-monitor.sh
```

### 2. Key Metrics to Monitor

**CPU Usage:**

- Should be under 80% for optimal performance
- Single-threaded performance is most important

**Memory Usage:**

- Monitor for memory leaks
- Each client uses approximately 1-2MB RAM

**Network Statistics:**

- Monitor packet loss and errors
- Check for buffer overruns

**Connection Count:**

- Monitor active connections
- Each connection increases resource usage

### 3. Performance Testing

**Speed Test Commands:**

```bash
# Install iperf3
apt install iperf3

# On server (inside VPN network)
iperf3 -s

# On client (through VPN)
iperf3 -c SERVER_IP -t 60
```

## Optimization Recommendations by Hardware

### Low-End VPS (1 CPU, 1GB RAM)

- Max clients: 10-20
- Use AES-128-GCM
- Disable compression
- Monitor CPU usage closely

### Mid-Range VPS (2 CPU, 2GB RAM)

- Max clients: 50-100
- Use AES-128-GCM or AES-256-GCM
- Enable performance optimizations
- Consider multiple server instances

### High-End Server (4+ CPU, 4GB+ RAM)

- Max clients: 100-500
- Use AES-256-GCM for better security
- Full optimization enabled
- Load balancing across multiple instances

## Performance Tuning Steps

### 1. Run Performance Tuning Script

```bash
sudo ./scripts/performance-tuning.sh
```

### 2. Apply System Optimizations

```bash
# Enable IP forwarding
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

# Apply network optimizations
sysctl -p

# Restart OpenVPN
docker-compose restart openvpn-server
```

### 3. Monitor and Adjust

```bash
# Check performance
/usr/local/bin/openvpn-monitor.sh

# Health check
/usr/local/bin/health-check.sh
```

## Common Performance Issues

### 1. High CPU Usage

**Symptoms:** Server becomes unresponsive, slow connections
**Solutions:**

- Reduce encryption strength
- Limit concurrent connections
- Upgrade hardware
- Use multiple server instances

### 2. Network Congestion

**Symptoms:** Packet loss, timeouts
**Solutions:**

- Optimize network buffers
- Check network interface settings
- Monitor bandwidth usage
- Adjust MTU settings

### 3. Memory Issues

**Symptoms:** System becomes slow, OOM errors
**Solutions:**

- Monitor memory usage per client
- Increase swap space
- Add more RAM
- Limit concurrent connections

## Advanced Optimizations

### 1. Multi-Threading

OpenVPN is single-threaded, but you can run multiple instances:

```bash
# Run multiple OpenVPN instances on different ports
docker-compose up -d --scale openvpn-server=2
```

### 2. Hardware Acceleration

For dedicated servers with AES-NI support:

```bash
# Check for AES-NI support
grep -m1 -o aes /proc/cpuinfo
```

### 3. Network Interface Optimization

```bash
# Optimize network interface
ethtool -K eth0 gso off
ethtool -K eth0 tso off
ethtool -K eth0 lro off
```

## Benchmarking Results

### Typical Performance Expectations

**1 CPU Core, 1GB RAM:**

- UDP: 50-100 Mbps
- TCP: 30-80 Mbps
- Max clients: 20-50

**2 CPU Cores, 2GB RAM:**

- UDP: 100-300 Mbps
- TCP: 80-200 Mbps
- Max clients: 50-100

**4 CPU Cores, 4GB RAM:**

- UDP: 300-500 Mbps
- TCP: 200-400 Mbps
- Max clients: 100-200

### Factors Affecting Performance

1. **Server Hardware**

   - CPU speed (single-thread performance)
   - RAM amount
   - Network interface speed

2. **Client Hardware**

   - Device CPU capability
   - Network connection quality
   - VPN client software

3. **Network Conditions**
   - Latency between client and server
   - Packet loss
   - Bandwidth limitations

## Troubleshooting Performance Issues

### 1. Identify Bottlenecks

```bash
# Check CPU usage
top -p $(pgrep openvpn)

# Check memory usage
free -h

# Check network statistics
netstat -i

# Check OpenVPN logs
tail -f /var/log/openvpn/server.log
```

### 2. Common Solutions

**Slow Connections:**

- Check server resources
- Verify network configuration
- Test with different encryption

**High Latency:**

- Check network routing
- Optimize keepalive settings
- Use UDP protocol

**Frequent Disconnections:**

- Adjust keepalive settings
- Check firewall rules
- Monitor network stability

## Performance Monitoring Tools

### 1. System Monitoring

```bash
# Real-time monitoring
htop

# Network monitoring
iftop

# I/O monitoring
iotop
```

### 2. OpenVPN Specific

```bash
# OpenVPN status
docker exec openvpn-server cat /tmp/openvpn-status.log

# Connection statistics
docker logs openvpn-server
```

### 3. Automated Monitoring

Set up monitoring with our provided scripts:

```bash
# Add to crontab for regular monitoring
0 */6 * * * /usr/local/bin/health-check.sh >> /var/log/health-check.log
```

## Conclusion

Optimal OpenVPN performance requires a combination of:

1. Proper protocol and encryption selection
2. System-level optimizations
3. Regular monitoring and maintenance
4. Hardware appropriate for your usage

Use the provided scripts and monitoring tools to maintain peak performance. Remember that OpenVPN is primarily CPU-bound, so single-thread performance is crucial for high-speed connections.
