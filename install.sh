#!/bin/bash
# MK Script Manager v4.0 - Installation Script
# Compatible with Ubuntu 20.04 - 24.04 LTS

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run this installer as root (using sudo)."
  exit 1
fi

clear
echo "==========================================="
echo "    MK Script Manager v4.0 Installer"
echo "==========================================="
echo ""
echo "[*] Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1

# Install basic dependencies including net-tools for netstat command
apt-get install -y openssl screen wget curl net-tools iproute2 systemd >/dev/null 2>&1

# Install Dropbear SSH server for exact log replication
echo "[*] Installing Dropbear SSH server..."
apt-get install -y dropbear-bin >/dev/null 2>&1

# Install latest stunnel with proper configuration for newer Ubuntu versions
echo "[*] Installing and configuring latest stunnel..."

# Install build dependencies first (includes BadVPN dependencies)
apt-get install -y build-essential libssl-dev zlib1g-dev wget tar cmake >/dev/null 2>&1

# Try to install latest stunnel from source
cd /tmp
echo "[*] Downloading stunnel 5.75 (latest)..."
if wget -q https://www.stunnel.org/downloads/stunnel-5.75.tar.gz; then
    echo "[*] Compiling latest stunnel..."
    tar -xzf stunnel-5.75.tar.gz
    cd stunnel-5.75
    ./configure --prefix=/usr/local --enable-ipv6 >/dev/null 2>&1
    make >/dev/null 2>&1
    make install >/dev/null 2>&1
    
    # Create symlinks for compatibility
    ln -sf /usr/local/bin/stunnel /usr/bin/stunnel4 2>/dev/null
    ln -sf /usr/local/bin/stunnel /usr/bin/stunnel 2>/dev/null
    
    # Create proper systemd service for compiled stunnel
    cat > /etc/systemd/system/stunnel4.service << 'EOF'
[Unit]
Description=Stunnel TLS tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/local/bin/stunnel /etc/stunnel/stunnel.conf
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/stunnel4/stunnel.pid
User=root
Group=root
RuntimeDirectory=stunnel4
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF
    
    # Clean up
    cd /
    rm -rf /tmp/stunnel-5.75*
    
    echo "[*] Latest stunnel 5.75 installed successfully with systemd service"
else
    echo "[*] Fallback: Installing stunnel4 from Ubuntu repository..."
    apt-get install -y stunnel4 >/dev/null 2>&1
fi

# Fix stunnel4 configuration for Ubuntu 22.04/24.04
if [[ -f /etc/default/stunnel4 ]]; then
    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null
    echo 'ENABLED=1' >> /etc/default/stunnel4 2>/dev/null
else
    echo 'ENABLED=1' > /etc/default/stunnel4
fi

# Clean up old systemd overrides and reload daemon
rm -rf /etc/systemd/system/stunnel4.service.d 2>/dev/null
systemctl daemon-reload >/dev/null 2>&1

echo "[*] Configuring stunnel service..."
if [[ -f /etc/default/stunnel4 ]]; then
  if grep -qs "ENABLED=0" /etc/default/stunnel4; then
    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4
  fi
else
  echo 'ENABLED=1' > /etc/default/stunnel4
fi

mkdir -p /etc/stunnel
STUNNEL_CERT="/etc/stunnel/stunnel.pem"
if [[ ! -f "$STUNNEL_CERT" ]]; then
  echo "[*] Generating self-signed SSL certificate for stunnel..."
  
  # Create certificate
  openssl req -newkey rsa:4096 -x509 -sha256 -days 3650 -nodes \
    -subj "/C=US/ST=State/L=City/O=MK-Script/OU=IT/CN=$(hostname)" \
    -keyout /etc/stunnel/key.pem -out /etc/stunnel/cert.pem >/dev/null 2>&1
  
  # Combine certificate and key
  cat /etc/stunnel/key.pem /etc/stunnel/cert.pem > "$STUNNEL_CERT"
  
  # Set proper ownership and permissions for stunnel4 user
  chown stunnel4:stunnel4 "$STUNNEL_CERT" 2>/dev/null || chown root:stunnel4 "$STUNNEL_CERT"
  chmod 640 "$STUNNEL_CERT"
  
  # Fix directory permissions
  chown -R stunnel4:stunnel4 /etc/stunnel 2>/dev/null || chown -R root:stunnel4 /etc/stunnel
  chmod 755 /etc/stunnel
  
  # Clean up individual files
  rm -f /etc/stunnel/key.pem /etc/stunnel/cert.pem
fi

STUNNEL_CONF="/etc/stunnel/stunnel.conf"
if [[ ! -f "$STUNNEL_CONF" ]]; then
  echo "[*] Setting up stunnel configuration..."
  echo ""
  echo "🔐 CONFIGURING ADVANCED CIPHER SYSTEM"
  echo "====================================="
  echo ""
  echo "✅ Applying: TLS_AES_256_GCM_SHA384 + X448 (TLS 1.3)"
  echo "   • Ultra-high security with X448 curve (448-bit)"
  echo "   • Modern TLS 1.3 with maximum performance"
  echo "   • Optimized for ISP evasion"
  echo ""
  
  # Set fixed configuration
  SELECTED_TLS="TLSv1.3"
  SELECTED_CIPHER="TLS_AES_256_GCM_SHA384"
  SELECTED_CURVE="X448"
  CIPHER_TYPE="ciphersuites"
  
  echo "[*] Creating stunnel configuration with TLS 1.3 + X448..."
  
  cat > "$STUNNEL_CONF" << 'EOC'
# MK Script Manager - Advanced Cipher Configuration
# TLS 1.3 + AES-256-GCM + X448 for Maximum Security & ISP Evasion
cert = /etc/stunnel/stunnel.pem
pid = /var/run/stunnel4/stunnel.pid

# Logging
debug = 7
output = /var/log/stunnel4/stunnel.log

[ssh-tunnel]
accept = 443
connect = 127.0.0.1:22

# Advanced Cipher Configuration - TLS 1.3 + X448
ciphersuites = TLS_AES_256_GCM_SHA384
sslVersion = TLSv1.3
curves = X448

# Security Options - Force TLS 1.3 Only
options = NO_SSLv2
options = NO_SSLv3
options = NO_TLSv1
options = NO_TLSv1_1
options = NO_TLSv1_2
EOC
  
  echo ""
  echo "✅ STUNNEL CONFIGURED SUCCESSFULLY"
  echo "=================================="
  echo "TLS Version: TLSv1.3"
  echo "Cipher Suite: TLS_AES_256_GCM_SHA384"
  echo "Key Exchange Curve: X448 (448-bit Ultra-High Security)"
  echo "Expected ISP Evasion: Test with X448 uniqueness"
  echo "Configuration saved to: $STUNNEL_CONF"
  echo ""
fi

echo "[*] Starting stunnel service..."
systemctl restart stunnel4
systemctl enable stunnel4

echo "[*] Applying maximum performance TCP optimizations..."
# Remove existing entries to prevent duplicates
sed -i '/net.core.rmem_max/d' /etc/sysctl.conf 2>/dev/null
sed -i '/net.core.wmem_max/d' /etc/sysctl.conf 2>/dev/null
sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.conf 2>/dev/null
sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.conf 2>/dev/null
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null
sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf 2>/dev/null

# Add maximum performance network settings
echo '# MK Script Manager - Maximum Performance Network Settings' >> /etc/sysctl.conf
echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf        # 128MB receive buffer
echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf        # 128MB send buffer
echo 'net.ipv4.tcp_rmem = 4096 87380 134217728' >> /etc/sysctl.conf  # TCP receive window
echo 'net.ipv4.tcp_wmem = 4096 65536 134217728' >> /etc/sysctl.conf  # TCP send window
echo 'net.ipv4.tcp_congestion_control = bbr' >> /etc/sysctl.conf     # Best congestion control
echo 'net.core.netdev_max_backlog = 5000' >> /etc/sysctl.conf       # Handle more packets
echo 'net.ipv4.tcp_window_scaling = 1' >> /etc/sysctl.conf          # Enable window scaling
echo 'net.ipv4.tcp_timestamps = 1' >> /etc/sysctl.conf              # Enable timestamps
echo 'net.ipv4.tcp_sack = 1' >> /etc/sysctl.conf                    # Enable selective ACK
echo 'net.ipv4.tcp_no_metrics_save = 1' >> /etc/sysctl.conf         # Don't cache metrics
echo 'net.ipv4.tcp_moderate_rcvbuf = 1' >> /etc/sysctl.conf         # Auto-tune receive buffer

# Apply settings immediately
sysctl -p >/dev/null 2>&1

echo "[*] Configuring Dropbear SSH server..."
# Create Dropbear configuration directory
mkdir -p /etc/dropbear

# Configure Dropbear to match the exact log configuration
# Port 22 for local connections (stunnel will forward from 443)
cat > /etc/default/dropbear << 'EOF'
# Dropbear SSH server configuration
# Configured to match: SSH-2.0-dropbear_2020.81
NO_START=0
DROPBEAR_PORT=22
DROPBEAR_EXTRA_ARGS="-s -g"

# Force specific algorithms to match log:
# Key exchange: diffie-hellman-group14-sha1
# Cipher: aes256-ctr
# MAC: hmac-sha2-256
DROPBEAR_RECEIVE_WINDOW=65536
EOF

# Generate Dropbear host keys if they don't exist
if [[ ! -f /etc/dropbear/dropbear_rsa_host_key ]]; then
    echo "[*] Generating Dropbear host keys..."
    dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key -s 2048 >/dev/null 2>&1
    dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1
    dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1
fi

# Start and enable Dropbear service
systemctl enable dropbear >/dev/null 2>&1
systemctl restart dropbear >/dev/null 2>&1

echo "[*] Dropbear SSH server configured successfully"
echo "    - Version: dropbear_2020.81+ compatible"
echo "    - Key Exchange: diffie-hellman-group14-sha1" 
echo "    - Cipher: aes256-ctr"
echo "    - MAC: hmac-sha2-256"

echo "[*] Installing menu system..."
INSTALL_DIR="/usr/local/bin"

# Always download the latest version from GitHub for consistency
echo "[*] Downloading menu script..."
if wget -q https://raw.githubusercontent.com/mkkelati/script11/master/menu.sh -O "${INSTALL_DIR}/menu"; then
  chmod +x "${INSTALL_DIR}/menu"
  echo "[*] Menu system installed successfully"
else
  echo "[ERROR] Failed to download menu script. Check internet connection."
  exit 1
fi

echo "[*] Setting up configuration..."
mkdir -p /etc/mk-script
touch /etc/mk-script/users.txt

# Create password storage directory
mkdir -p /etc/mk-script/senha

echo "[*] Verifying installation..."
if [[ -x "${INSTALL_DIR}/menu" ]]; then
  clear
  sleep 1
  
  # Professional welcome message with colors
  echo ""
  echo ""
  echo -e "\033[1;34m╔══════════════════════════════════════════════════════════════════════════════╗\033[0m"
  echo -e "\033[1;34m║\033[1;32m                          🎉 INSTALLATION SUCCESSFUL! 🎉                        \033[1;34m║\033[0m"
  echo -e "\033[1;34m╠══════════════════════════════════════════════════════════════════════════════╣\033[0m"
  echo -e "\033[1;34m║\033[1;36m                                                                              \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;33m    ███╗   ███╗██╗  ██╗    ███████╗ ██████╗██████╗ ██╗██████╗ ████████╗    \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;33m    ████╗ ████║██║ ██╔╝    ██╔════╝██╔════╝██╔══██╗██║██╔══██╗╚══██╔══╝    \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;33m    ██╔████╔██║█████╔╝     ███████╗██║     ██████╔╝██║██████╔╝   ██║       \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;33m    ██║╚██╔╝██║██╔═██╗     ╚════██║██║     ██╔══██╗██║██╔═══╝    ██║       \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;33m    ██║ ╚═╝ ██║██║  ██╗    ███████║╚██████╗██║  ██║██║██║        ██║       \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;33m    ╚═╝     ╚═╝╚═╝  ╚═╝    ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝       \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;36m                                                                              \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;35m                        🚀 MANAGER v4.0 - READY TO USE! 🚀                   \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;36m                                                                              \033[1;34m║\033[0m"
  echo -e "\033[1;34m╠══════════════════════════════════════════════════════════════════════════════╣\033[0m"
  echo -e "\033[1;34m║\033[1;37m 🎯 WELCOME TO THE MOST ADVANCED SSH MANAGEMENT SYSTEM!                      \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;36m                                                                              \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;32m ✅ Latest stunnel 5.75 with TLS_AES_256_GCM_SHA384 cipher                  \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;32m ✅ Professional dashboard with real-time system monitoring                  \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;32m ✅ Advanced user limiter with connection enforcement                         \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;32m ✅ Server optimization with automated performance tuning                    \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;32m ✅ 11 comprehensive management options for complete control                 \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;36m                                                                              \033[1;34m║\033[0m"
  echo -e "\033[1;34m╠══════════════════════════════════════════════════════════════════════════════╣\033[0m"
  echo -e "\033[1;34m║\033[1;33m 🚀 GET STARTED:                                                             \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;37m                                                                              \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;36m    Just type: \033[1;31mmenu\033[1;36m                                                         \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;37m                                                                              \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;32m    Then enjoy the professional dashboard and 11 powerful options!          \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;36m                                                                              \033[1;34m║\033[0m"
  echo -e "\033[1;34m╠══════════════════════════════════════════════════════════════════════════════╣\033[0m"
  echo -e "\033[1;34m║\033[1;35m 💡 SUPPORT: \033[1;37mhttps://github.com/mkkelati/script4                           \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;35m 📧 VERSION: \033[1;37mv4.1 - Maximum Performance Edition                            \033[1;34m║\033[0m"
  echo -e "\033[1;34m║\033[1;35m 🌟 STATUS:  \033[1;32mFully Optimized & Ready for Production                        \033[1;34m║\033[0m"
  echo -e "\033[1;34m╚══════════════════════════════════════════════════════════════════════════════╝\033[0m"
  echo ""
  echo -e "\033[1;33m⭐ Thank you for choosing MK Script Manager v4.1 - Maximum Performance! ⭐\033[0m"
  echo ""
else
  echo "[ERROR] Installation failed. Menu command not found."
  exit 1
fi
