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
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const redis = require('redis');

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

// Constants
const OUTLINE_SERVER_URL = process.env.OUTLINE_SERVER_URL || 'http://outline-server:8080';
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin';

// Redis client setup
const redisClient = redis.createClient({
    host: 'redis',
    port: 6379
});

redisClient.on('error', (err) => {
    console.error('Redis error:', err);
});

// Connect to Redis
redisClient.connect();

// Authentication middleware
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return res.status(401).json({ error: 'Access token required' });
    }

    jwt.verify(token, JWT_SECRET, (err, user) => {
        if (err) {
            return res.status(403).json({ error: 'Invalid token' });
        }
        req.user = user;
        next();
    });
};

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

// Helper functions
const makeOutlineRequest = async (method, endpoint, data = null) => {
    try {
        const config = {
            method,
            url: `${OUTLINE_SERVER_URL}${endpoint}`,
            headers: {
                'Content-Type': 'application/json',
            },
        };

        if (data) {
            config.data = data;
        }

        const response = await axios(config);
        return response.data;
    } catch (error) {
        console.error('Outline API error:', error.message);
        throw error;
    }
};

const generateQRCode = async (text) => {
    try {
        return await QRCode.toDataURL(text);
    } catch (error) {
        console.error('QR code generation error:', error);
        throw error;
    }
};

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

// Login endpoint
app.post('/api/login', async (req, res) => {
    try {
        const { password } = req.body;

        if (!password) {
            return res.status(400).json({ error: 'Password is required' });
        }

        // Simple password check (in production, use proper hashing)
        if (password !== ADMIN_PASSWORD) {
            return res.status(401).json({ error: 'Invalid password' });
        }

        const token = jwt.sign({ user: 'admin' }, JWT_SECRET, { expiresIn: '24h' });
        res.json({ token, expiresIn: '24h' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get server information
app.get('/api/server', authenticateToken, async (req, res) => {
    try {
        const serverInfo = await makeOutlineRequest('GET', '/server');
        res.json(serverInfo);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get server metrics
app.get('/api/metrics', authenticateToken, async (req, res) => {
    try {
        const metrics = await makeOutlineRequest('GET', '/metrics');
        res.json(metrics);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get all access keys
app.get('/api/access-keys', authenticateToken, async (req, res) => {
    try {
        const keys = await makeOutlineRequest('GET', '/access-keys');

        // Enhance keys with QR codes
        const enhancedKeys = await Promise.all(
            keys.accessKeys.map(async (key) => {
                try {
                    const qrCode = await generateQRCode(key.accessUrl);
                    return {
                        ...key,
                        qrCode,
                        created: new Date().toISOString()
                    };
                } catch (error) {
                    return {
                        ...key,
                        qrCode: null,
                        created: new Date().toISOString()
                    };
                }
            })
        );

        res.json({ accessKeys: enhancedKeys });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Create new access key
app.post('/api/access-keys', authenticateToken, async (req, res) => {
    try {
        const { name, limit } = req.body;

        // Create the key
        const newKey = await makeOutlineRequest('POST', '/access-keys');

        // Set name if provided
        if (name) {
            await makeOutlineRequest('PUT', `/access-keys/${newKey.id}/name`, { name });
        }

        // Set data limit if provided
        if (limit) {
            await makeOutlineRequest('PUT', `/access-keys/${newKey.id}/data-limit`, { limit: { bytes: limit } });
        }

        // Generate QR code
        const qrCode = await generateQRCode(newKey.accessUrl);

        res.json({
            ...newKey,
            name: name || `Key ${newKey.id}`,
            qrCode,
            created: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Delete access key
app.delete('/api/access-keys/:id', authenticateToken, async (req, res) => {
    try {
        const { id } = req.params;
        await makeOutlineRequest('DELETE', `/access-keys/${id}`);
        res.json({ success: true, message: 'Access key deleted' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Update access key name
app.put('/api/access-keys/:id/name', authenticateToken, async (req, res) => {
    try {
        const { id } = req.params;
        const { name } = req.body;

        if (!name) {
            return res.status(400).json({ error: 'Name is required' });
        }

        await makeOutlineRequest('PUT', `/access-keys/${id}/name`, { name });
        res.json({ success: true, message: 'Access key name updated' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Set data limit for access key
app.put('/api/access-keys/:id/data-limit', authenticateToken, async (req, res) => {
    try {
        const { id } = req.params;
        const { limit } = req.body;

        if (!limit) {
            return res.status(400).json({ error: 'Data limit is required' });
        }

        await makeOutlineRequest('PUT', `/access-keys/${id}/data-limit`, { limit: { bytes: limit } });
        res.json({ success: true, message: 'Data limit updated' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Remove data limit for access key
app.delete('/api/access-keys/:id/data-limit', authenticateToken, async (req, res) => {
    try {
        const { id } = req.params;
        await makeOutlineRequest('DELETE', `/access-keys/${id}/data-limit`);
        res.json({ success: true, message: 'Data limit removed' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get data usage for all keys
app.get('/api/metrics/transfer', authenticateToken, async (req, res) => {
    try {
        const transfer = await makeOutlineRequest('GET', '/metrics/transfer');
        res.json(transfer);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get server configuration
app.get('/api/server/config', authenticateToken, async (req, res) => {
    try {
        const config = await makeOutlineRequest('GET', '/server');
        res.json(config);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Update server name
app.put('/api/server/name', authenticateToken, async (req, res) => {
    try {
        const { name } = req.body;

        if (!name) {
            return res.status(400).json({ error: 'Server name is required' });
        }

        await makeOutlineRequest('PUT', '/name', { name });
        res.json({ success: true, message: 'Server name updated' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Update server hostname
app.put('/api/server/hostname', authenticateToken, async (req, res) => {
    try {
        const { hostname } = req.body;

        if (!hostname) {
            return res.status(400).json({ error: 'Hostname is required' });
        }

        await makeOutlineRequest('PUT', '/server/hostname-for-new-access-keys', { hostname });
        res.json({ success: true, message: 'Server hostname updated' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Update server port
app.put('/api/server/port', authenticateToken, async (req, res) => {
    try {
        const { port } = req.body;

        if (!port) {
            return res.status(400).json({ error: 'Port is required' });
        }

        await makeOutlineRequest('PUT', '/server/port-for-new-access-keys', { port });
        res.json({ success: true, message: 'Server port updated' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get access key by ID
app.get('/api/access-keys/:id', authenticateToken, async (req, res) => {
    try {
        const { id } = req.params;
        const keys = await makeOutlineRequest('GET', '/access-keys');
        const key = keys.accessKeys.find(k => k.id === id);

        if (!key) {
            return res.status(404).json({ error: 'Access key not found' });
        }

        const qrCode = await generateQRCode(key.accessUrl);
        res.json({
            ...key,
            qrCode,
            created: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get system status
app.get('/api/system/status', authenticateToken, async (req, res) => {
    try {
        const status = {
            server: 'running',
            uptime: process.uptime(),
            memory: process.memoryUsage(),
            timestamp: new Date().toISOString()
        };

        res.json(status);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Error handling middleware
app.use((error, req, res, next) => {
    console.error('Error:', error);
    res.status(500).json({ error: 'Internal server error' });
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