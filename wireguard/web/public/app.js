// WireGuard Web Interface Client Application
class WireGuardApp {
    constructor() {
        this.socket = null;
        this.authToken = null;
        this.isAuthenticated = false;
        this.clients = [];
        this.serverStatus = {};

        this.init();
    }

    init() {
        this.setupEventListeners();
        this.checkAuthStatus();
    }

    setupEventListeners() {
        // Login form
        document.getElementById('login-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.handleLogin();
        });

        // Logout button
        document.getElementById('logout-btn').addEventListener('click', () => {
            this.handleLogout();
        });

        // Add client form
        document.getElementById('add-client-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.handleAddClient();
        });

        // Server actions
        document.getElementById('restart-server').addEventListener('click', () => {
            this.restartServer();
        });

        document.getElementById('refresh-status').addEventListener('click', () => {
            this.refreshServerStatus();
        });

        document.getElementById('refresh-logs').addEventListener('click', () => {
            this.refreshLogs();
        });

        // Tab switches
        document.getElementById('logs-tab').addEventListener('click', () => {
            setTimeout(() => this.refreshLogs(), 100);
        });

        document.getElementById('server-tab').addEventListener('click', () => {
            setTimeout(() => this.refreshServerStatus(), 100);
        });
    }

    checkAuthStatus() {
        const token = this.getCookie('token');
        if (token) {
            this.authToken = token;
            this.isAuthenticated = true;
            this.showDashboard();
            this.connectWebSocket();
            this.loadInitialData();
        } else {
            this.showLogin();
        }
    }

    async handleLogin() {
        const username = document.getElementById('username').value;
        const password = document.getElementById('password').value;
        const errorDiv = document.getElementById('login-error');

        try {
            this.showLoading();

            const response = await fetch('/api/login', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ username, password }),
            });

            const data = await response.json();

            if (response.ok) {
                this.authToken = data.token;
                this.isAuthenticated = true;
                this.showDashboard();
                this.connectWebSocket();
                this.loadInitialData();
                this.showToast('Login successful!', 'success');
            } else {
                errorDiv.textContent = data.error || 'Login failed';
                errorDiv.style.display = 'block';
            }
        } catch (error) {
            errorDiv.textContent = 'Connection error. Please try again.';
            errorDiv.style.display = 'block';
        } finally {
            this.hideLoading();
        }
    }

    async handleLogout() {
        try {
            await fetch('/api/logout', {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${this.authToken}`,
                },
            });
        } catch (error) {
            console.error('Logout error:', error);
        }

        this.authToken = null;
        this.isAuthenticated = false;
        this.disconnectWebSocket();
        this.showLogin();
        this.showToast('Logged out successfully', 'info');
    }

    async handleAddClient() {
        const clientName = document.getElementById('client-name').value.trim();

        if (!clientName) {
            this.showToast('Please enter a client name', 'error');
            return;
        }

        try {
            this.showLoading();

            const response = await fetch('/api/clients', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${this.authToken}`,
                },
                body: JSON.stringify({ name: clientName }),
            });

            const data = await response.json();

            if (response.ok) {
                this.showToast(`Client "${clientName}" added successfully!`, 'success');
                document.getElementById('client-name').value = '';
                bootstrap.Modal.getInstance(document.getElementById('add-client-modal')).hide();
                this.loadClients();
            } else {
                this.showToast(data.error || 'Failed to add client', 'error');
            }
        } catch (error) {
            this.showToast('Connection error. Please try again.', 'error');
        } finally {
            this.hideLoading();
        }
    }

    async removeClient(clientName) {
        if (!confirm(`Are you sure you want to remove client "${clientName}"?`)) {
            return;
        }

        try {
            this.showLoading();

            const response = await fetch(`/api/clients/${clientName}`, {
                method: 'DELETE',
                headers: {
                    'Authorization': `Bearer ${this.authToken}`,
                },
            });

            const data = await response.json();

            if (response.ok) {
                this.showToast(`Client "${clientName}" removed successfully!`, 'success');
                this.loadClients();
            } else {
                this.showToast(data.error || 'Failed to remove client', 'error');
            }
        } catch (error) {
            this.showToast('Connection error. Please try again.', 'error');
        } finally {
            this.hideLoading();
        }
    }

    async showClientConfig(clientName) {
        try {
            this.showLoading();

            const [configResponse, qrResponse] = await Promise.all([
                fetch(`/api/clients/${clientName}/config`, {
                    headers: { 'Authorization': `Bearer ${this.authToken}` },
                }),
                fetch(`/api/clients/${clientName}/qr`, {
                    headers: { 'Authorization': `Bearer ${this.authToken}` },
                })
            ]);

            const configData = await configResponse.json();
            const qrData = await qrResponse.json();

            if (configResponse.ok && qrResponse.ok) {
                document.getElementById('client-config-text').value = configData.config;
                document.getElementById('qr-code-image').src = qrData.qrCode;

                // Setup download button
                const downloadBtn = document.getElementById('download-config');
                downloadBtn.onclick = () => this.downloadConfig(clientName, configData.config);

                const modal = new bootstrap.Modal(document.getElementById('client-config-modal'));
                modal.show();
            } else {
                this.showToast('Failed to load client configuration', 'error');
            }
        } catch (error) {
            this.showToast('Connection error. Please try again.', 'error');
        } finally {
            this.hideLoading();
        }
    }

    downloadConfig(clientName, config) {
        const blob = new Blob([config], { type: 'text/plain' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${clientName}.conf`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        window.URL.revokeObjectURL(url);
    }

    async restartServer() {
        if (!confirm('Are you sure you want to restart the WireGuard server?')) {
            return;
        }

        try {
            this.showLoading();

            const response = await fetch('/api/server/restart', {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${this.authToken}`,
                },
            });

            const data = await response.json();

            if (response.ok) {
                this.showToast('Server restarted successfully!', 'success');
                setTimeout(() => this.refreshServerStatus(), 2000);
            } else {
                this.showToast(data.error || 'Failed to restart server', 'error');
            }
        } catch (error) {
            this.showToast('Connection error. Please try again.', 'error');
        } finally {
            this.hideLoading();
        }
    }

    async loadClients() {
        try {
            const response = await fetch('/api/clients', {
                headers: {
                    'Authorization': `Bearer ${this.authToken}`,
                },
            });

            const clients = await response.json();

            if (response.ok) {
                this.clients = clients;
                this.renderClientsTable();
            } else {
                this.showToast('Failed to load clients', 'error');
            }
        } catch (error) {
            this.showToast('Connection error. Please try again.', 'error');
        }
    }

    async loadServerStatus() {
        try {
            const response = await fetch('/api/status', {
                headers: {
                    'Authorization': `Bearer ${this.authToken}`,
                },
            });

            const status = await response.json();

            if (response.ok) {
                this.serverStatus = status;
                this.updateStatusCards();
                this.updateServerTab();
            }
        } catch (error) {
            console.error('Error loading server status:', error);
        }
    }

    async refreshServerStatus() {
        this.showLoading();
        await this.loadServerStatus();
        this.hideLoading();
    }

    async refreshLogs() {
        try {
            this.showLoading();

            const response = await fetch('/api/logs', {
                headers: {
                    'Authorization': `Bearer ${this.authToken}`,
                },
            });

            const data = await response.json();

            if (response.ok) {
                document.getElementById('system-logs').textContent = data.logs;
            } else {
                this.showToast('Failed to load logs', 'error');
            }
        } catch (error) {
            this.showToast('Connection error. Please try again.', 'error');
        } finally {
            this.hideLoading();
        }
    }

    renderClientsTable() {
        const tbody = document.getElementById('clients-table');

        if (this.clients.length === 0) {
            tbody.innerHTML = '<tr><td colspan="4" class="text-center text-muted">No clients found</td></tr>';
            return;
        }

        tbody.innerHTML = this.clients.map(client => `
            <tr>
                <td>
                    <i class="fas fa-user me-2"></i>
                    <strong>${client.name}</strong>
                </td>
                <td>
                    <code>${client.address}</code>
                </td>
                <td>
                    <span class="badge bg-success">
                        <i class="fas fa-circle me-1"></i>
                        Connected
                    </span>
                </td>
                <td>
                    <div class="btn-group" role="group">
                        <button class="btn btn-sm btn-outline-primary" onclick="app.showClientConfig('${client.name}')">
                            <i class="fas fa-qrcode me-1"></i>Config
                        </button>
                        <button class="btn btn-sm btn-outline-danger" onclick="app.removeClient('${client.name}')">
                            <i class="fas fa-trash me-1"></i>Remove
                        </button>
                    </div>
                </td>
            </tr>
        `).join('');
    }

    updateStatusCards() {
        const status = this.serverStatus;

        document.getElementById('server-status').textContent = status.isRunning ? 'Running' : 'Stopped';
        document.getElementById('connected-clients').textContent = status.peers || 0;
        document.getElementById('server-uptime').textContent = status.uptime || 'Unknown';

        // Update status card colors
        const statusCard = document.getElementById('server-status').closest('.card');
        statusCard.className = `card text-white ${status.isRunning ? 'bg-success' : 'bg-danger'}`;
    }

    updateServerTab() {
        const status = this.serverStatus;
        document.getElementById('wireguard-status').textContent = status.wgOutput || 'No data available';
    }

    connectWebSocket() {
        this.socket = io();

        this.socket.on('connect', () => {
            console.log('Connected to WebSocket');
            this.showConnectionStatus('connected');
        });

        this.socket.on('disconnect', () => {
            console.log('Disconnected from WebSocket');
            this.showConnectionStatus('disconnected');
        });

        this.socket.on('statusUpdate', (status) => {
            this.serverStatus = status;
            this.updateStatusCards();
            this.updateServerTab();
        });

        this.socket.on('clientAdded', (data) => {
            this.showToast(`Client "${data.name}" was added`, 'success');
            this.loadClients();
        });

        this.socket.on('clientRemoved', (data) => {
            this.showToast(`Client "${data.name}" was removed`, 'info');
            this.loadClients();
        });

        this.socket.on('serverRestarted', () => {
            this.showToast('Server was restarted', 'info');
            this.loadServerStatus();
        });
    }

    disconnectWebSocket() {
        if (this.socket) {
            this.socket.disconnect();
            this.socket = null;
        }
    }

    showConnectionStatus(status) {
        let statusEl = document.getElementById('connection-status');

        if (!statusEl) {
            statusEl = document.createElement('div');
            statusEl.id = 'connection-status';
            statusEl.className = 'connection-status';
            document.body.appendChild(statusEl);
        }

        statusEl.className = `connection-status ${status}`;
        statusEl.innerHTML = `
            <i class="fas fa-circle me-1"></i>
            ${status === 'connected' ? 'Connected' : 'Disconnected'}
        `;

        setTimeout(() => {
            statusEl.style.display = 'none';
        }, 3000);
    }

    showLogin() {
        document.getElementById('login-section').style.display = 'block';
        document.getElementById('dashboard').style.display = 'none';
        document.getElementById('user-info').style.display = 'none';
        document.getElementById('logout-btn').style.display = 'none';
        document.getElementById('login-error').style.display = 'none';
    }

    showDashboard() {
        document.getElementById('login-section').style.display = 'none';
        document.getElementById('dashboard').style.display = 'block';
        document.getElementById('user-info').style.display = 'block';
        document.getElementById('logout-btn').style.display = 'block';
    }

    showLoading() {
        document.getElementById('loading-overlay').style.display = 'flex';
    }

    hideLoading() {
        document.getElementById('loading-overlay').style.display = 'none';
    }

    showToast(message, type = 'info') {
        const toast = document.getElementById('toast');
        const toastMessage = document.getElementById('toast-message');
        const toastHeader = toast.querySelector('.toast-header');

        // Update toast appearance based on type
        let iconClass = 'fas fa-info-circle';
        let headerClass = 'text-primary';

        switch (type) {
            case 'success':
                iconClass = 'fas fa-check-circle';
                headerClass = 'text-success';
                break;
            case 'error':
                iconClass = 'fas fa-exclamation-circle';
                headerClass = 'text-danger';
                break;
            case 'warning':
                iconClass = 'fas fa-exclamation-triangle';
                headerClass = 'text-warning';
                break;
        }

        toastHeader.querySelector('i').className = `${iconClass} me-2`;
        toastHeader.querySelector('i').classList.add(headerClass);
        toastMessage.textContent = message;

        const bsToast = new bootstrap.Toast(toast);
        bsToast.show();
    }

    loadInitialData() {
        this.loadClients();
        this.loadServerStatus();
    }

    getCookie(name) {
        const value = `; ${document.cookie}`;
        const parts = value.split(`; ${name}=`);
        if (parts.length === 2) return parts.pop().split(';').shift();
        return null;
    }
}

// Initialize the application when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.app = new WireGuardApp();
});

// Handle page visibility changes
document.addEventListener('visibilitychange', () => {
    if (!document.hidden && window.app && window.app.isAuthenticated) {
        window.app.loadInitialData();
    }
});

// Handle connection errors
window.addEventListener('online', () => {
    if (window.app && window.app.isAuthenticated) {
        window.app.showToast('Connection restored', 'success');
        window.app.loadInitialData();
    }
});

window.addEventListener('offline', () => {
    if (window.app) {
        window.app.showToast('Connection lost', 'warning');
    }
}); 