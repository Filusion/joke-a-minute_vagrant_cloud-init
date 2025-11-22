#!/bin/bash

# =============================================================================
# Joke-a-Minute Vagrant Provisioning Script
# =============================================================================
# This script automatically installs and configures all components needed for
# the Joke-a-Minute application inside the Vagrant VM
#
# Components installed:
#   - MySQL 8.0 (database for jokes storage)
#   - Redis (caching layer for performance)
#   - Python 3 + pip + venv (application runtime)
#   - Nginx (reverse proxy and web server)
#   - Flask + Gunicorn (Python web application)
#
# Exit on any error

set -e

echo "========================================="
echo "   Starting Joke App Provisioning"
echo "========================================="
echo "Starting at: $(date)"
echo ""

# Update system
# =============================================================================
# System Update
# =============================================================================
echo ">>> [1/9]  Updating system packages..."
echo "  → Running apt-get update to refresh package lists"
export DEBIAN_FRONTEND=noninteractive
apt-get update
echo "  → Running apt-get upgrade to update installed packages"
apt-get upgrade -y
echo "  ✓ System packages updated"
echo ""

# Install MySQL
# =============================================================================
# MySQL Installation
# =============================================================================
echo ">>> [2/9] Installing MySQL..."
echo "  → Installing mysql-server package"
apt-get install -y mysql-server
echo "  → Starting MySQL service"
systemctl start mysql
echo "  → Enabling MySQL to start on boot"
systemctl enable mysql
echo "  ✓ MySQL installed and running"
echo ""

# Install Redis
# =============================================================================
# Redis Installation
# =============================================================================
echo ">>> [3/9] Installing Redis..."
echo "  → Installing redis-server package"
apt-get install -y redis-server
echo "  → Starting Redis service"
systemctl start redis-server
echo "  → Enabling Redis to start on boot"
systemctl enable redis-server
echo "  ✓ Redis installed and running"
echo ""

# Install Python and pip
# =============================================================================
# Python Installation
# =============================================================================
echo ">>> [4/9] Installing Python..."
echo "  → Installing python3, pip, and venv"
apt-get install -y python3 python3-pip python3-venv
echo "  ✓ Python environment ready"
echo ""

# =============================================================================
# Nginx Installation
# =============================================================================
# Install Nginx (for internal use)
echo ">>> [5/9] Installing Nginx..."
echo "  → Installing nginx package"
apt-get install -y nginx
echo "  ✓ Nginx installed"
echo ""

# =============================================================================
# Application Setup
# =============================================================================
# Create app directory
echo ">>> [6/9] Setting up application..."
echo "  → Creating /opt/joke-app directory"
mkdir -p /opt/joke-app
echo "  → Copying application files from /project/app/"
cp -r /project/app/* /opt/joke-app/

# Create virtual environment and install dependencies
echo "  → Creating Python virtual environment"
cd /opt/joke-app
python3 -m venv venv
echo "  → Activating virtual environment"
source venv/bin/activate
echo "  → Upgrading pip to latest version"
pip install --upgrade pip
echo "  → Installing Python dependencies from requirements.txt"
pip install -r requirements.txt
echo "  → Installing Gunicorn (production WSGI server)"
pip install gunicorn
echo "  → Deactivating virtual environment"
deactivate

echo "  ✓ Application files configured"
echo ""

# =============================================================================
# MySQL Database Configuration
# =============================================================================
# Configure MySQL database
echo ">>> [7/9] Configuring MySQL database..."
echo "  → Creating database 'jokes_db'"
echo "  → Creating user 'joke_user' with password"
echo "  → Granting privileges"
mysql <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS jokes_db;
CREATE USER IF NOT EXISTS 'joke_user'@'localhost' IDENTIFIED BY 'joke_pass123';
GRANT ALL PRIVILEGES ON jokes_db.* TO 'joke_user'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
echo "  ✓ MySQL database configured"
echo ""

# =============================================================================
# Database Initialization
# =============================================================================
# Initialize database with jokes
echo ">>> [8/9] Initializing database with jokes..."
echo "  → Running init_db.py to populate jokes table"
source /opt/joke-app/venv/bin/activate
python3 init_db.py
deactivate

# Verify jokes were added
JOKE_COUNT=$(mysql -u joke_user -pjoke_pass123 jokes_db -sN -e "SELECT COUNT(*) FROM jokes;" 2>/dev/null || echo "0")
echo "  ✓ Database initialized with $JOKE_COUNT jokes"
echo ""

# =============================================================================
# Systemd Service Creation
# =============================================================================
# Create systemd service for Flask app
echo ">>> [9/9] Creating and starting systemd service..."
echo "  → Creating /etc/systemd/system/joke-app.service"
cat > /etc/systemd/system/joke-app.service <<'SERVICE'
[Unit]
Description=Joke-a-Minute Flask Application
After=network.target mysql.service redis-server.service

[Service]
User=root
WorkingDirectory=/opt/joke-app
Environment="PATH=/opt/joke-app/venv/bin"
ExecStart=/opt/joke-app/venv/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

# Start Flask app
echo ">>> Starting Flask application..."
echo "  → Reloading systemd daemon"
systemctl daemon-reload
echo "  → Starting joke-app service"
systemctl start joke-app
echo "  → Enabling joke-app to start on boot"
systemctl enable joke-app

# Wait for Flask to start
echo "  → Waiting 5 seconds for service to start..."
sleep 5

# Check if Flask is running
if systemctl is-active --quiet joke-app; then
    echo "✓ Flask app started successfully"
else
    echo "✗ Flask app failed to start"
    systemctl status joke-app
    exit 1
fi

# =============================================================================
# Nginx Configuration
# =============================================================================
# Configure Nginx as reverse proxy
echo ">>> [10/10] Configuring Nginx reverse proxy..."
echo "  → Creating nginx config for joke-app"
cat > /etc/nginx/sites-available/joke-app <<'NGINX_CONFIG'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX_CONFIG

echo "  → Enabling site (creating symlink)"
ln -sf /etc/nginx/sites-available/joke-app /etc/nginx/sites-enabled/
echo "  → Removing default nginx site"
rm -f /etc/nginx/sites-enabled/default

echo "  → Testing nginx configuration"
nginx -t

echo "  → Restarting nginx"
systemctl restart nginx

echo "  ✓ Nginx configured and running"
echo ""

# =============================================================================
# GUI ENVIRONMENT SETUP - noVNC ONLY
# =============================================================================
echo "========================================="
echo "   Installing GUI Environment (noVNC)"
echo "========================================="
echo ""

# =============================================================================
# Desktop Environment Installation
# =============================================================================
echo ">>> [11/13] Installing XFCE Desktop Environment..."
echo "  → Installing xfce4 (lightweight desktop)"
apt-get install -y xfce4 xfce4-goodies dbus-x11
echo "  → Installing basic GUI applications"
apt-get install -y firefox gedit gnome-terminal
echo "  ✓ Desktop environment installed"
echo ""

# =============================================================================
# VNC Server Installation
# =============================================================================
echo ">>> [12/13] Installing TightVNC Server..."
echo "  → Installing tightvncserver"
apt-get install -y tightvncserver
echo "  → Creating VNC user directory"
mkdir -p /home/vagrant/.vnc

# Set VNC password (password: vagrant)
echo "  → Setting VNC password to 'vagrant'"
echo -e "vagrant\nvagrant\nn" | vncpasswd -f > /home/vagrant/.vnc/passwd
chmod 600 /home/vagrant/.vnc/passwd

# Create VNC xstartup script
cat > /home/vagrant/.vnc/xstartup <<'VNCSTARTUP'
#!/bin/bash
xrdb $HOME/.Xresources
startxfce4 &
VNCSTARTUP

chmod +x /home/vagrant/.vnc/xstartup
chown -R vagrant:vagrant /home/vagrant/.vnc

# Create VNC systemd service
cat > /etc/systemd/system/vncserver@.service <<'VNCSERVICE'
[Unit]
Description=TightVNC Server
After=syslog.target network.target

[Service]
Type=forking
User=vagrant
Group=vagrant
WorkingDirectory=/home/vagrant
PIDFile=/home/vagrant/.vnc/%H:%i.pid
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver -depth 24 -geometry 1280x800 :%i
ExecStop=/usr/bin/vncserver -kill :%i

[Install]
WantedBy=multi-user.target
VNCSERVICE

systemctl daemon-reload
systemctl enable vncserver@1.service
systemctl start vncserver@1.service

echo "  ✓ VNC Server running on display :1 (port 5901)"
echo ""

# =============================================================================
# noVNC Installation
# =============================================================================
echo ">>> [13/13] Installing noVNC (browser-based access)..."
echo "  → Installing git and dependencies"
apt-get install -y git python3-numpy

echo "  → Cloning noVNC repository"
cd /opt
git clone https://github.com/novnc/noVNC.git
cd noVNC
git clone https://github.com/novnc/websockify.git

# Create noVNC systemd service
cat > /etc/systemd/system/novnc.service <<'NOVNCSERVICE'
[Unit]
Description=noVNC Web VNC Client
After=network.target vncserver@1.service

[Service]
Type=simple
User=root
ExecStart=/opt/noVNC/utils/novnc_proxy --vnc localhost:5901 --listen 6080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
NOVNCSERVICE

systemctl daemon-reload
systemctl enable novnc.service
systemctl start novnc.service

echo "  ✓ noVNC running on port 6080"
echo ""


# =============================================================================
# Final Status Report
# =============================================================================
echo "========================================="
echo "   ✅ Vagrant VM Provisioning Complete!"
echo "========================================="
echo ""
echo "🎉 All services are now running!"
echo ""
echo "📊 Service Status:"
echo "  • MySQL:       $(systemctl is-active mysql)"
echo "  • Redis:       $(systemctl is-active redis-server)"
echo "  • Flask App:   $(systemctl is-active joke-app)"
echo "  • Nginx:       $(systemctl is-active nginx)"
echo ""
echo "🔗 Access Points (from HOST machine):"
echo "  • Via HOST Nginx: https://devops-vm-43.lrk.si"
echo "  • Direct to VM:   http://localhost:8080"
echo "  • Direct Flask:   http://localhost:5000"
echo "  • GUI (noVNC): http://localhost:6080/vnc.html or https://devops-vm-43.lrk.si/gui/vnc.html"
echo "     Password: vagrant"
echo ""
echo "📝 Logs:"
echo "  • Flask logs: journalctl -u joke-app -f"
echo "  • Nginx logs: /var/log/nginx/error.log"
echo ""
echo "Completed at: $(date)"
echo "========================================="