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

    # GUI access via noVNC (NEW)
    location /gui/ {
        proxy_pass http://127.0.0.1:6080/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
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

## GUI Access (Browser-based Remote Desktop)

The VM includes a graphical desktop environment accessible through your web browser using noVNC.

### Components Installed

- **XFCE Desktop Environment** - Lightweight Linux desktop interface
- **TightVNC Server** - VNC server running on display :1 (port 5901)
- **noVNC** - HTML5 VNC client for browser-based access (port 6080)
- **GUI Applications**: Firefox, gedit, gnome-terminal

### Accessing the GUI

**From anywhere (via HTTPS):**
```
https://devops-vm-43.lrk.si/gui/vnc.html
```

**Locally (if on the host machine):**
```
http://localhost:6080/vnc.html
```

**Credentials:**
- Password: `vagrant`

### What You Can Do

Once connected to the GUI desktop, you can:
- Open Firefox and browse to `http://localhost` to view the Joke app
- Open a terminal to run commands inside the VM
- Use gedit to edit files
- Run any GUI applications installed in the VM

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

# Cloud-Init Deployment

## Overview

This part of the repository describes the cloud-init deployment method for the **Joke-a-Minute** application using **Multipass**. It includes a single YAML configuration file that automatically provisions the complete four-component application stack.


---

## Deployment Environment

- **Host OS**: Windows 11
- **Virtualization**: Multipass (Canonical)
- **Guest OS**: Ubuntu 22.04 LTS
- **Deployment Method**: cloud-init (Infrastructure as Code)

---

## Step-by-Step Deployment

### Step 1: Install Multipass on Windows

1. **Download Multipass**
   https://multipass.run/install

2. **Verify Installation**
   ```powershell
   # Open PowerShell or Command Prompt
   multipass version
   ```
   
   Expected output:
   ```
   multipass   1.x.x
   multipassd  1.x.x
   ```

3. **Check Multipass is Running**
   ```powershell
   multipass list
   ```

### Step 2: Clone the Repository

```powershell
# Open PowerShell
cd C:\Users\YourUsername\Documents

# Clone the repository
git clone https://github.com/Filusion/joke-a-minute_vagrant_cloud-init.git

# Navigate to cloud-init directory
cd joke-a-minute_vagrant_cloud-init\IoC\cloud-init
```

### Step 3: Review the Cloud-Config File

```powershell
# View the cloud-config-multipass.yaml
notepad cloud-config-multipass.yaml
```

The file contains the complete infrastructure definition (explained below).

### Step 4: Launch the VM

```powershell
# Launch VM with cloud-init configuration
multipass launch --name joke-app --cloud-init cloud-config.yaml --memory 2G --disk 10G --cpus 2
```

**What happens:**
- Multipass downloads Ubuntu 22.04 cloud image (if not cached)
- Creates a VM with 2GB RAM, 10GB disk, 2 CPUs
- Applies cloud-init configuration during first boot
- Installs and configures all services automatically

### Step 5: Monitor Provisioning

```powershell
# Check VM status
multipass list

# Wait for cloud-init to complete (this can take 2-3 minutes)
multipass exec joke-app -- cloud-init status --wait
```

**Expected output when complete:**
```
status: done
```

### Step 6: Verify Deployment

```powershell
# Get VM IP address
multipass list

# Check health endpoint
multipass exec joke-app -- curl http://localhost/health
```

**Expected response:**
```json
{
  "mysql": "ok",
  "redis": "ok",
  "status": "healthy",
  "total_jokes": 50
}
```

### Step 7: Access the Application

```powershell
# Get VM IP (e.g., 172.x.x.x)
multipass list

# Open browser to:
http://<VM_IP>

# For HTTPS:
https://<VM_IP>
```

**Note**: You'll get a certificate warning for HTTPS because it uses self-signed certificates. This is expected.

---

## Viewing Logs and Debugging

### View Setup Logs

```powershell
# View complete setup log
multipass exec joke-app -- cat /var/log/joke-app-setup.log

# View last 50 lines
multipass exec joke-app -- tail -50 /var/log/joke-app-setup.log
```

### View Application Logs

```powershell
# Flask application output
multipass exec joke-app -- tail -f /var/log/joke-app.log

# Flask application errors
multipass exec joke-app -- tail -f /var/log/joke-app-error.log

# Cloud-init logs
multipass exec joke-app -- tail -f /var/log/cloud-init-output.log
```

### Check Service Status

```powershell
# Shell into the VM
multipass shell joke-app

# Inside VM - Check all services
sudo systemctl status mysql
sudo systemctl status redis-server
sudo systemctl status joke-app
sudo systemctl status nginx

# Exit VM
exit
```

---

## Management Commands

### Stop/Start VM

```powershell
# Stop VM (preserves state)
multipass stop joke-app

# Start VM
multipass start joke-app

# Restart VM
multipass restart joke-app
```

### Access VM Shell

```powershell
# SSH into VM
multipass shell joke-app

# Run single command without shell
multipass exec joke-app -- <command>
```

### Delete and Redeploy

```powershell
# Delete VM
multipass delete joke-app

# Purge deleted VMs
multipass purge

# Redeploy fresh
multipass launch --name joke-app --cloud-init cloud-config.yaml --memory 2G --disk 10G --cpus 2
```

---

## Cloud-Config.yaml Structure Explanation

### 1. Basic Configuration
```yaml
#cloud-config
hostname: joke-app
fqdn: joke-app.lxd
```
Sets VM hostname and domain name. The `#cloud-config` header is required to identify this as a cloud-init file.

---

### 2. Package Management
```yaml
package_update: true
package_upgrade: false
packages:
  - git, curl, python3, python3-pip, python3-venv
  - mysql-server, redis-server, nginx
```
Updates package lists and installs all required software for the 4-component stack (MySQL, Redis, Flask/Python, Nginx).

---

### 3. Write Files

#### 3.1 Systemd Service for Flask Application
```yaml
- path: /etc/systemd/system/joke-app.service
```
Creates a systemd service that automatically starts the Flask application on boot, restarts it if it crashes, and logs output to files.

#### 3.2 Nginx Reverse Proxy Configuration
```yaml
- path: /etc/nginx/sites-available/joke-app
```
Configures Nginx to listen on port 80 and forward all requests to the Flask app running on port 5000. Acts as a reverse proxy.

#### 3.3 MySQL Configuration
```yaml
- path: /etc/mysql/conf.d/joke-app.cnf
```
Configures MySQL to listen on localhost only for security.

#### 3.4 Setup Script
```yaml
- path: /tmp/setup.sh
```
Main provisioning script that:
- Waits for MySQL to be ready
- Creates database and user
- Clones application from GitHub
- Sets up Python virtual environment
- Installs dependencies
- Initializes database with 50 jokes
- Configures and starts all services

---

### Run Commands (runcmd)

The runcmd section in cloud-init runs after the instance finishes booting.
It performs the full automated setup of the Joke-a-Minute application, installs HTTPS certificates, configures Nginx, and enables secure access.

Below is a detailed explanation of each block:

### 1. Run the Application Setup Script

```yaml
  /tmp/setup.sh
```
This executes the main provisioning script.
It installs and configures all application components:

MySQL database  
Flask API  
Joke generator service  
Joke UI website  
Systemd units for each service  
  
This step completes the entire backend and frontend deployment.  

### 2. Install and Configure mkcert for HTTPS

mkcert is used to generate locally trusted certificates without needing Let's Encrypt or an external CA.

```yaml
- curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
```

Downloads the latest mkcert binary for Linux.

```yaml
- chmod +x mkcert-v*-linux-amd64
- cp mkcert-v*-linux-amd64 /usr/local/bin/mkcert
```

Makes it executable and places it in /usr/local/bin so it is available system-wide.

```yaml
- CAROOT=/root/.local/share/mkcert mkcert -install
```

Initializes mkcert's local Certificate Authority in the root user’s CAROOT directory.

```yaml
- cd /etc/ssl/certs && CAROOT=/root/.local/share/mkcert mkcert -cert-file nginx.crt -key-file /etc/ssl/private/nginx.key localhost 127.0.0.1 $(hostname -I | awk '{print $1}')
```

Generates certificates signed by mkcert for:
  - **localhost**

  - **127.0.0.1**

  - **the VM’s private IP address**

The resulting files:

- **/etc/ssl/certs/nginx.crt**

- **/etc/ssl/private/nginx.key**

are used by Nginx to enable HTTPS.


### 3. Configure Nginx for HTTPS

A full HTTPS-enabled reverse-proxy configuration is written to Nginx:


```yaml
- |
  cat > /etc/nginx/sites-available/joke-app-ssl <<'EOF'
  ...
  EOF
```

This creates a complete Nginx configuration with:

HTTPS reverse proxy (port 443)

  - Uses the mkcert SSL certificate and key
  - Proxies all traffic to the Flask backend at http://127.0.0.1:5000

  - Passes standard headers (Host, X-Forwarded-For, upgrade, etc.)

  - Provides a /health endpoint without logging

#### Automatic HTTP → HTTPS redirect (port 80)  
Forces all insecure connections to HTTPS:
```yaml
return 301 https://$host$request_uri;
```

### 4. Enable the SSL Configuration

```yaml
- rm -f /etc/nginx/sites-enabled/joke-app
```
Removes the old non-SSL configuration if it exists.
```yaml
- ln -sf /etc/nginx/sites-available/joke-app-ssl /etc/nginx/sites-enabled/joke-app-ssl
```
Enables the new HTTPS configuration.
```yaml
- nginx -t && systemctl reload nginx
```
Validates the Nginx config syntax  
Reloads Nginx to apply changes without downtime  
Forces all insecure connections to HTTPS:

---

### Final Message
```yaml
final_message: |
    Cloud-Init Complete!
```
Displays completion message with log file locations for debugging.

---

## Deployment Flow

1. **VM Boot** → Cloud-init starts
2. **Package Installation** → Install MySQL, Redis, Nginx, Python
3. **File Creation** → Write service configs and setup script
4. **Setup Execution** → Clone app, configure services, start everything
5. **SSL Setup** → Generate certificates and enable HTTPS
6. **Ready** → All 4 components running and accessible

---

## Common Issues and Solutions

This section helps you diagnose and fix the most common problems during cloud-init provisioning or when accessing the Joke-a-Minute application.

### Issue: Cloud-init times out
Cloud-init may fail if a package installation or setup step errors out.

**Solution:**
```powershell
# Check logs
multipass exec joke-app -- tail -100 /var/log/cloud-init-output.log

# Look for errors in setup
multipass exec joke-app -- cat /var/log/joke-app-setup.log
```

### Issue: Application not accessible

How to verify that all services are running  

**Solution:**
```powershell
# Check services are running
multipass exec joke-app -- sudo systemctl status joke-app nginx mysql redis-server

# Check if ports are listening
multipass exec joke-app -- sudo netstat -tlnp | grep -E '(:80|:443|:5000|:3306|:6379)'
```

### Issue: Certificate warnings in browser

This happens because mkcert creates locally trusted, not publicly trusted certificates.
**Solution:**
- This is expected with self-signed certificates
- Click "Advanced" → "Proceed to site" (safe for local development)
- For production, use Let's Encrypt certificates

### Issue: VM has no internet access (apt update hangs)
This usually happens when DNS inside the VM is not working.

Test connectivity:

```bash
multipass exec joke-app -- ping -c 3 8.8.8.8     # tests raw network
multipass exec joke-app -- ping -c 3 google.com  # tests DNS
```

If DNS is broken, fix it:

```bash
multipass exec joke-app -- sudo systemctl restart systemd-resolved
```

### Issue: Something else goes wrong

Check all logs at once:

```bash
multipass exec joke-app -- sudo journalctl -xe
```
---

## References

- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [Multipass Documentation](https://multipass.run/docs)
- [Systemd Service Management](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Nginx Configuration](https://nginx.org/en/docs/)


---

# Cloud-Init Deployment with LXD Virtual Machines

## Overview

This document describes the deployment of the Joke-a-Minute application using **LXD Virtual Machines** with cloud-init on the university's Teleport server.

---

## Deployment Environment

- **Host Server**: devops-vm-20.lrk.si (University Teleport Server)
- **Virtualization**: LXD with KVM (Virtual Machines, not containers)
- **Guest OS**: Ubuntu 22.04 LTS
- **Deployment Method**: cloud-init (Infrastructure as Code)
- **Access**: HTTPS with Let's Encrypt SSL certificate

---

## Prerequisites Check

### Step 1: Verify Nested Virtualization Support

Before starting, verify the teleport server supports nested virtualization:

```bash
# Check CPU virtualization support
egrep -c '(vmx|svm)' /proc/cpuinfo
```

**Expected result:** A number greater than 0 (number of CPU cores with virtualization support)

- `vmx` = Intel VT-x
- `svm` = AMD-V

**If result is 0:** Nested virtualization is not enabled. Contact system administrator.

### Step 2: Verify KVM is Available

```bash
# Check if KVM modules are loaded
lsmod | grep kvm

# Expected output:
# kvm_intel (or kvm_amd)
# kvm
```

### Step 3: Check LXD Installation

```bash
# Check LXD version
lxd --version

# If not installed:
sudo snap install lxd
```

---

## Complete Deployment Process

### Step 1: Initialize LXD

```bash
# Initialize LXD (if not already done)
sudo lxd init --auto

# Answer the prompts:
# - Storage pool: yes (use default)
# - Network bridge: yes (use default)
# - Other options: use defaults
```

**Verify LXD is ready:**
```bash
sudo lxc list
```

### Step 2: Clone Repository

```bash
# Create working directory
mkdir -p ~/joke-a-minute
cd ~/joke-a-minute

# Clone the repository
git clone https://github.com/Filusion/joke-a-minute_vagrant_cloud-init.git
cd joke-a-minute_vagrant_cloud-init/IoC/cloud-init
```

### Step 3: Review Cloud-Init Configuration

```bash
# View the cloud-config file
cat cloud-config-LXD.yaml
```

The configuration file defines:
- **4 Components**: MySQL, Redis, Flask, Nginx
- **Automated setup**: Database initialization, application deployment
- **Service management**: Systemd services for all components

### Step 4: Launch LXD Virtual Machine

**Important:** We're using `--vm` flag to create a virtual machine, not a container.

```bash
# Launch VM with cloud-init configuration
sudo lxc launch ubuntu:22.04 joke-app \
  --vm \
  --config=user.user-data="$(cat cloud-config-LXD.yaml)" \
  -c limits.cpu=2 \
  -c limits.memory=2GiB

# The --vm flag creates a KVM virtual machine
# Without --vm, it would create a container (which we don't want)
```

**What happens:**
- LXD downloads Ubuntu 22.04 VM image
- Creates a full virtual machine with 2 CPUs and 2GB RAM
- Applies cloud-init configuration during first boot
- Installs and configures all 4 components automatically

### Step 5: Monitor Provisioning

```bash
# Check VM status (should show "RUNNING" and "VIRTUAL-MACHINE" type)
sudo lxc list

# Expected output:
# +-----------+---------+---------------------+------+-----------------+-----------+
# | NAME      | STATE   | IPV4                | TYPE | SNAPSHOTS       | LOCATION  |
# +-----------+---------+---------------------+------+-----------------+-----------+
# | joke-app  | RUNNING | 10.x.x.x (eth0)    | VIRTUAL-MACHINE | 0       |           |
# +-----------+---------+---------------------+------+-----------------+-----------+

# Wait for cloud-init to complete (2-3 minutes)
sudo lxc exec joke-app -- cloud-init status --wait

# Expected output when complete:
# status: done
```

### Step 6: Verify Deployment

```bash
# Check setup logs
sudo lxc exec joke-app -- cat /var/log/joke-app-setup.log

# Should show all ✓ checkmarks for:
# [1/10] MySQL ready
# [2/10] MySQL database configured
# [3/10] Redis ready
# [4/10] Repository cloned
# [5/10] All required files present
# [6/10] Python packages installed
# [7/10] Database initialized with 50 jokes
# [8/10] Nginx configured
# [9/10] Joke-app service running
# [10/10] Flask app health check passed

# Verify health endpoint
sudo lxc exec joke-app -- curl http://localhost/health
```

**Expected response:**
```json
{
  "mysql": "ok",
  "redis": "ok",
  "status": "healthy",
  "total_jokes": 50
}
```

### Step 7: Check All Services

```bash
# Shell into the VM
sudo lxc exec joke-app -- bash

# Check all 4 components
systemctl status mysql
systemctl status redis-server
systemctl status joke-app
systemctl status nginx

# All should show "active (running)" in green
# Exit the VM
exit
```

---

## Expose Application to the Internet

### Step 1: Configure LXD Proxy Devices

Expose the VM's ports 80 and 443 on the host server:

```bash
# Add HTTP proxy (port 80)
sudo lxc config device add joke-app http80 proxy \
  listen=tcp:0.0.0.0:80 \
  connect=tcp:127.0.0.1:80

# Add HTTPS proxy (port 443)
sudo lxc config device add joke-app https443 proxy \
  listen=tcp:0.0.0.0:443 \
  connect=tcp:127.0.0.1:443

# Verify devices are configured
sudo lxc config device list joke-app
```

**Expected output:**
```
http80
https443
root
```

### Step 2: Configure Firewall

```bash
# Allow HTTP and HTTPS through firewall
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Verify firewall rules
sudo ufw status
```

### Step 3: Test HTTP Access

```bash
# Test from the host server
curl http://devops-vm-20.lrk.si/health

# Should return:
# {"mysql":"ok","redis":"ok","status":"healthy","total_jokes":50}
```

**Access from browser:**
```
http://devops-vm-20.lrk.si
```

---

## Setup HTTPS with Let's Encrypt

### Prerequisites

- Domain name must point to your server's IP
- Ports 80 and 443 must be accessible from the internet
- **Rate Limit**: Let's Encrypt allows 5 certificates per domain per week

### Step 1: Install Certbot in the VM

```bash
# Shell into the VM
sudo lxc exec joke-app -- bash

# Install Certbot and Nginx plugin
apt-get update
apt-get install -y certbot python3-certbot-nginx
```

### Step 2: Obtain SSL Certificate

```bash
# Request certificate from Let's Encrypt
certbot --nginx \
  -d devops-vm-20.lrk.si \
  --non-interactive \
  --agree-tos \
  --email admin@devops-vm-20.lrk.si \
  --redirect

# Exit the VM
exit
```

**What certbot does:**
1. Validates domain ownership via HTTP challenge
2. Obtains SSL certificate from Let's Encrypt
3. Configures Nginx to use the certificate
4. Sets up automatic HTTP → HTTPS redirect
5. Configures auto-renewal

### Step 3: Verify HTTPS

```bash
# Test HTTPS endpoint
curl https://devops-vm-20.lrk.si/health

# Access from browser:
# https://devops-vm-20.lrk.si
```

**Certificate details:**
- **Issued by**: Let's Encrypt
- **Valid for**: 90 days (auto-renewal configured)
- **Renewal**: Automatic via certbot timer

### Step 4: Verify Auto-Renewal

```bash
# Check certbot renewal timer
sudo lxc exec joke-app -- systemctl status certbot.timer

# Test renewal (dry run)
sudo lxc exec joke-app -- certbot renew --dry-run
```

---

## VM Management Commands

### Basic Operations

```bash
# List all VMs
sudo lxc list

# Stop VM
sudo lxc stop joke-app

# Start VM
sudo lxc start joke-app

# Restart VM
sudo lxc restart joke-app

# Shell into VM
sudo lxc exec joke-app -- bash

# Run single command
sudo lxc exec joke-app -- <command>
```

### Monitoring

```bash
# View VM resource usage
sudo lxc info joke-app

# View logs
sudo lxc exec joke-app -- tail -f /var/log/joke-app-setup.log
sudo lxc exec joke-app -- tail -f /var/log/joke-app.log
sudo lxc exec joke-app -- tail -f /var/log/joke-app-error.log

# Check service status
sudo lxc exec joke-app -- systemctl status joke-app mysql redis-server nginx
```

### Cleanup

```bash
# Stop and delete VM
sudo lxc stop joke-app
sudo lxc delete joke-app

# Remove proxy devices (if VM still exists)
sudo lxc config device remove joke-app http80
sudo lxc config device remove joke-app https443

# Verify deletion
sudo lxc list
```

---

## Verification Checklist

After deployment, verify everything is working:

- VM is running and shows "VIRTUAL-MACHINE" type
- Cloud-init status shows "done"
- All 4 services are active (mysql, redis, nginx, joke-app)
- Health endpoint returns all "ok" statuses
- Application accessible via HTTP
- Application accessible via HTTPS
- HTTP automatically redirects to HTTPS
- SSL certificate is valid (Let's Encrypt or self-signed)
- All features work (random joke, add joke, manage jokes)
- Redis caching is functioning (check indicators)

---

## Troubleshooting

### Issue: VM fails to start

```bash
# Check LXD logs
sudo journalctl -u snap.lxd.daemon -n 50

# Check VM console
sudo lxc console joke-app
```

### Issue: Cloud-init fails

```bash
# Check cloud-init logs
sudo lxc exec joke-app -- cat /var/log/cloud-init-output.log

# Check setup script output
sudo lxc exec joke-app -- cat /var/log/joke-app-setup.log
```

### Issue: Services not running

```bash
# Check individual service logs
sudo lxc exec joke-app -- journalctl -u joke-app -n 50
sudo lxc exec joke-app -- journalctl -u mysql -n 50
sudo lxc exec joke-app -- journalctl -u redis-server -n 50
sudo lxc exec joke-app -- journalctl -u nginx -n 50
```

### Issue: Application not accessible

```bash
# Check if VM has IP address
sudo lxc list

# Check if ports are listening in VM
sudo lxc exec joke-app -- netstat -tlnp | grep -E '(:80|:443|:5000)'

# Check proxy devices
sudo lxc config device list joke-app

# Check firewall
sudo ufw status
```

### Issue: Let's Encrypt fails

```bash
# Check if domain resolves correctly
nslookup devops-vm-20.lrk.si

# Check if ports 80/443 are accessible from internet
# (test from external machine)
curl -I http://devops-vm-20.lrk.si
curl -I https://devops-vm-20.lrk.si

# Check certbot logs
sudo lxc exec joke-app -- tail -50 /var/log/letsencrypt/letsencrypt.log
```

### Issue: VM does not get an IP address

If your LXD VM stays stuck without an IP (example: inet: none), it usually means the LXD network bridge (lxdbr0) is misconfigured or the Teleport server firewall blocks DHCP.

#### Solution Steps

**1. Verify that the LXD bridge exists**

```bash
lxc network show lxdbr0
```

You should see something like:

```bash
ipv4.address: 10.x.x.1/24
ipv4.nat: "true"
```

If it is missing, recreate it:

```bash
lxc network create lxdbr0 ipv4.address=10.200.1.1/24 ipv4.nat=true ipv6.address=none  

lxc profile device add default eth0 nic network=lxdbr0 name=eth0
```


**2. Restart the DHCP server (dnsmasq) inside LXD**  

```bash
sudo systemctl reload snap.lxd.daemon
```


Or:

```bash
lxc network restart lxdbr0
```
--- 

### This was the problem I encountered

**LXD VM Not Getting an IPv4 Address**

During deployment on the Teleport server, I ran into a networking issue where newly created LXD VMs did not receive an IPv4 address.
lxc list showed:

IPV4: -

Because of this, cloud-init could not install packages, and the application never started.

After investigation, the root cause was that systemd-resolved was enabled on the host, but it wasn’t functioning correctly.
This broke DNS resolution for LXD, preventing its internal DHCP (dnsmasq) from assigning IP addresses.

**How I fixed it**

I disabled the faulty resolver and replaced /etc/resolv.conf with working DNS entries:

```bash
sudo systemctl disable --now systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```
Then restarted networking:

```bash
sudo systemctl restart systemd-networkd
```
After applying this fix, new LXD VMs immediately started receiving IPv4 addresses and cloud-init provisioning succeeded.

---

## References

- [LXD Virtual Machines Documentation](https://linuxcontainers.org/lxd/docs/latest/virtual-machines/)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [KVM Virtualization](https://www.linux-kvm.org/)
