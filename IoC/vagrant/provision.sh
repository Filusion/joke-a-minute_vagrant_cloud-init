#!/bin/bash
set -e

echo "========================================="
echo "   Starting Joke App Provisioning"
echo "========================================="
echo ""

# Update system
echo ">>> Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install MySQL
echo ">>> Installing MySQL..."
apt-get install -y mysql-server
systemctl start mysql
systemctl enable mysql

# Install Redis
echo ">>> Installing Redis..."
apt-get install -y redis-server
systemctl start redis-server
systemctl enable redis-server

# Install Python and pip
echo ">>> Installing Python..."
apt-get install -y python3 python3-pip python3-venv

# Install Nginx (for internal use)
echo ">>> Installing Nginx..."
apt-get install -y nginx

# Create app directory
echo ">>> Setting up application..."
mkdir -p /opt/joke-app
cp -r /project/app/* /opt/joke-app/

# Create virtual environment and install dependencies
echo ">>> Installing Python dependencies..."
cd /opt/joke-app
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install gunicorn
deactivate

# Configure MySQL database
echo ">>> Configuring MySQL database..."
mysql <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS jokes_db;
CREATE USER IF NOT EXISTS 'joke_user'@'localhost' IDENTIFIED BY 'joke_pass123';
GRANT ALL PRIVILEGES ON jokes_db.* TO 'joke_user'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Initialize database with jokes
echo ">>> Initializing database..."
source /opt/joke-app/venv/bin/activate
python3 init_db.py
deactivate

# Create systemd service for Flask app
echo ">>> Creating Flask service..."
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
systemctl daemon-reload
systemctl start joke-app
systemctl enable joke-app

# Wait for Flask to start
sleep 5

# Check if Flask is running
if systemctl is-active --quiet joke-app; then
    echo "✓ Flask app started successfully"
else
    echo "✗ Flask app failed to start"
    systemctl status joke-app
    exit 1
fi

# Configure Nginx as reverse proxy
echo ">>> Configuring Nginx..."
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

ln -sf /etc/nginx/sites-available/joke-app /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl restart nginx

echo ""
echo "========================================="
echo "   VM Provisioning Complete!"
echo "========================================="
echo ""
echo "✅ All services running in VM!"
echo ""
echo "Service Status:"
echo "  MySQL:       $(systemctl is-active mysql)"
echo "  Redis:       $(systemctl is-active redis-server)"
echo "  Flask App:   $(systemctl is-active joke-app)"
echo "  Nginx:       $(systemctl is-active nginx)"
echo ""
echo "VM is accessible at:"
echo "  - http://localhost:8080 (from HOST)"
echo "  - http://localhost:5000 (direct Flask access)"
echo ""
echo "========================================="