// Outline VPN Manager JavaScript

class OutlineManager {
    constructor() {
        this.apiUrl = '/api';
        this.users = [];
        this.serverStats = {};
        this.init();
    }

    async init() {
        await this.loadServerStats();
        await this.loadUsers();
        this.startPolling();
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

    async loadUsers() {
        try {
            const users = await this.makeRequest('/users');
            this.users = users;
            this.updateUsersTable();
            this.updateUserCount();
        } catch (error) {
            console.error('Failed to load users:', error);
        }
    }

    async createUser(name, dataLimit = null) {
        try {
            const user = await this.makeRequest('/users', {
                method: 'POST',
                body: JSON.stringify({ name, dataLimit })
            });
            this.users.push(user);
            this.updateUsersTable();
            this.updateUserCount();
            this.showSuccess('User created successfully!');
            return user;
        } catch (error) {
            console.error('Failed to create user:', error);
            this.showError('Failed to create user');
            throw error;
        }
    }

    async deleteUser(userId) {
        try {
            await this.makeRequest(`/users/${userId}`, {
                method: 'DELETE'
            });
            this.users = this.users.filter(u => u.id !== userId);
            this.updateUsersTable();
            this.updateUserCount();
            this.showSuccess('User deleted successfully!');
        } catch (error) {
            console.error('Failed to delete user:', error);
            this.showError('Failed to delete user');
        }
    }

    async getUserDetails(userId) {
        try {
            return await this.makeRequest(`/users/${userId}`);
        } catch (error) {
            console.error('Failed to get user details:', error);
            throw error;
        }
    }

    // UI Update Methods
    updateServerStatus() {
        const statusElement = document.getElementById('serverStatus');
        const statusText = document.getElementById('statusText');
        const activeConnections = document.getElementById('activeConnections');
        const totalUsers = document.getElementById('totalUsers');
        const dataTransfer = document.getElementById('dataTransfer');
        const serverUptime = document.getElementById('serverUptime');
        const totalDataTransfer = document.getElementById('totalDataTransfer');
        const peakConnections = document.getElementById('peakConnections');
        const serverLocation = document.getElementById('serverLocation');

        if (this.serverStats.online) {
            statusElement.innerHTML = '<i class="fas fa-circle text-success"></i>';
            statusText.textContent = 'Online';
        } else {
            statusElement.innerHTML = '<i class="fas fa-circle text-danger"></i>';
            statusText.textContent = 'Offline';
        }

        activeConnections.textContent = this.serverStats.activeConnections || 0;
        totalUsers.textContent = this.users.length;
        dataTransfer.textContent = this.formatBytes(this.serverStats.dataTransfer || 0);
        serverUptime.textContent = this.formatUptime(this.serverStats.uptime || 0);
        totalDataTransfer.textContent = this.formatBytes(this.serverStats.totalDataTransfer || 0);
        peakConnections.textContent = this.serverStats.peakConnections || 0;
        serverLocation.textContent = this.serverStats.location || 'Unknown';
    }

    updateUsersTable() {
        const tbody = document.getElementById('usersTable');
        tbody.innerHTML = '';

        this.users.forEach(user => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${user.name}</td>
                <td><code>${user.id}</code></td>
                <td><span class="user-status ${user.status}">${user.status}</span></td>
                <td>${this.formatBytes(user.dataUsage || 0)}</td>
                <td>${new Date(user.created).toLocaleDateString()}</td>
                <td>
                    <button class="btn btn-sm btn-primary btn-action" onclick="app.showUserDetails('${user.id}')">
                        <i class="fas fa-eye"></i> View
                    </button>
                    <button class="btn btn-sm btn-danger btn-action" onclick="app.confirmDeleteUser('${user.id}')">
                        <i class="fas fa-trash"></i> Delete
                    </button>
                </td>
            `;
            tbody.appendChild(row);
        });
    }

    updateUserCount() {
        document.getElementById('totalUsers').textContent = this.users.length;
    }

    // Modal Methods
    showAddUserModal() {
        const modal = new bootstrap.Modal(document.getElementById('addUserModal'));
        modal.show();
    }

    async showUserDetails(userId) {
        try {
            const user = await this.getUserDetails(userId);

            document.getElementById('accessKey').value = user.accessKey;

            // Generate QR code
            const qrContainer = document.getElementById('qrCodeContainer');
            qrContainer.innerHTML = '';

            QRCode.toCanvas(qrContainer, user.accessKey, {
                width: 200,
                margin: 2,
                color: {
                    dark: '#000000',
                    light: '#FFFFFF'
                }
            }, (error) => {
                if (error) console.error('QR Code generation failed:', error);
            });

            const modal = new bootstrap.Modal(document.getElementById('userDetailsModal'));
            modal.show();
        } catch (error) {
            this.showError('Failed to load user details');
        }
    }

    confirmDeleteUser(userId) {
        const user = this.users.find(u => u.id === userId);
        if (user && confirm(`Are you sure you want to delete user "${user.name}"?`)) {
            this.deleteUser(userId);
        }
    }

    // Utility Methods
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
            return `${days} days, ${hours} hours`;
        } else if (hours > 0) {
            return `${hours} hours, ${minutes} minutes`;
        } else {
            return `${minutes} minutes`;
        }
    }

    copyToClipboard(elementId) {
        const element = document.getElementById(elementId);
        element.select();
        document.execCommand('copy');
        this.showSuccess('Copied to clipboard!');
    }

    showSuccess(message) {
        this.showToast(message, 'success');
    }

    showError(message) {
        this.showToast(message, 'error');
    }

    showToast(message, type = 'info') {
        // Create toast element
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

        // Add to page
        let toastContainer = document.getElementById('toastContainer');
        if (!toastContainer) {
            toastContainer = document.createElement('div');
            toastContainer.id = 'toastContainer';
            toastContainer.className = 'toast-container position-fixed top-0 end-0 p-3';
            document.body.appendChild(toastContainer);
        }

        toastContainer.appendChild(toast);

        // Show toast
        const bsToast = new bootstrap.Toast(toast);
        bsToast.show();

        // Remove after hiding
        toast.addEventListener('hidden.bs.toast', () => {
            toast.remove();
        });
    }

    startPolling() {
        // Poll server stats every 30 seconds
        setInterval(() => {
            this.loadServerStats();
        }, 30000);

        // Poll users every 60 seconds
        setInterval(() => {
            this.loadUsers();
        }, 60000);
    }
}

// Global Functions
async function addUser() {
    const name = document.getElementById('userName').value;
    const dataLimit = document.getElementById('dataLimit').value;

    if (!name.trim()) {
        app.showError('Please enter a user name');
        return;
    }

    try {
        await app.createUser(name, dataLimit ? parseInt(dataLimit) : null);

        // Clear form
        document.getElementById('addUserForm').reset();

        // Close modal
        const modal = bootstrap.Modal.getInstance(document.getElementById('addUserModal'));
        modal.hide();
    } catch (error) {
        // Error already handled in createUser method
    }
}

function logout() {
    if (confirm('Are you sure you want to logout?')) {
        window.location.href = '/login';
    }
}

// Initialize app when DOM is loaded
let app;
document.addEventListener('DOMContentLoaded', () => {
    app = new OutlineManager();
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