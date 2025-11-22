# Vagrant and Cloud-Init App Deployment

## Vagrant App Deployment

This repository contains configuration files and scripts for deploying a Flask-based web application (joke-a-minute) using Vagrant and VirtualBox. The deployment includes automated provisioning, SSL/TLS encryption via Let's Encrypt, and an Nginx reverse proxy for secure HTTPS access.

## Overview

We're deploying a Python Flask application inside an Ubuntu virtual machine managed by Vagrant. The host machine runs Nginx as a reverse proxy with SSL certificates, allowing secure external access to the application running inside the VM. This setup is ideal for development, testing, or small-scale production deployments.

---

## Requirements Check

### Verify Hardware Virtualization Support

Before installing anything, check if your CPU supports hardware virtualization (required for running VMs efficiently):

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
```

**What this command does:**  
This searches your CPU info for virtualization flags. Intel CPUs use `vmx` (VT-x), while AMD CPUs use `svm` (AMD-V). The output is a number representing how many CPU cores have virtualization enabled.

**Expected output:**  
Any number greater than 0 means you're good to go. For example, if you see `4`, it means 4 cores support virtualization. If you get `0`, virtualization is either not supported by your CPU or disabled in your BIOS settings.

---

## Step 1: Install VirtualBox

VirtualBox is the hypervisor that will host your virtual machines. We need to install it along with the necessary kernel modules.

```bash
sudo apt install virtualbox virtualbox-dkms linux-headers-$(uname -r)
```

**Breaking down this command:**
- `virtualbox` → The main VirtualBox package
- `virtualbox-dkms` → Dynamic Kernel Module Support ensures VirtualBox kernel modules rebuild automatically when your kernel updates
- `linux-headers-$(uname -r)` → Installs kernel headers matching your current kernel version, which are needed to compile VirtualBox kernel modules

### Verify VirtualBox Installation

```bash
vboxmanage --version
```

If installed correctly, this will output the VirtualBox version number (e.g., `6.1.38r153438`).

---

## Step 2: Clone the Repository

First, make sure Git is installed on your system:

```bash
sudo apt install git
```

Git is essential for cloning repositories from GitHub. Once installed, clone this repository:

```bash
git clone https://github.com/Filusion/joke-a-minute_vagrant_cloud-init.git joke-a-minute
```

This creates a `joke-a-minute` directory containing all necessary files.

### Expected Directory Structure

After cloning, your project structure should look like this:

```
joke-a-minute/
├── app
│   ├── app.py              # Main Flask application
│   ├── init_db.py          # Database initialization script
│   └── requirements.txt    # Python dependencies
└── IoC
    ├── provision.sh
    └── vagrant
        ├── provision.sh    # VM provisioning script
        └── Vagrantfile     # Vagrant configuration
```

---

## Step 3: Install Vagrant

Vagrant automates the process of setting up and managing virtual machines. We'll install it from HashiCorp's official repository to get the latest version.

### Add HashiCorp Repository and Install Vagrant

```bash
# Download HashiCorp's GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add the HashiCorp repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update package lists
sudo apt update

# Install Vagrant
sudo apt install -y vagrant
```

**Why these steps:**
- The GPG key verifies package authenticity
- `lsb_release -cs` automatically detects your Ubuntu version codename (focal, jammy, etc.)
- Adding the repository gives you access to official, up-to-date Vagrant releases

### Verify Vagrant Installation

```bash
vagrant --version
```

This shows the installed Vagrant version.

```bash
vagrant version
```

This command verifies that Vagrant can communicate with VirtualBox. If everything is configured correctly, you'll see version information for both the installed and latest available Vagrant versions.

---

## Step 4: Configure SSL/TLS with Nginx

To securely access our application over the internet, we need to set up Nginx as a reverse proxy with SSL certificates from Let's Encrypt. This ensures all traffic between users and your application is encrypted.

### Install Nginx and Certbot

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo apt install nginx
```

**What you're installing:**
- `nginx` → A high-performance web server that will act as a reverse proxy
- `certbot` → Automated tool for obtaining and managing Let's Encrypt SSL certificates
- `python3-certbot-nginx` → Certbot plugin for automatic Nginx configuration

### Obtain SSL Certificate

```bash
sudo certbot certonly --standalone -d devops-vm-43.lrk.si --non-interactive --agree-tos -m admin@devops-vm-43.lrk.si
```

**Understanding this command:**
- `certonly` → Only obtain the certificate (we'll configure Nginx manually)
- `--standalone` → Certbot runs its own temporary web server on port 80 to verify you control the domain
- `-d devops-vm-43.lrk.si` → Your domain name (replace with yours)
- `--non-interactive` → No prompts, runs automatically
- `--agree-tos` → Accepts Let's Encrypt Terms of Service
- `-m admin@devops-vm-43.lrk.si` → Email for renewal notifications and security alerts (replace with yours)

**Important prerequisite:**  
Before running this command, ensure your domain's DNS A record points to your server's public IP address and port 80 is accessible from the internet.

### Enable Automatic Certificate Renewal

Let's Encrypt certificates expire after 90 days. To avoid manual renewal, enable automatic renewal:

```bash
# Enable the certbot timer service
sudo systemctl enable certbot.timer

# Start the timer service
sudo systemctl start certbot.timer
```

**What this does:**  
The certbot timer automatically checks twice daily if your certificates need renewal and renews them when they're within 30 days of expiration. Nginx is automatically reloaded after successful renewal.

### Create Nginx Configuration

Create a new Nginx site configuration:

```bash
sudo nano /etc/nginx/sites-available/joke-app
```

Paste the following configuration (remember to replace domain names and IP addresses with your own):

```nginx
# HTTP - redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name devops-vm-43.lrk.si;
    
    return 301 https://$server_name$request_uri;
}

# HTTPS - proxy to Vagrant VM
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name devops-vm-43.lrk.si;

    # Let's Encrypt certificates
    ssl_certificate /etc/letsencrypt/live/devops-vm-43.lrk.si/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/devops-vm-43.lrk.si/privkey.pem;

    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Proxy settings
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

**Configuration breakdown:**

**HTTP server block:**
- Listens on port 80 (both IPv4 and IPv6)
- Redirects all HTTP requests to HTTPS for security

**HTTPS server block:**
- Listens on port 443 with SSL enabled and HTTP/2 support
- Points to your Let's Encrypt SSL certificates (fullchain.pem contains your certificate + intermediate certificates, privkey.pem is your private key)
- Configures SSL to use only modern, secure protocols (TLS 1.2 and 1.3)
- Uses strong cipher suites, excluding weak or null encryption
- Proxies all requests to `127.0.0.1:8080` where your Vagrant VM will be accessible
- Preserves original client information in HTTP headers
- Supports WebSocket connections with Upgrade headers

### Enable the Site Configuration

```bash
# Create a symbolic link to enable the site
sudo ln -sf /etc/nginx/sites-available/joke-app /etc/nginx/sites-enabled/

# Remove the default site to avoid conflicts
sudo rm -f /etc/nginx/sites-enabled/default

# Test the configuration for syntax errors
sudo nginx -t

# Start Nginx
sudo systemctl start nginx
```

**What these commands do:**
- Nginx only serves sites that are symlinked in `sites-enabled/`
- Removing the default site prevents conflicts with our configuration
- `nginx -t` validates your configuration before applying it (always do this!)
- Starting the service makes Nginx active

---

## Step 5: Configure the Firewall

We need to allow HTTP and HTTPS traffic through the firewall so external users can access your application.

```bash
# Check current firewall status
sudo ufw status numbered

# Allow HTTP (port 80) - needed for Let's Encrypt verification and redirects
sudo ufw allow 80/tcp

# Allow HTTPS (port 443) - needed for secure application access
sudo ufw allow 443/tcp

# Reload firewall to apply changes
sudo ufw reload

# Verify the rules are active
sudo ufw status
```

**Why we need these firewall rules:**
- Port 80 is required for Let's Encrypt to verify domain ownership and for HTTP-to-HTTPS redirects
- Port 443 is required for users to access your application over HTTPS
- Without these rules, all external access attempts will be blocked

**Expected output from `sudo ufw status`:**
```
80/tcp          ALLOW       Anywhere
443/tcp         ALLOW       Anywhere
80/tcp (v6)     ALLOW       Anywhere (v6)
443/tcp (v6)    ALLOW       Anywhere (v6)
```

### Apply Nginx Configuration

Reload Nginx to ensure all changes are active:

```bash
sudo systemctl reload nginx
```

This reloads the configuration without dropping existing connections.

---

## Step 6: Deploy the Application

Navigate to the Vagrant configuration directory:

```bash
cd ~/joke-a-minute/IoC/vagrant
```

Start the Vagrant VM and provision the application:

```bash
vagrant up
```

**What happens during this step:**

Vagrant will:
1. Read the `Vagrantfile` to understand the VM configuration
2. Download the Ubuntu box image if it's not already cached (this can take a few minutes the first time)
3. Create a new virtual machine in VirtualBox with the specified settings
4. Configure networking (port forwarding from host port 8080 to the VM)
5. Run the `provision.sh` script inside the VM, which:
   - Updates the system packages
   - Installs Python, pip, and required system dependencies
   - Sets up the Flask application
   - Installs Python dependencies from `requirements.txt`
   - Initializes the database
   - Configures the application to start automatically
   - Starts the application server

The entire process typically takes 5-10 minutes on the first run. Subsequent runs are faster since the base image is cached.

---

## Step 7: Access Your Application

Once the deployment completes successfully, you can access your application securely at:

```
https://devops-vm-43.lrk.si/
```

(Replace with your actual domain name)

**How the connection works:**
1. User's browser connects to your domain via HTTPS (port 443)
2. Nginx on the host machine receives the request
3. Nginx decrypts the SSL/TLS connection using Let's Encrypt certificates
4. Nginx forwards the request to `127.0.0.1:8080`
5. Vagrant's port forwarding sends it to the Flask app inside the VM
6. The response travels back through the same path

---

## Useful Vagrant Commands

Once your VM is running, you can manage it with these commands:

```bash
# Stop the VM (graceful shutdown)
vagrant halt

# Start a stopped VM
vagrant up

# Restart the VM
vagrant reload

# Restart and re-run provisioning scripts
vagrant reload --provision

# SSH into the VM
vagrant ssh

# Check VM status
vagrant status

# View port forwarding info
vagrant port

# Destroy the VM completely (delete all data)
vagrant destroy

# Destroy and recreate the VM
vagrant destroy -f && vagrant up
```

---

## Troubleshooting

### Certificate Generation Fails

**Problem:** Certbot can't verify domain ownership  
**Solutions:**
- Verify your domain's DNS A record points to your server's public IP
- Ensure port 80 is not blocked by your ISP or firewall
- Check if another service is using port 80: `sudo netstat -tlnp | grep :80`
- Temporarily stop Nginx if it's blocking: `sudo systemctl stop nginx`, then retry certbot, then restart Nginx

### Application Not Accessible

**Problem:** Can't reach the application in browser  
**Solutions:**
- Verify Nginx is running: `sudo systemctl status nginx`
- Test Nginx configuration: `sudo nginx -t`
- Check if the VM is running: `vagrant status`
- Verify port forwarding: `vagrant port` (should show 8080)
- Test local access: `curl http://localhost:8080`
- Check Nginx error logs: `sudo tail -f /var/log/nginx/error.log`
- Check Nginx access logs: `sudo tail -f /var/log/nginx/access.log`


---

## Additional Resources

- [Vagrant Documentation](https://www.vagrantup.com/docs)
- [VirtualBox Manual](https://www.virtualbox.org/manual/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Certbot Documentation](https://eff-certbot.readthedocs.io/)

***
---
***
## Cloud-init App Deployment
