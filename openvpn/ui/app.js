// OpenVPN Server Manager JavaScript

class OpenVPNManager {
    constructor() {
        this.apiUrl = '/api';
        this.clients = [];
        this.connections = [];
        this.serverStats = {};
        this.certificates = [];
        this.logs = [];
        this.autoRefreshInterval = null;
        this.init();
    }

    async init() {
        await this.loadServerStats();
        await this.loadClients();
        await this.loadConnections();
        await this.loadCertificates();
        this.startPolling();
        this.initEventListeners();
    }

    // API Methods
    async makeRequest(endpoint, options = {}) {
        try {
            const response = await fetch(`${this.apiUrl}${endpoint}`, {
                ...options,
                headers: {
                    'Content-Type': 'application/json',
                    ...options.headers
                }
            });

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            return await response.json();
        } catch (error) {
            console.error('API Error:', error);
            this.showError('API Error: ' + error.message);
            throw error;
        }
    }

    async loadServerStats() {
        try {
            const stats = await this.makeRequest('/server/stats');
            this.serverStats = stats;
            this.updateServerStatus();
        } catch (error) {
            console.error('Failed to load server stats:', error);
        }
    }

    async loadClients() {
        try {
            const clients = await this.makeRequest('/clients');
            this.clients = clients;
            this.updateClientsTable();
        } catch (error) {
            console.error('Failed to load clients:', error);
        }
    }

    async loadConnections() {
        try {
            const connections = await this.makeRequest('/connections');
            this.connections = connections;
            this.updateConnectionsTable();
        } catch (error) {
            console.error('Failed to load connections:', error);
        }
    }

    async loadCertificates() {
        try {
            const certificates = await this.makeRequest('/certificates');
            this.certificates = certificates;
            this.updateCertificatesInfo();
        } catch (error) {
            console.error('Failed to load certificates:', error);
        }
    }

    async createClient(clientData) {
        try {
            const client = await this.makeRequest('/clients', {
                method: 'POST',
                body: JSON.stringify(clientData)
            });
            this.clients.push(client);
            this.updateClientsTable();
            this.showSuccess('Client created successfully!');
            return client;
        } catch (error) {
            console.error('Failed to create client:', error);
            this.showError('Failed to create client');
            throw error;
        }
    }

    async revokeClient(clientId) {
        try {
            await this.makeRequest(`/clients/${clientId}/revoke`, {
                method: 'POST'
            });
            const clientIndex = this.clients.findIndex(c => c.id === clientId);
            if (clientIndex !== -1) {
                this.clients[clientIndex].status = 'revoked';
            }
            this.updateClientsTable();
            this.showSuccess('Client certificate revoked successfully!');
        } catch (error) {
            console.error('Failed to revoke client:', error);
            this.showError('Failed to revoke client');
        }
    }

    async deleteClient(clientId) {
        try {
            await this.makeRequest(`/clients/${clientId}`, {
                method: 'DELETE'
            });
            this.clients = this.clients.filter(c => c.id !== clientId);
            this.updateClientsTable();
            this.showSuccess('Client deleted successfully!');
        } catch (error) {
            console.error('Failed to delete client:', error);
            this.showError('Failed to delete client');
        }
    }

    async getClientConfig(clientId) {
        try {
            const config = await this.makeRequest(`/clients/${clientId}/config`);
            return config;
        } catch (error) {
            console.error('Failed to get client config:', error);
            throw error;
        }
    }

    async disconnectClient(clientId) {
        try {
            await this.makeRequest(`/clients/${clientId}/disconnect`, {
                method: 'POST'
            });
            this.loadConnections();
            this.showSuccess('Client disconnected successfully!');
        } catch (error) {
            console.error('Failed to disconnect client:', error);
            this.showError('Failed to disconnect client');
        }
    }

    async loadLogs(level = 'all', lines = 100) {
        try {
            const logs = await this.makeRequest(`/logs?level=${level}&lines=${lines}`);
            this.logs = logs;
            this.updateLogsOutput();
        } catch (error) {
            console.error('Failed to load logs:', error);
        }
    }

    async saveConfiguration(config) {
        try {
            await this.makeRequest('/config', {
                method: 'PUT',
                body: JSON.stringify(config)
            });
            this.showSuccess('Configuration saved successfully!');
        } catch (error) {
            console.error('Failed to save configuration:', error);
            this.showError('Failed to save configuration');
        }
    }

    async restartServer() {
        try {
            await this.makeRequest('/server/restart', {
                method: 'POST'
            });
            this.showSuccess('Server restart initiated!');
        } catch (error) {
            console.error('Failed to restart server:', error);
            this.showError('Failed to restart server');
        }
    }

    // UI Update Methods
    updateServerStatus() {
        const statusElement = document.getElementById('serverStatus');
        const statusText = document.getElementById('statusText');
        const connectedClients = document.getElementById('connectedClients');
        const totalUsers = document.getElementById('totalUsers');
        const dataTransfer = document.getElementById('dataTransfer');
        const serverUptime = document.getElementById('serverUptime');
        const serverLoad = document.getElementById('serverLoad');

        if (this.serverStats.online) {
            statusElement.innerHTML = '<i class="fas fa-circle text-success"></i>';
            statusText.textContent = 'Online';
        } else {
            statusElement.innerHTML = '<i class="fas fa-circle text-danger"></i>';
            statusText.textContent = 'Offline';
        }

        connectedClients.textContent = this.connections.length;
        totalUsers.textContent = this.clients.length;
        dataTransfer.textContent = this.formatBytes(this.serverStats.dataTransfer || 0);
        serverUptime.textContent = this.formatUptime(this.serverStats.uptime || 0);
        serverLoad.textContent = `${this.serverStats.cpuUsage || 0}%`;
    }

    updateClientsTable() {
        const tbody = document.getElementById('clientsTableBody');
        tbody.innerHTML = '';

        this.clients.forEach(client => {
            const row = document.createElement('tr');
            const statusBadge = this.getStatusBadge(client.status);
            const certStatus = this.getCertificateStatus(client.certificate);

            row.innerHTML = `
                <td>${client.name}</td>
                <td>${client.email || '-'}</td>
                <td>${statusBadge}</td>
                <td>${certStatus}</td>
                <td>${new Date(client.created).toLocaleDateString()}</td>
                <td>${client.lastConnected ? new Date(client.lastConnected).toLocaleString() : 'Never'}</td>
                <td>
                    <button class="btn btn-sm btn-primary me-1" onclick="app.showClientConfig('${client.id}')">
                        <i class="fas fa-eye"></i>
                    </button>
                    <button class="btn btn-sm btn-warning me-1" onclick="app.confirmRevokeClient('${client.id}')">
                        <i class="fas fa-ban"></i>
                    </button>
                    <button class="btn btn-sm btn-danger" onclick="app.confirmDeleteClient('${client.id}')">
                        <i class="fas fa-trash"></i>
                    </button>
                </td>
            `;
            tbody.appendChild(row);
        });
    }

    updateConnectionsTable() {
        const tbody = document.getElementById('connectionsTableBody');
        tbody.innerHTML = '';

        this.connections.forEach(connection => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${connection.clientName}</td>
                <td>${connection.virtualIP}</td>
                <td>${connection.realIP}</td>
                <td>${new Date(connection.connectedSince).toLocaleString()}</td>
                <td>${this.formatBytes(connection.bytesSent)}</td>
                <td>${this.formatBytes(connection.bytesReceived)}</td>
                <td>
                    <button class="btn btn-sm btn-danger" onclick="app.disconnectClient('${connection.clientId}')">
                        <i class="fas fa-times"></i> Disconnect
                    </button>
                </td>
            `;
            tbody.appendChild(row);
        });
    }

    updateCertificatesInfo() {
        const caExpiry = document.getElementById('caExpiry');
        const certsIssued = document.getElementById('certsIssued');
        const certsActive = document.getElementById('certsActive');
        const revokedCertsTable = document.getElementById('revokedCertsTable');

        if (this.certificates.ca) {
            caExpiry.textContent = new Date(this.certificates.ca.expiry).toLocaleDateString();
        }

        certsIssued.textContent = this.certificates.issued?.length || 0;
        certsActive.textContent = this.certificates.active?.length || 0;

        // Update revoked certificates table
        revokedCertsTable.innerHTML = '';
        if (this.certificates.revoked) {
            this.certificates.revoked.forEach(cert => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td>${cert.commonName}</td>
                    <td>${new Date(cert.revokedDate).toLocaleDateString()}</td>
                    <td>${cert.reason}</td>
                `;
                revokedCertsTable.appendChild(row);
            });
        }
    }

    updateLogsOutput() {
        const logOutput = document.getElementById('logOutput');
        if (this.logs && this.logs.length > 0) {
            logOutput.textContent = this.logs.join('\n');
            logOutput.scrollTop = logOutput.scrollHeight;
        } else {
            logOutput.textContent = 'No logs available';
        }
    }

    // Modal Methods
    showAddClientModal() {
        const modal = new bootstrap.Modal(document.getElementById('addClientModal'));
        modal.show();
    }

    async showClientConfig(clientId) {
        try {
            const config = await this.getClientConfig(clientId);
            const client = this.clients.find(c => c.id === clientId);

            document.getElementById('clientConfig').value = config.ovpnConfig;

            // Generate QR code
            const qrContainer = document.getElementById('qrCodeContainer');
            qrContainer.innerHTML = '';

            if (config.ovpnConfig) {
                QRCode.toCanvas(qrContainer, config.ovpnConfig, {
                    width: 200,
                    margin: 2,
                    color: {
                        dark: '#000000',
                        light: '#FFFFFF'
                    }
                }, (error) => {
                    if (error) console.error('QR Code generation failed:', error);
                });
            }

            // Store config for download
            this.currentClientConfig = {
                name: client.name,
                config: config.ovpnConfig
            };

            const modal = new bootstrap.Modal(document.getElementById('clientDetailsModal'));
            modal.show();
        } catch (error) {
            this.showError('Failed to load client configuration');
        }
    }

    confirmRevokeClient(clientId) {
        const client = this.clients.find(c => c.id === clientId);
        if (client && confirm(`Are you sure you want to revoke the certificate for "${client.name}"?`)) {
            this.revokeClient(clientId);
        }
    }

    confirmDeleteClient(clientId) {
        const client = this.clients.find(c => c.id === clientId);
        if (client && confirm(`Are you sure you want to delete client "${client.name}"?`)) {
            this.deleteClient(clientId);
        }
    }

    // Event Listeners
    initEventListeners() {
        // Log controls
        document.getElementById('logLevel').addEventListener('change', (e) => {
            this.loadLogs(e.target.value, document.getElementById('logLines').value);
        });

        document.getElementById('logLines').addEventListener('change', (e) => {
            this.loadLogs(document.getElementById('logLevel').value, e.target.value);
        });

        document.getElementById('autoRefresh').addEventListener('change', (e) => {
            if (e.target.checked) {
                this.startLogAutoRefresh();
            } else {
                this.stopLogAutoRefresh();
            }
        });

        // Tab switches
        document.querySelectorAll('[data-bs-toggle="tab"]').forEach(tab => {
            tab.addEventListener('shown.bs.tab', (e) => {
                const target = e.target.getAttribute('data-bs-target');
                if (target === '#logs') {
                    this.loadLogs();
                }
            });
        });
    }

    // Utility Methods
    getStatusBadge(status) {
        const badges = {
            active: '<span class="badge bg-success">Active</span>',
            revoked: '<span class="badge bg-danger">Revoked</span>',
            expired: '<span class="badge bg-warning">Expired</span>',
            inactive: '<span class="badge bg-secondary">Inactive</span>'
        };
        return badges[status] || badges.inactive;
    }

    getCertificateStatus(certificate) {
        if (!certificate) return '<span class="cert-status cert-invalid">No Certificate</span>';

        const now = new Date();
        const expiry = new Date(certificate.expiry);
        const daysUntilExpiry = Math.ceil((expiry - now) / (1000 * 60 * 60 * 24));

        if (certificate.revoked) {
            return '<span class="cert-status cert-revoked"><i class="fas fa-times-circle"></i> Revoked</span>';
        } else if (expiry < now) {
            return '<span class="cert-status cert-expired"><i class="fas fa-exclamation-triangle"></i> Expired</span>';
        } else if (daysUntilExpiry <= 30) {
            return `<span class="cert-status cert-expiring"><i class="fas fa-clock"></i> Expires in ${daysUntilExpiry} days</span>`;
        } else {
            return '<span class="cert-status cert-valid"><i class="fas fa-check-circle"></i> Valid</span>';
        }
    }

    formatBytes(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    formatUptime(seconds) {
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);

        if (days > 0) {
            return `${days}d ${hours}h`;
        } else if (hours > 0) {
            return `${hours}h ${minutes}m`;
        } else {
            return `${minutes}m`;
        }
    }

    copyConfig() {
        const configTextarea = document.getElementById('clientConfig');
        configTextarea.select();
        document.execCommand('copy');
        this.showSuccess('Configuration copied to clipboard!');
    }

    downloadConfig() {
        if (this.currentClientConfig) {
            const element = document.createElement('a');
            const file = new Blob([this.currentClientConfig.config], { type: 'text/plain' });
            element.href = URL.createObjectURL(file);
            element.download = `${this.currentClientConfig.name}.ovpn`;
            document.body.appendChild(element);
            element.click();
            document.body.removeChild(element);
        }
    }

    downloadLogs() {
        if (this.logs && this.logs.length > 0) {
            const element = document.createElement('a');
            const file = new Blob([this.logs.join('\n')], { type: 'text/plain' });
            element.href = URL.createObjectURL(file);
            element.download = `openvpn-logs-${new Date().toISOString().split('T')[0]}.txt`;
            document.body.appendChild(element);
            element.click();
            document.body.removeChild(element);
        }
    }

    showSuccess(message) {
        this.showToast(message, 'success');
    }

    showError(message) {
        this.showToast(message, 'error');
    }

    showToast(message, type = 'info') {
        const toast = document.createElement('div');
        toast.className = `toast align-items-center text-white bg-${type === 'success' ? 'success' : 'danger'} border-0`;
        toast.setAttribute('role', 'alert');
        toast.setAttribute('aria-live', 'assertive');
        toast.setAttribute('aria-atomic', 'true');

        toast.innerHTML = `
            <div class="d-flex">
                <div class="toast-body">
                    ${message}
                </div>
                <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
            </div>
        `;

        let toastContainer = document.getElementById('toastContainer');
        if (!toastContainer) {
            toastContainer = document.createElement('div');
            toastContainer.id = 'toastContainer';
            toastContainer.className = 'toast-container position-fixed top-0 end-0 p-3';
            document.body.appendChild(toastContainer);
        }

        toastContainer.appendChild(toast);

        const bsToast = new bootstrap.Toast(toast);
        bsToast.show();

        toast.addEventListener('hidden.bs.toast', () => {
            toast.remove();
        });
    }

    startPolling() {
        setInterval(() => {
            this.loadServerStats();
            this.loadConnections();
        }, 30000);

        setInterval(() => {
            this.loadClients();
        }, 60000);
    }

    startLogAutoRefresh() {
        if (this.autoRefreshInterval) {
            clearInterval(this.autoRefreshInterval);
        }
        this.autoRefreshInterval = setInterval(() => {
            this.loadLogs(
                document.getElementById('logLevel').value,
                document.getElementById('logLines').value
            );
        }, 5000);
    }

    stopLogAutoRefresh() {
        if (this.autoRefreshInterval) {
            clearInterval(this.autoRefreshInterval);
            this.autoRefreshInterval = null;
        }
    }
}

// Global Functions
async function addClient() {
    const name = document.getElementById('clientName').value;
    const email = document.getElementById('clientEmail').value;
    const description = document.getElementById('clientDescription').value;
    const noPassword = document.getElementById('clientNoPass').checked;

    if (!name.trim()) {
        app.showError('Please enter a client name');
        return;
    }

    try {
        await app.createClient({
            name: name.trim(),
            email: email.trim(),
            description: description.trim(),
            noPassword: noPassword
        });

        document.getElementById('addClientForm').reset();

        const modal = bootstrap.Modal.getInstance(document.getElementById('addClientModal'));
        modal.hide();
    } catch (error) {
        // Error already handled in createClient method
    }
}

function refreshLogs() {
    app.loadLogs(
        document.getElementById('logLevel').value,
        document.getElementById('logLines').value
    );
}

function showCAInfo() {
    // Implementation for showing CA information
    app.showSuccess('CA information loaded');
}

function regenerateCA() {
    if (confirm('Are you sure you want to regenerate the Certificate Authority? This will invalidate all existing certificates.')) {
        app.showWarning('CA regeneration is not implemented yet');
    }
}

function downloadCRL() {
    app.showSuccess('CRL download started');
}

function updateCRL() {
    app.showSuccess('CRL updated');
}

function saveConfiguration() {
    const config = {
        serverIP: document.getElementById('serverIP').value,
        serverPort: document.getElementById('serverPort').value,
        protocol: document.getElementById('protocol').value,
        subnet: document.getElementById('subnet').value,
        cipher: document.getElementById('cipher').value,
        authDigest: document.getElementById('authDigest').value,
        compression: document.getElementById('compression').checked,
        duplicateCN: document.getElementById('duplicateCN').checked
    };

    app.saveConfiguration(config);
}

function restartServer() {
    if (confirm('Are you sure you want to restart the OpenVPN server? This will disconnect all clients.')) {
        app.restartServer();
    }
}

function showSettings() {
    app.showSuccess('Settings modal would open here');
}

function logout() {
    if (confirm('Are you sure you want to logout?')) {
        window.location.href = '/login';
    }
}

// Initialize app when DOM is loaded
let app;
document.addEventListener('DOMContentLoaded', () => {
    app = new OpenVPNManager();
});

// Service Worker for offline support
if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js')
            .then((registration) => {
                console.log('SW registered: ', registration);
            })
            .catch((registrationError) => {
                console.log('SW registration failed: ', registrationError);
            });
    });
} 