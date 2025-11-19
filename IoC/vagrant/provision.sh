#!/bin/bash
set -e

DOMAIN="devops-vm-20.lrk.si"
EMAIL="admin@devops-vm-20.lrk.si"  # Change this to your actual email

echo "=== Starting Joke App Provisioning ==="

# Update system
echo ">>> Updating system packages..."
apt-get update
apt-get upgrade -y

# Install MySQL
echo ">>> Installing MySQL..."
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
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

# Install Nginx
echo ">>> Installing Nginx..."
apt-get install -y nginx

# Install Certbot for Let's Encrypt
echo ">>> Installing Certbot..."
apt-get install -y certbot python3-certbot-nginx

# Create app directory
echo ">>> Setting up application..."
mkdir -p /opt/joke-app
cp -r /project/app/* /opt/joke-app/

# Create virtual environment and install dependencies
cd /opt/joke-app
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

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
python3 init_db.py

# Create systemd service for Flask app
echo ">>> Creating Flask service..."
cat > /etc/systemd/system/joke-app.service <<SERVICE
[Unit]
Description=Joke-a-Minute Flask Application
After=network.target mysql.service redis-server.service

[Service]
User=root
WorkingDirectory=/opt/joke-app
Environment="PATH=/opt/joke-app/venv/bin"
ExecStart=/opt/joke-app/venv/bin/python3 /opt/joke-app/app.py
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

# Start Flask app
systemctl daemon-reload
systemctl start joke-app
systemctl enable joke-app

# Configure Nginx (temporary HTTP config for Let's Encrypt)
echo ">>> Configuring Nginx..."
cat > /etc/nginx/sites-available/joke-app <<NGINX
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/joke-app /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and reload Nginx
nginx -t
systemctl reload nginx

# Get Let's Encrypt certificate
echo ">>> Obtaining Let's Encrypt certificate..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $EMAIL --redirect

echo "=== Provisioning Complete! ==="
echo "Access the app at:"
echo "  - https://$DOMAIN (Trusted HTTPS with Let's Encrypt)"
echo "  - http://$DOMAIN (redirects to HTTPS)"