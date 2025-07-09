# OpenVPN Security Guide

This guide covers security best practices for your OpenVPN server setup.

## Security Overview

Our OpenVPN setup includes several security layers:

- **Certificate-based authentication** (RSA 2048-bit)
- **Strong encryption** (AES-128-GCM/AES-256-GCM)
- **TLS authentication** (Additional security layer)
- **Firewall protection** (UFW configuration)
- **Secure dashboard** (SSL-encrypted web interface)

## Certificate Security

### 1. Certificate Authority (CA) Protection

**Best Practices:**

- Keep CA private key secure and offline when possible
- Use strong passphrase for CA key
- Regularly backup certificates
- Monitor certificate expiration dates

**CA Key Location:**

```bash
/opt/openvpn-server/data/pki/private/ca.key
```

### 2. Client Certificate Management

**Security Measures:**

- Generate unique certificates for each client
- Use descriptive names for client certificates
- Regularly audit active certificates
- Revoke certificates for inactive users

**Commands:**

```bash
# List all certificates
./scripts/client-generator.sh -l

# Create new client
./scripts/client-generator.sh -c client-name

# Revoke client certificate
./scripts/client-generator.sh -r client-name
```

### 3. Certificate Rotation

**Regular Rotation Schedule:**

- Server certificates: Every 2-3 years
- Client certificates: Every 1-2 years
- CA certificate: Every 5-10 years

## Encryption Settings

### 1. Current Security Configuration

**Cipher:** AES-128-GCM

- Provides authenticated encryption
- Optimal balance of security and performance
- Recommended by security experts

**Authentication:** SHA256

- Strong hash function
- Resistant to collision attacks
- Industry standard

### 2. Upgrading Encryption

For higher security requirements:

```bash
# Edit server configuration
cipher AES-256-GCM
auth SHA384
```

## Network Security

### 1. Firewall Configuration

**UFW Rules Applied:**

```bash
# SSH access
ufw allow ssh

# OpenVPN
ufw allow 1194/udp

# Dashboard
ufw allow 8080/tcp
ufw allow 443/tcp

# Enable firewall
ufw enable
```

### 2. Network Isolation

**VPN Network:**

- Isolated network: 10.8.0.0/24
- No access to server management interfaces
- Controlled routing to internal networks

### 3. DNS Security

**DNS Settings:**

- Primary: 8.8.8.8 (Google)
- Secondary: 8.8.4.4 (Google)
- Fallback: 1.1.1.1 (Cloudflare)

## Dashboard Security

### 1. Web Interface Protection

**SSL/TLS Configuration:**

- Self-signed certificate (replace with valid certificate)
- TLS 1.2+ minimum
- Strong cipher suites
- HSTS headers

### 2. Access Control

**Default Credentials:**

- Username: admin
- Password: UI_passw0rd
- **⚠️ Change immediately after installation**

**Changing Admin Password:**

```bash
# Access dashboard and change password
# Or reset via container
docker exec openvpn-ui /reset-password.sh
```

### 3. IP Restrictions

**Restrict Dashboard Access:**

```bash
# Allow only specific IP
ufw allow from YOUR_IP to any port 8080

# Remove general access
ufw delete allow 8080/tcp
```

## System Security

### 1. System Hardening

**Security Measures Applied:**

- Non-root user execution
- Restricted file permissions
- Regular security updates
- Minimal service exposure

### 2. Log Security

**Log Monitoring:**

- OpenVPN connection logs
- Authentication attempts
- System security events
- Dashboard access logs

**Log Locations:**

```bash
# OpenVPN logs
/opt/openvpn-server/data/logs/

# System logs
/var/log/auth.log
/var/log/syslog
```

## Access Control

### 1. User Management

**Best Practices:**

- Use descriptive client names
- Implement user lifecycle management
- Regular access reviews
- Immediate revocation for departing users

### 2. Connection Limits

**Current Limits:**

- Maximum clients: 100
- Concurrent connections per client: 1
- Connection timeout: 120 seconds

**Adjusting Limits:**

```bash
# Edit server configuration
max-clients 50
duplicate-cn  # Remove to prevent multiple connections
```

## Monitoring and Auditing

### 1. Security Monitoring

**Key Metrics:**

- Failed authentication attempts
- Unusual connection patterns
- Certificate expiration warnings
- System resource usage

**Monitoring Commands:**

```bash
# Check active connections
docker exec openvpn-server cat /tmp/openvpn-status.log

# Review authentication logs
tail -f /opt/openvpn-server/data/logs/server.log | grep AUTH
```

### 2. Security Alerts

**Automated Monitoring:**

```bash
# Add to crontab for security monitoring
0 */6 * * * /usr/local/bin/security-check.sh
```

## Backup and Recovery

### 1. Critical Files to Backup

**Essential Files:**

```bash
# Certificate Authority
/opt/openvpn-server/data/pki/ca.crt
/opt/openvpn-server/data/pki/private/ca.key

# Server certificates
/opt/openvpn-server/data/pki/issued/server.crt
/opt/openvpn-server/data/pki/private/server.key

# TLS authentication key
/opt/openvpn-server/data/pki/ta.key

# Configuration files
/opt/openvpn-server/configs/
```

### 2. Backup Script

**Automated Backup:**

```bash
#!/bin/bash
# OpenVPN Security Backup Script

BACKUP_DIR="/backup/openvpn-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Backup certificates
cp -r /opt/openvpn-server/data/pki "$BACKUP_DIR/"

# Backup configurations
cp -r /opt/openvpn-server/configs "$BACKUP_DIR/"

# Encrypt backup
tar -czf "$BACKUP_DIR.tar.gz" "$BACKUP_DIR"
gpg --symmetric --cipher-algo AES256 "$BACKUP_DIR.tar.gz"
```

## Incident Response

### 1. Security Incident Procedures

**Immediate Actions:**

1. Isolate affected systems
2. Review logs for compromise indicators
3. Revoke compromised certificates
4. Reset admin passwords
5. Update security measures

### 2. Recovery Procedures

**System Recovery:**

```bash
# Stop services
docker-compose down

# Restore from backup
# (restore process depends on backup method)

# Regenerate compromised certificates
docker exec openvpn-server easyrsa revoke COMPROMISED_CLIENT
docker exec openvpn-server easyrsa gen-crl

# Restart services
docker-compose up -d
```

## Security Best Practices

### 1. Regular Security Tasks

**Monthly:**

- Review active certificates
- Check system logs
- Update system packages
- Verify firewall rules

**Quarterly:**

- Audit user access
- Review security configuration
- Test backup procedures
- Update security documentation

**Annually:**

- Rotate server certificates
- Security assessment
- Update security policies
- Review incident response procedures

### 2. Additional Security Measures

**Enhanced Security:**

- Implement two-factor authentication
- Use hardware security modules (HSM)
- Enable intrusion detection systems
- Implement network segmentation
- Use VPN kill switches

### 3. Client Security

**Client-Side Security:**

- Use strong device passwords
- Enable device encryption
- Use official OpenVPN clients
- Avoid untrusted networks
- Regular client updates

## Compliance Considerations

### 1. Data Protection

**Privacy Measures:**

- Minimal logging policy
- Log retention policies
- Data encryption at rest
- Secure data transmission

### 2. Regulatory Compliance

**Common Requirements:**

- GDPR compliance for EU users
- HIPAA compliance for healthcare
- SOC 2 compliance for business
- PCI DSS compliance for payments

## Security Testing

### 1. Vulnerability Testing

**Regular Testing:**

```bash
# Test OpenVPN configuration
openvpn --config server.conf --test-crypto

# Network security scan
nmap -sS -O SERVER_IP

# SSL/TLS testing
sslyze --regular SERVER_IP:443
```

### 2. Penetration Testing

**Recommended Testing:**

- External vulnerability assessment
- Internal network penetration testing
- Web application security testing
- Social engineering assessment

## Conclusion

Security is an ongoing process requiring:

1. Regular monitoring and maintenance
2. Prompt security updates
3. Proper incident response procedures
4. Continuous security education
5. Regular security assessments

**Remember:** Security is only as strong as its weakest link. Regularly review and update security measures to maintain protection against evolving threats.

## Emergency Contacts

**Security Incident Response:**

- System Administrator: [Your Contact]
- Security Team: [Your Contact]
- Legal/Compliance: [Your Contact]

**Escalation Procedures:**

1. Immediate containment
2. Incident documentation
3. Stakeholder notification
4. Recovery implementation
5. Post-incident review
