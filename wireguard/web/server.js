const express = require('express');
const path = require('path');
const fs = require('fs');
const { exec } = require('child_process');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const cookieParser = require('cookie-parser');
const session = require('express-session');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const bodyParser = require('body-parser');
const QRCode = require('qrcode');
const { Server } = require('socket.io');
const http = require('http');
const winston = require('winston');
const compression = require('compression');
const { body, validationResult } = require('express-validator');

// Configuration
const config = {
    port: process.env.PORT || 8080,
    jwtSecret: process.env.JWT_SECRET || 'your-super-secret-jwt-key-change-this',
    sessionSecret: process.env.SESSION_SECRET || 'your-super-secret-session-key-change-this',
    installDir: '/opt/wireguard-server',
    configDir: '/etc/wireguard',
    clientsDir: '/opt/wireguard-server/clients',
    logFile: '/var/log/wireguard-web.log'
};

// Setup logging
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.json()
    ),
    defaultMeta: { service: 'wireguard-web' },
    transports: [
        new winston.transports.File({ filename: config.logFile }),
        new winston.transports.Console({
            format: winston.format.simple()
        })
    ]
});

// Create Express app
const app = express();
const server = http.createServer(app);
const io = new Server(server);

// Security middleware
app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            styleSrc: ["'self'", "'unsafe-inline'", "https://cdn.jsdelivr.net"],
            scriptSrc: ["'self'", "'unsafe-inline'", "https://cdn.jsdelivr.net"],
            imgSrc: ["'self'", "data:", "https:"],
            connectSrc: ["'self'", "ws:", "wss:"]
        }
    }
}));

app.use(cors({
    origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:8080'],
    credentials: true
}));

app.use(compression());
app.use(morgan('combined', { stream: { write: message => logger.info(message.trim()) } }));
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(cookieParser());

// Rate limiting
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // limit each IP to 100 requests per windowMs
    message: 'Too many requests from this IP, please try again later.'
});
app.use('/api/', limiter);

// Session configuration
app.use(session({
    secret: config.sessionSecret,
    resave: false,
    saveUninitialized: false,
    cookie: {
        secure: process.env.NODE_ENV === 'production',
        httpOnly: true,
        maxAge: 24 * 60 * 60 * 1000 // 24 hours
    }
}));

// Serve static files
app.use(express.static(path.join(__dirname, 'public')));

// Default admin user (change this in production)
const adminUser = {
    username: 'admin',
    password: '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewqKKVdmjG5oQmO6' // 'admin' hashed
};

// Middleware to check authentication
const authenticateToken = (req, res, next) => {
    const token = req.cookies.token || req.headers.authorization?.split(' ')[1];

    if (!token) {
        return res.status(401).json({ error: 'Access denied. No token provided.' });
    }

    try {
        const decoded = jwt.verify(token, config.jwtSecret);
        req.user = decoded;
        next();
    } catch (ex) {
        res.status(400).json({ error: 'Invalid token.' });
    }
};

// Load environment configuration
function loadConfig() {
    try {
        const envFile = path.join(config.installDir, 'config.env');
        if (fs.existsSync(envFile)) {
            const envContent = fs.readFileSync(envFile, 'utf8');
            const envVars = {};
            envContent.split('\n').forEach(line => {
                const [key, value] = line.split('=');
                if (key && value) {
                    envVars[key] = value;
                }
            });
            return envVars;
        }
    } catch (error) {
        logger.error('Error loading configuration:', error);
    }
    return {};
}

// Execute shell command
function executeCommand(command) {
    return new Promise((resolve, reject) => {
        exec(command, (error, stdout, stderr) => {
            if (error) {
                reject(error);
            } else {
                resolve({ stdout, stderr });
            }
        });
    });
}

// Get server status
async function getServerStatus() {
    try {
        const wgStatus = await executeCommand('wg show wg0');
        const serviceStatus = await executeCommand('systemctl is-active wg-quick@wg0');
        const uptime = await executeCommand('uptime -p');

        return {
            isRunning: serviceStatus.stdout.trim() === 'active',
            uptime: uptime.stdout.trim(),
            peers: wgStatus.stdout.split('\n').filter(line => line.startsWith('peer:')).length,
            wgOutput: wgStatus.stdout
        };
    } catch (error) {
        logger.error('Error getting server status:', error);
        return { isRunning: false, uptime: 'Unknown', peers: 0, wgOutput: '' };
    }
}

// Get client list
function getClientList() {
    try {
        if (!fs.existsSync(config.clientsDir)) {
            return [];
        }

        const clients = [];
        const files = fs.readdirSync(config.clientsDir);

        files.forEach(file => {
            if (file.endsWith('.conf')) {
                const clientName = path.basename(file, '.conf');
                const configPath = path.join(config.clientsDir, file);
                const configContent = fs.readFileSync(configPath, 'utf8');

                // Extract client IP
                const addressMatch = configContent.match(/Address = ([^\\n]+)/);
                const address = addressMatch ? addressMatch[1] : 'Unknown';

                clients.push({
                    name: clientName,
                    address: address,
                    configFile: file,
                    qrCode: `${clientName}.png`
                });
            }
        });

        return clients;
    } catch (error) {
        logger.error('Error getting client list:', error);
        return [];
    }
}

// Authentication routes
app.post('/api/login', [
    body('username').isLength({ min: 1 }).trim(),
    body('password').isLength({ min: 1 })
], async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
    }

    try {
        const { username, password } = req.body;

        if (username === adminUser.username && await bcrypt.compare(password, adminUser.password)) {
            const token = jwt.sign(
                { username: username },
                config.jwtSecret,
                { expiresIn: '24h' }
            );

            res.cookie('token', token, { httpOnly: true, secure: process.env.NODE_ENV === 'production' });
            res.json({ success: true, token });
        } else {
            res.status(401).json({ error: 'Invalid credentials' });
        }
    } catch (error) {
        logger.error('Login error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});

app.post('/api/logout', (req, res) => {
    res.clearCookie('token');
    res.json({ success: true });
});

// Protected routes
app.get('/api/status', authenticateToken, async (req, res) => {
    try {
        const status = await getServerStatus();
        res.json(status);
    } catch (error) {
        logger.error('Error getting status:', error);
        res.status(500).json({ error: 'Failed to get server status' });
    }
});

app.get('/api/clients', authenticateToken, (req, res) => {
    try {
        const clients = getClientList();
        res.json(clients);
    } catch (error) {
        logger.error('Error getting clients:', error);
        res.status(500).json({ error: 'Failed to get client list' });
    }
});

app.post('/api/clients', authenticateToken, [
    body('name').isAlphanumeric().isLength({ min: 1, max: 50 }).trim()
], async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
    }

    try {
        const { name } = req.body;

        // Check if client already exists
        const clientPath = path.join(config.clientsDir, `${name}.conf`);
        if (fs.existsSync(clientPath)) {
            return res.status(400).json({ error: 'Client already exists' });
        }

        // Add client using management script
        const result = await executeCommand(`/usr/local/bin/wg-manage add-client ${name}`);

        if (result.stderr && result.stderr.includes('ERROR')) {
            return res.status(500).json({ error: result.stderr });
        }

        res.json({ success: true, message: `Client ${name} added successfully` });

        // Emit to connected clients
        io.emit('clientAdded', { name });

    } catch (error) {
        logger.error('Error adding client:', error);
        res.status(500).json({ error: 'Failed to add client' });
    }
});

app.delete('/api/clients/:name', authenticateToken, async (req, res) => {
    try {
        const { name } = req.params;

        // Remove client using management script
        const result = await executeCommand(`/usr/local/bin/wg-manage remove-client ${name}`);

        if (result.stderr && result.stderr.includes('ERROR')) {
            return res.status(500).json({ error: result.stderr });
        }

        res.json({ success: true, message: `Client ${name} removed successfully` });

        // Emit to connected clients
        io.emit('clientRemoved', { name });

    } catch (error) {
        logger.error('Error removing client:', error);
        res.status(500).json({ error: 'Failed to remove client' });
    }
});

app.get('/api/clients/:name/config', authenticateToken, (req, res) => {
    try {
        const { name } = req.params;
        const configPath = path.join(config.clientsDir, `${name}.conf`);

        if (!fs.existsSync(configPath)) {
            return res.status(404).json({ error: 'Client not found' });
        }

        const config = fs.readFileSync(configPath, 'utf8');
        res.json({ config });

    } catch (error) {
        logger.error('Error getting client config:', error);
        res.status(500).json({ error: 'Failed to get client configuration' });
    }
});

app.get('/api/clients/:name/qr', authenticateToken, async (req, res) => {
    try {
        const { name } = req.params;
        const configPath = path.join(config.clientsDir, `${name}.conf`);

        if (!fs.existsSync(configPath)) {
            return res.status(404).json({ error: 'Client not found' });
        }

        const config = fs.readFileSync(configPath, 'utf8');
        const qrCode = await QRCode.toDataURL(config);

        res.json({ qrCode });

    } catch (error) {
        logger.error('Error generating QR code:', error);
        res.status(500).json({ error: 'Failed to generate QR code' });
    }
});

app.post('/api/server/restart', authenticateToken, async (req, res) => {
    try {
        await executeCommand('systemctl restart wg-quick@wg0');
        res.json({ success: true, message: 'Server restarted successfully' });

        // Emit to connected clients
        io.emit('serverRestarted');

    } catch (error) {
        logger.error('Error restarting server:', error);
        res.status(500).json({ error: 'Failed to restart server' });
    }
});

app.get('/api/logs', authenticateToken, async (req, res) => {
    try {
        const lines = req.query.lines || 50;
        const result = await executeCommand(`journalctl -u wg-quick@wg0 -n ${lines} --no-pager`);
        res.json({ logs: result.stdout });

    } catch (error) {
        logger.error('Error getting logs:', error);
        res.status(500).json({ error: 'Failed to get logs' });
    }
});

// Socket.IO for real-time updates
io.on('connection', (socket) => {
    logger.info('Client connected to WebSocket');

    socket.on('disconnect', () => {
        logger.info('Client disconnected from WebSocket');
    });

    // Send real-time status updates
    const statusInterval = setInterval(async () => {
        try {
            const status = await getServerStatus();
            socket.emit('statusUpdate', status);
        } catch (error) {
            logger.error('Error sending status update:', error);
        }
    }, 5000); // Every 5 seconds

    socket.on('disconnect', () => {
        clearInterval(statusInterval);
    });
});

// Serve the main HTML file
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Error handling middleware
app.use((err, req, res, next) => {
    logger.error('Unhandled error:', err);
    res.status(500).json({ error: 'Internal server error' });
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({ error: 'Not found' });
});

// Start server
server.listen(config.port, () => {
    logger.info(`WireGuard Web Interface running on port ${config.port}`);
    console.log(`Server running on http://localhost:${config.port}`);
    console.log(`Default credentials: admin / admin`);
});

// Graceful shutdown
process.on('SIGINT', () => {
    logger.info('Shutting down gracefully...');
    server.close(() => {
        logger.info('Server closed');
        process.exit(0);
    });
});

module.exports = app; 