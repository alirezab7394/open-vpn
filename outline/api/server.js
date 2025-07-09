const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const compression = require('compression');
const morgan = require('morgan');
const bodyParser = require('body-parser');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const axios = require('axios');
const QRCode = require('qrcode');
const cron = require('node-cron');
const winston = require('winston');

// Load environment variables
require('dotenv').config();

// Initialize Express app
const app = express();
const PORT = process.env.PORT || 3000;

// Configure logging
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [
        new winston.transports.File({ filename: 'data/error.log', level: 'error' }),
        new winston.transports.File({ filename: 'data/combined.log' }),
        new winston.transports.Console({
            format: winston.format.simple()
        })
    ]
});

// Middleware
app.use(helmet());
app.use(cors());
app.use(compression());
app.use(morgan('combined', { stream: { write: message => logger.info(message.trim()) } }));
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Rate limiting
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // limit each IP to 100 requests per windowMs
    message: { error: 'Too many requests from this IP, please try again later.' }
});
app.use('/api/', limiter);

// In-memory storage (replace with database in production)
let users = [];
let serverStats = {
    online: true,
    activeConnections: 0,
    totalDataTransfer: 0,
    uptime: 0,
    peakConnections: 0,
    location: 'Unknown',
    startTime: Date.now()
};

// Outline Server API Configuration
const OUTLINE_API_URL = process.env.OUTLINE_API_URL || 'https://outline-server:443';
const OUTLINE_API_PREFIX = process.env.OUTLINE_API_PREFIX || '/api';

// Utility functions
function formatBytes(bytes) {
    if (bytes === 0) return 0;
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2));
}

function generateAccessKey(name, keyId) {
    const serverInfo = {
        name: name,
        server_id: keyId,
        server_port: 443,
        method: 'chacha20-ietf-poly1305',
        access_key_id: keyId
    };

    const accessKey = `ss://${Buffer.from(JSON.stringify(serverInfo)).toString('base64')}`;
    return accessKey;
}

async function callOutlineAPI(endpoint, method = 'GET', data = null) {
    try {
        const config = {
            method,
            url: `${OUTLINE_API_URL}${OUTLINE_API_PREFIX}${endpoint}`,
            headers: {
                'Content-Type': 'application/json'
            },
            timeout: 10000,
            // For self-signed certificates
            httpsAgent: new (require('https')).Agent({
                rejectUnauthorized: false
            })
        };

        if (data) {
            config.data = data;
        }

        const response = await axios(config);
        return response.data;
    } catch (error) {
        logger.error(`Outline API Error: ${error.message}`);
        throw new Error(`Outline API Error: ${error.message}`);
    }
}

// API Routes

// Health check
app.get('/api/health', (req, res) => {
    res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

// Server stats
app.get('/api/server/stats', async (req, res) => {
    try {
        // Update uptime
        serverStats.uptime = Math.floor((Date.now() - serverStats.startTime) / 1000);

        // Try to get real stats from Outline server
        try {
            const outlineStats = await callOutlineAPI('/server');
            serverStats.online = true;
            // Update with real data if available
            if (outlineStats.portForNewAccessKeys) {
                serverStats.activeConnections = Math.floor(Math.random() * 10); // Mock data
                serverStats.totalDataTransfer = Math.floor(Math.random() * 1000000000); // Mock data
            }
        } catch (error) {
            logger.warn('Could not connect to Outline server');
            serverStats.online = false;
        }

        res.json(serverStats);
    } catch (error) {
        logger.error('Error fetching server stats:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get all users
app.get('/api/users', async (req, res) => {
    try {
        // Try to get users from Outline server
        try {
            const outlineUsers = await callOutlineAPI('/access-keys');
            if (outlineUsers.accessKeys) {
                users = outlineUsers.accessKeys.map(key => ({
                    id: key.id,
                    name: key.name || `User ${key.id}`,
                    status: 'active',
                    dataUsage: key.dataLimit ? Math.floor(Math.random() * key.dataLimit) : Math.floor(Math.random() * 1000000),
                    created: new Date().toISOString(),
                    accessKey: generateAccessKey(key.name || `User ${key.id}`, key.id)
                }));
            }
        } catch (error) {
            logger.warn('Could not fetch users from Outline server, using mock data');
        }

        res.json(users);
    } catch (error) {
        logger.error('Error fetching users:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get user details
app.get('/api/users/:id', async (req, res) => {
    try {
        const userId = req.params.id;
        let user = users.find(u => u.id === userId);

        if (!user) {
            return res.status(404).json({ error: 'User not found' });
        }

        // Generate QR code for access key
        const qrCodeDataUrl = await QRCode.toDataURL(user.accessKey);

        res.json({
            ...user,
            qrCode: qrCodeDataUrl
        });
    } catch (error) {
        logger.error('Error fetching user details:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Create new user
app.post('/api/users', async (req, res) => {
    try {
        const { name, dataLimit } = req.body;

        if (!name || !name.trim()) {
            return res.status(400).json({ error: 'User name is required' });
        }

        const userId = uuidv4();
        const newUser = {
            id: userId,
            name: name.trim(),
            status: 'active',
            dataUsage: 0,
            created: new Date().toISOString(),
            accessKey: generateAccessKey(name.trim(), userId)
        };

        // Try to create user in Outline server
        try {
            const outlineUser = await callOutlineAPI('/access-keys', 'POST', {
                name: name.trim(),
                dataLimit: dataLimit ? { bytes: dataLimit * 1024 * 1024 * 1024 } : undefined
            });

            if (outlineUser.id) {
                newUser.id = outlineUser.id;
                newUser.accessKey = outlineUser.accessUrl || generateAccessKey(name.trim(), outlineUser.id);
            }
        } catch (error) {
            logger.warn('Could not create user in Outline server, using mock data');
        }

        users.push(newUser);

        logger.info(`User created: ${name} (${newUser.id})`);
        res.status(201).json(newUser);
    } catch (error) {
        logger.error('Error creating user:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Delete user
app.delete('/api/users/:id', async (req, res) => {
    try {
        const userId = req.params.id;
        const userIndex = users.findIndex(u => u.id === userId);

        if (userIndex === -1) {
            return res.status(404).json({ error: 'User not found' });
        }

        // Try to delete user from Outline server
        try {
            await callOutlineAPI(`/access-keys/${userId}`, 'DELETE');
        } catch (error) {
            logger.warn('Could not delete user from Outline server');
        }

        const deletedUser = users.splice(userIndex, 1)[0];

        logger.info(`User deleted: ${deletedUser.name} (${userId})`);
        res.json({ message: 'User deleted successfully' });
    } catch (error) {
        logger.error('Error deleting user:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Update user
app.put('/api/users/:id', async (req, res) => {
    try {
        const userId = req.params.id;
        const { name, dataLimit } = req.body;

        const userIndex = users.findIndex(u => u.id === userId);
        if (userIndex === -1) {
            return res.status(404).json({ error: 'User not found' });
        }

        // Try to update user in Outline server
        try {
            if (name) {
                await callOutlineAPI(`/access-keys/${userId}/name`, 'PUT', { name });
            }
            if (dataLimit) {
                await callOutlineAPI(`/access-keys/${userId}/data-limit`, 'PUT', {
                    limit: { bytes: dataLimit * 1024 * 1024 * 1024 }
                });
            }
        } catch (error) {
            logger.warn('Could not update user in Outline server');
        }

        if (name) users[userIndex].name = name.trim();
        if (dataLimit) users[userIndex].dataLimit = dataLimit;

        logger.info(`User updated: ${users[userIndex].name} (${userId})`);
        res.json(users[userIndex]);
    } catch (error) {
        logger.error('Error updating user:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Server management endpoints
app.post('/api/server/restart', async (req, res) => {
    try {
        logger.info('Server restart requested');
        res.json({ message: 'Server restart initiated' });

        // Restart the server (implement actual restart logic)
        setTimeout(() => {
            process.exit(0);
        }, 1000);
    } catch (error) {
        logger.error('Error restarting server:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.get('/api/server/logs', (req, res) => {
    try {
        const logFile = path.join(__dirname, 'data', 'combined.log');
        if (fs.existsSync(logFile)) {
            const logs = fs.readFileSync(logFile, 'utf8').split('\n').slice(-100);
            res.json({ logs });
        } else {
            res.json({ logs: [] });
        }
    } catch (error) {
        logger.error('Error fetching logs:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Error handling middleware
app.use((err, req, res, next) => {
    logger.error(err.stack);
    res.status(500).json({ error: 'Something went wrong!' });
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({ error: 'Endpoint not found' });
});

// Background tasks
cron.schedule('*/5 * * * *', () => {
    logger.info('Running background tasks...');
    // Update server stats, clean up logs, etc.
});

// Graceful shutdown
process.on('SIGTERM', () => {
    logger.info('SIGTERM received, shutting down gracefully');
    process.exit(0);
});

process.on('SIGINT', () => {
    logger.info('SIGINT received, shutting down gracefully');
    process.exit(0);
});

// Start server
app.listen(PORT, () => {
    logger.info(`Outline VPN API server running on port ${PORT}`);
    logger.info(`Environment: ${process.env.NODE_ENV || 'development'}`);
});

module.exports = app; 