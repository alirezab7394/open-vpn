# OpenVPN Server Troubleshooting Guide

## Common Issues and Solutions

### 1. Blank Page at `/ov/clientconfig` Route

**Problem**: The OpenVPN-UI dashboard shows a blank page when navigating to client configuration.

**Root Cause**: Missing nginx configuration file causing routing issues.

**Solution**:

#### Option A: Quick Fix (HTTP Only)

1. **Replace the nginx configuration** with HTTP-only version:

   ```bash
   cp configs/nginx-http-only.conf configs/nginx.conf
   ```

2. **Restart containers**:

   ```bash
   docker-compose down
   docker-compose up -d
   ```

3. **Access the dashboard** at: `http://your-server-ip:8080`

#### Option B: Full SSL Setup

1. **Generate SSL certificates**:

   ```bash
   chmod +x scripts/generate-ssl.sh
   ./scripts/generate-ssl.sh
   ```

2. **Keep the existing nginx.conf** (already configured for SSL)

3. **Restart containers**:

   ```bash
   docker-compose down
   docker-compose up -d
   ```

4. **Access the dashboard** at: `https://your-server-ip:443`

### 2. Container Startup Issues

**Check container status**:

```bash
docker-compose ps
```

**View logs**:

```bash
# OpenVPN Server logs
docker-compose logs openvpn-server

# OpenVPN-UI logs
docker-compose logs openvpn-ui

# Nginx logs
docker-compose logs nginx
```

**Common fixes**:

- Ensure required directories exist:
  ```bash
  mkdir -p data/{pki,clients,logs,db}
  ```
- Check port conflicts:
  ```bash
  netstat -tulpn | grep -E ":(8080|443|1194|8080)"
  ```

### 3. PKI/Certificate Issues

**Problem**: Client configuration generation fails or shows errors.

**Solution**:

1. **Initialize PKI manually**:

   ```bash
   docker-compose exec openvpn-server ovpn_genconfig -u udp://your-server-ip
   docker-compose exec openvpn-server ovpn_initpki
   ```

2. **Generate server certificates**:

   ```bash
   docker-compose exec openvpn-server easyrsa build-server-full server nopass
   ```

3. **Generate DH parameters**:
   ```bash
   docker-compose exec openvpn-server easyrsa gen-dh
   ```

### 4. Dashboard Login Issues

**Default credentials**:

- Username: `admin`
- Password: `UI_passw0rd`

**Reset admin password**:

```bash
docker-compose exec openvpn-ui /bin/sh -c "echo 'admin:new_password' | chpasswd"
```

### 5. OpenVPN Connection Issues

**Check server status**:

```bash
docker-compose exec openvpn-server ovpn_status
```

**View active connections**:

```bash
docker-compose exec openvpn-server cat /var/log/openvpn/openvpn-status.log
```

**Common fixes**:

- Verify firewall rules:
  ```bash
  sudo ufw status
  sudo ufw allow 1194/udp
  ```
- Check server configuration:
  ```bash
  docker-compose exec openvpn-server cat /etc/openvpn/server.conf
  ```

### 6. Network Connectivity Issues

**Test internal communication**:

```bash
# Test OpenVPN-UI to OpenVPN-Server communication
docker-compose exec openvpn-ui nc -z openvpn-server 2080

# Test nginx to OpenVPN-UI communication
docker-compose exec nginx nc -z openvpn-ui 8080
```

**Check Docker network**:

```bash
docker network ls
docker network inspect openvpn-server-setup_openvpn-network
```

### 7. Performance Issues

**Monitor resource usage**:

```bash
docker stats
```

**Check OpenVPN performance**:

```bash
# View connection logs
docker-compose logs openvpn-server | grep -E "(CONNECT|DISCONNECT)"

# Monitor bandwidth usage
docker-compose exec openvpn-server iftop -i tun0
```

### 8. Backup and Recovery

**Create backup**:

```bash
chmod +x scripts/backup.sh
./scripts/backup.sh
```

**Restore from backup**:

```bash
./scripts/backup.sh restore /path/to/backup.tar.gz
```

## Step-by-Step Debugging

### For Blank Page Issues:

1. **Check if containers are running**:

   ```bash
   docker-compose ps
   ```

2. **Verify nginx configuration**:

   ```bash
   docker-compose exec nginx nginx -t
   ```

3. **Check OpenVPN-UI accessibility**:

   ```bash
   curl -I http://localhost:8080
   ```

4. **Test direct access**:

   - Try accessing OpenVPN-UI directly: `http://your-server-ip:8080`
   - If this works, the issue is with nginx routing

5. **Check browser console**:
   - Open browser developer tools
   - Look for JavaScript errors or failed requests

### For SSL Issues:

1. **Verify SSL certificates exist**:

   ```bash
   ls -la ssl/
   ```

2. **Test certificate validity**:

   ```bash
   openssl x509 -in ssl/server.crt -text -noout
   ```

3. **Check certificate expiration**:
   ```bash
   openssl x509 -in ssl/server.crt -noout -dates
   ```

## Getting Help

If you're still experiencing issues:

1. **Collect logs**:

   ```bash
   docker-compose logs > debug.log 2>&1
   ```

2. **Check system resources**:

   ```bash
   free -h
   df -h
   ```

3. **Verify network connectivity**:

   ```bash
   ss -tulpn | grep -E ":(80|443|1194|8080)"
   ```

4. **Document the issue**:
   - What URL were you trying to access?
   - What error messages appeared?
   - What does the browser console show?
   - What do the container logs show?

## Quick Recovery Commands

**Complete restart**:

```bash
docker-compose down
docker-compose up -d
```

**Reset everything** (destructive):

```bash
docker-compose down -v
sudo rm -rf data/
docker-compose up -d
```

**Rebuild containers**:

```bash
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```
