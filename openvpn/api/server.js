const express = require('express');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const cors = require('cors');
const multer = require('multer');
const bcrypt = require('bcrypt');

const app = express();
const PORT = 3001;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Storage configuration
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, '/app/storage/');
    },
    filename: (req, file, cb) => {
        cb(null, file.originalname);
    }
});
const upload = multer({ storage });

// Helper functions
const execPromise = (command) => {
    return new Promise((resolve, reject) => {
        exec(command, (error, stdout, stderr) => {
            if (error) {
                reject({ error: error.message, stderr });
            } else {
                resolve(stdout);
            }
        });
    });
};

const readFile = (filePath) => {
    return new Promise((resolve, reject) => {
        fs.readFile(filePath, 'utf8', (err, data) => {
            if (err) reject(err);
            else resolve(data);
        });
    });
};

const writeFile = (filePath, data) => {
    return new Promise((resolve, reject) => {
        fs.writeFile(filePath, data, (err) => {
            if (err) reject(err);
            else resolve();
        });
    });
};

// Routes

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Get server status
app.get('/api/status', async (req, res) => {
    try {
        const status = await execPromise('systemctl is-active openvpn-server@server');
        const connections = await execPromise('cat /var/log/openvpn/status.log | grep "CLIENT_LIST" | wc -l');
        const uptime = await execPromise('systemctl show openvpn-server@server --property=ActiveEnterTimestamp');

        res.json({
            status: status.trim(),
            connections: parseInt(connections.trim()) || 0,
            uptime: uptime.trim(),
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get active connections
app.get('/api/connections', async (req, res) => {
    try {
        const statusLog = await readFile('/var/log/openvpn/status.log');
        const lines = statusLog.split('\n');
        const connections = [];

        let inClientList = false;
        for (const line of lines) {
            if (line.startsWith('CLIENT_LIST')) {
                inClientList = true;
                continue;
            }
            if (line.startsWith('ROUTING_TABLE')) {
                inClientList = false;
                break;
            }
            if (inClientList && line.trim()) {
                const parts = line.split(',');
                if (parts.length >= 5) {
                    connections.push({
                        client: parts[0],
                        realAddress: parts[1],
                        virtualAddress: parts[2],
                        bytesReceived: parseInt(parts[3]) || 0,
                        bytesSent: parseInt(parts[4]) || 0,
                        connectedSince: parts[5] || 'Unknown'
                    });
                }
            }
        }

        res.json(connections);
    } catch (error) {
        res.json([]);
    }
});

// Get server logs
app.get('/api/logs', async (req, res) => {
    try {
        const logs = await execPromise('tail -100 /var/log/openvpn/server.log');
        res.json({
            logs: logs.split('\n').filter(line => line.trim())
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get clients list
app.get('/api/clients', async (req, res) => {
    try {
        const clients = await execPromise('ls -la /etc/openvpn/easy-rsa/pki/issued/ | grep ".crt" | awk \'{print $9}\' | sed "s/.crt//"');
        const clientList = clients.split('\n').filter(client => client.trim() && client !== 'server');

        const clientsWithStatus = await Promise.all(
            clientList.map(async (client) => {
                try {
                    const certInfo = await execPromise(`openssl x509 -in /etc/openvpn/easy-rsa/pki/issued/${client}.crt -noout -dates`);
                    const validFrom = certInfo.match(/notBefore=(.*)/)?.[1] || 'Unknown';
                    const validTo = certInfo.match(/notAfter=(.*)/)?.[1] || 'Unknown';

                    return {
                        name: client,
                        status: 'active',
                        validFrom,
                        validTo,
                        created: new Date().toISOString()
                    };
                } catch (error) {
                    return {
                        name: client,
                        status: 'error',
                        error: error.message
                    };
                }
            })
        );

        res.json(clientsWithStatus);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Create new client
app.post('/api/clients', async (req, res) => {
    try {
        const { clientName } = req.body;

        if (!clientName || !/^[a-zA-Z0-9_-]+$/.test(clientName)) {
            return res.status(400).json({ error: 'Invalid client name' });
        }

        // Generate client certificate
        await execPromise(`cd /etc/openvpn/easy-rsa && ./easyrsa build-client-full ${clientName} nopass`);

        // Generate client configuration
        const clientConfig = `client
dev tun
proto udp
remote YOUR_SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert ${clientName}.crt
key ${clientName}.key
remote-cert-tls server
cipher AES-256-CBC
verb 3
auth SHA256
key-direction 1
script-security 2
up /etc/openvpn/update-resolv-conf
down /etc/openvpn/update-resolv-conf
`;

        await writeFile(`/etc/openvpn/clients/${clientName}.ovpn`, clientConfig);

        res.json({
            success: true,
            client: clientName,
            message: 'Client created successfully'
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Download client config
app.get('/api/clients/:clientName/config', async (req, res) => {
    try {
        const { clientName } = req.params;
        const configPath = `/etc/openvpn/clients/${clientName}.ovpn`;

        if (!fs.existsSync(configPath)) {
            return res.status(404).json({ error: 'Client config not found' });
        }

        const config = await readFile(configPath);
        res.set({
            'Content-Type': 'application/octet-stream',
            'Content-Disposition': `attachment; filename="${clientName}.ovpn"`
        });
        res.send(config);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Revoke client certificate
app.delete('/api/clients/:clientName', async (req, res) => {
    try {
        const { clientName } = req.params;

        await execPromise(`cd /etc/openvpn/easy-rsa && ./easyrsa revoke ${clientName}`);
        await execPromise(`cd /etc/openvpn/easy-rsa && ./easyrsa gen-crl`);

        // Remove client config file
        const configPath = `/etc/openvpn/clients/${clientName}.ovpn`;
        if (fs.existsSync(configPath)) {
            fs.unlinkSync(configPath);
        }

        res.json({
            success: true,
            message: 'Client revoked successfully'
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get server configuration
app.get('/api/config', async (req, res) => {
    try {
        const config = await readFile('/etc/openvpn/server.conf');
        res.json({ config });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Update server configuration
app.put('/api/config', async (req, res) => {
    try {
        const { config } = req.body;

        if (!config) {
            return res.status(400).json({ error: 'Configuration is required' });
        }

        // Backup current config
        await execPromise('cp /etc/openvpn/server.conf /etc/openvpn/server.conf.backup');

        // Write new config
        await writeFile('/etc/openvpn/server.conf', config);

        res.json({
            success: true,
            message: 'Configuration updated successfully'
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Restart OpenVPN server
app.post('/api/restart', async (req, res) => {
    try {
        await execPromise('systemctl restart openvpn-server@server');
        res.json({
            success: true,
            message: 'OpenVPN server restarted successfully'
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get server metrics
app.get('/api/metrics', async (req, res) => {
    try {
        const cpuUsage = await execPromise('top -bn1 | grep "Cpu(s)" | awk \'{print $2}\' | sed "s/%us,//"');
        const memoryUsage = await execPromise('free -m | awk \'NR==2{printf "%.2f", $3*100/$2}\'');
        const diskUsage = await execPromise('df -h / | awk \'NR==2{print $5}\' | sed "s/%//"');
        const networkRx = await execPromise('cat /proc/net/dev | grep eth0 | awk \'{print $2}\'');
        const networkTx = await execPromise('cat /proc/net/dev | grep eth0 | awk \'{print $10}\'');

        res.json({
            cpu: parseFloat(cpuUsage.trim()) || 0,
            memory: parseFloat(memoryUsage.trim()) || 0,
            disk: parseFloat(diskUsage.trim()) || 0,
            network: {
                rx: parseInt(networkRx.trim()) || 0,
                tx: parseInt(networkTx.trim()) || 0
            },
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Error handling middleware
app.use((error, req, res, next) => {
    console.error('Error:', error);
    res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
    console.log(`OpenVPN API server running on port ${PORT}`);
}); 