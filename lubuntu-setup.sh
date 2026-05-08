#!/usr/bin/env bash

set -euo pipefail

trap 'echo "[ERROR] Error occurred at line $LINENO. Suggested cleanup: sudo apt-get install -f && sudo dpkg --configure -a"' ERR

# =========================================================
# Ubuntu 22.04 RDP Provisioning Script
# - LXDE Desktop
# - XRDP with Sound Redirection
# - Swap Optimization
# - Lightweight Productivity Setup
# =========================================================

REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo "~${REAL_USER}")

LOG_INFO="[INFO]"
LOG_WARN="[WARN]"
LOG_ERROR="[ERROR]"

# ---------------------------------------------------------
# Logging Helpers
# ---------------------------------------------------------

log_info() {
    echo "${LOG_INFO} $1"
}

log_warn() {
    echo "${LOG_WARN} $1"
}

log_error() {
    echo "${LOG_ERROR} $1"
}

# ---------------------------------------------------------
# Safety Backup Function
# ---------------------------------------------------------

safe_edit() {
    local file="$1"

    if [[ -f "$file" ]]; then
        cp -p "$file" "$file.bak"
        log_info "Backup created: ${file}.bak"
    fi
}

# ---------------------------------------------------------
# Root Check
# ---------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    log_error "Please run this script with sudo or as root."
    exit 1
fi

log_info "Starting Ubuntu 22.04 XRDP + LXDE provisioning..."
log_info "Detected real user: ${REAL_USER}"

# ---------------------------------------------------------
# Update System
# ---------------------------------------------------------

log_info "Updating package lists and upgrading system..."

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y

# ---------------------------------------------------------
# Install LXDE Desktop Environment
# ---------------------------------------------------------

log_info "Installing LXDE desktop environment..."

apt-get install -y \
    lxde-core \
    lxsession \
    openbox \
    lightdm

# ---------------------------------------------------------
# Install Required Software
# ---------------------------------------------------------

log_info "Installing productivity and audio packages..."

apt-get install -y \
    synaptic \
    pulseaudio-utils \
    wget \
    curl \
    git \
    xorgxrdp

# ---------------------------------------------------------
# Configure LXDE as Default XRDP Session
# ---------------------------------------------------------

log_info "Configuring LXDE as default XRDP session..."

XRDP_STARTWM="/etc/xrdp/startwm.sh"

safe_edit "$XRDP_STARTWM"

cat > "$XRDP_STARTWM" <<'EOF'
#!/bin/sh

if [ -r /etc/profile ]; then
    . /etc/profile
fi

if [ -r ~/.profile ]; then
    . ~/.profile
fi

export DESKTOP_SESSION=LXDE
export XDG_SESSION_DESKTOP=LXDE
export XDG_CURRENT_DESKTOP=LXDE

exec startlxde
EOF

chmod +x "$XRDP_STARTWM"

# ---------------------------------------------------------
# Create .xsession for User
# ---------------------------------------------------------

log_info "Creating LXDE xsession for user: ${REAL_USER}"

cat > "${REAL_HOME}/.xsession" <<'EOF'
startlxde
EOF

chown "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/.xsession"

# ---------------------------------------------------------
# Configure Swap File
# ---------------------------------------------------------

if swapon --show | grep -q "/swapfile"; then
    log_warn "Swapfile already exists and is active."
else
    log_info "Creating 2GB swap file..."

    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048

    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    if ! grep -q "^/swapfile" /etc/fstab; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi

    log_info "Swap file created and activated."
fi

# ---------------------------------------------------------
# Disable Non-Essential Services
# ---------------------------------------------------------

log_info "Disabling unnecessary services..."

systemctl disable bluetooth.service || true
systemctl stop bluetooth.service || true

systemctl disable cups.service || true
systemctl stop cups.service || true

# ---------------------------------------------------------
# Download and Install Latest C-Nergy XRDP Script
# ---------------------------------------------------------

log_info "Downloading latest C-Nergy XRDP installation script..."

TMP_SCRIPT="/tmp/xrdp-installer.sh"

wget -O "$TMP_SCRIPT" \
https://www.c-nergy.be/downloads/xRDP/xrdp-installer-1.5.3.sh

chmod +x "$TMP_SCRIPT"

# ---------------------------------------------------------
# Run XRDP Installer Non-Interactively
# ---------------------------------------------------------

log_info "Running XRDP installer in non-interactive mode with sound redirection..."

# Flags explanation:
# -s : sound redirection
# -l : install latest XRDP packages
# -n : no reboot
# -a : automatic install/no prompts

bash "$TMP_SCRIPT" -s -l -n -a

# ---------------------------------------------------------
# Enable XRDP Service
# ---------------------------------------------------------

log_info "Enabling and restarting XRDP service..."

systemctl enable xrdp
systemctl restart xrdp

# ---------------------------------------------------------
# Add User to SSL-CERT Group
# ---------------------------------------------------------

log_info "Adding ${REAL_USER} to ssl-cert group..."

usermod -aG ssl-cert "$REAL_USER"

# ---------------------------------------------------------
# XRDP Polkit Fix
# ---------------------------------------------------------

log_info "Applying XRDP polkit compatibility configuration..."

POLKIT_RULE="/etc/polkit-1/localauthority.conf.d/02-allow-colord.conf"

safe_edit "$POLKIT_RULE"

mkdir -p /etc/polkit-1/localauthority.conf.d

cat > "$POLKIT_RULE" <<'EOF'
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.color-manager.create-device" ||
         action.id == "org.freedesktop.color-manager.create-profile" ||
         action.id == "org.freedesktop.color-manager.delete-device" ||
         action.id == "org.freedesktop.color-manager.delete-profile" ||
         action.id == "org.freedesktop.color-manager.modify-device" ||
         action.id == "org.freedesktop.color-manager.modify-profile") &&
         subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
EOF

# ---------------------------------------------------------
# Cleanup
# ---------------------------------------------------------

log_info "Cleaning unnecessary packages..."

apt-get autoremove -y
apt-get autoclean -y

# ---------------------------------------------------------
# Final Status Output
# ---------------------------------------------------------

log_info "Provisioning completed successfully."

echo
echo "=================================================="
echo "XRDP Service Status:"
systemctl --no-pager status xrdp | head -n 10
echo "=================================================="

echo
echo "Swap Status:"
swapon --show
echo "=================================================="

echo
echo "Desktop configured: LXDE"
echo "Sound redirection enabled: YES"
echo "=================================================="

echo
log_info "A reboot is strongly recommended."
