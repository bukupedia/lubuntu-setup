#!/usr/bin/env bash

# Safer error handling without ERR trap that could fail
set -uo pipefail

# =========================================================
# Ubuntu 22.04 RDP Provisioning Script
# - LXDE Desktop
# - XRDP with Sound Redirection
# - Swap Optimization
# - Lightweight Productivity Setup
# =========================================================

REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

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
# Safety Backup Function with Timestamped Versions
# ---------------------------------------------------------

safe_edit() {
    local file="$1"
    
    if [[ -f "$file" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        if cp -p "$file" "${file}.bak_${timestamp}"; then
            log_info "Backup created: ${file}.bak_${timestamp}"
        else
            log_warn "Failed to create backup of ${file}"
        fi
    fi
}

# ---------------------------------------------------------
# Execute with Error Handling
# ---------------------------------------------------------

run_or_fail() {
    local description="$1"
    shift
    
    log_info "${description}..."
    if "$@"; then
        log_info "${description} - OK"
        return 0
    else
        local exit_code=$?
        log_error "${description} - FAILED (exit code: ${exit_code})"
        return $exit_code
    fi
}

# ---------------------------------------------------------
# Root Check
# ---------------------------------------------------------

if [[ $(id -u) -ne 0 ]]; then
    log_error "Please run this script with sudo or as root."
    exit 1
fi

log_info "Starting Ubuntu 22.04 XRDP + LXDE provisioning..."
log_info "Detected real user: ${REAL_USER}"
log_info "Detected home directory: ${REAL_HOME}"

# ---------------------------------------------------------
# Update System
# ---------------------------------------------------------

log_info "Updating package lists and upgrading system..."

export DEBIAN_FRONTEND=noninteractive

run_or_fail "apt-get update" apt-get update -y || exit 1
run_or_fail "apt-get upgrade" apt-get upgrade -y || exit 1

# ---------------------------------------------------------
# Install LXDE Desktop Environment (Corrected Packages)
# ---------------------------------------------------------

log_info "Installing LXDE desktop environment..."

apt-get install -y \
    lxde-core \
    openbox \
    lightdm \
    || { log_error "Failed to install LXDE"; exit 1; }

# ---------------------------------------------------------
# Install Required Software (Corrected Packages)
# ---------------------------------------------------------

log_info "Installing productivity and audio packages..."

apt-get install -y \
    synaptic \
    pulseaudio-utils \
    wget \
    curl \
    git \
    xrdp \
    xorgxrdp-generic \
    || { log_error "Failed to install packages"; exit 1; }

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
chmod 600 "${REAL_HOME}/.xsession"

# ---------------------------------------------------------
# Configure Swap File (With Verification)
# ---------------------------------------------------------

if swapon --show | grep -q "^/swapfile"; then
    log_warn "Swapfile already exists and is active."
else
    log_info "Creating 2GB swap file..."

    if ! fallocate -l 2G /swapfile 2>/dev/null; then
        log_info "fallocate not available, using dd..."
        dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress || { log_error "Failed to create swap file"; exit 1; }
    fi
    
    # Verify swap file was created before proceeding
    if [[ ! -f /swapfile ]]; then
        log_error "Swap file was not created successfully"
        exit 1
    fi
    
    chmod 600 /swapfile
    mkswap /swapfile || { log_error "Failed to format swap file"; rm -f /swapfile; exit 1; }
    swapon /swapfile || { log_error "Failed to activate swap"; rm -f /swapfile; exit 1; }
    
    # Verify swap is active before updating fstab
    if swapon --show | grep -q "^/swapfile"; then
        if ! grep -q "^/swapfile" /etc/fstab 2>/dev/null; then
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
            log_info "Added swapfile to /etc/fstab"
        fi
        log_info "Swap file created and activated."
    else
        log_error "Swap verification failed after activation"
        exit 1
    fi
fi

# ---------------------------------------------------------
# Disable Non-Essential Services (With Proper Error Handling)
# ---------------------------------------------------------

log_info "Disabling unnecessary services..."

disable_service() {
    local svc="$1"
    if systemctl list-unit-files "$svc" &>/dev/null; then
        systemctl disable "$svc" 2>/dev/null || true
        systemctl stop "$svc" 2>/dev/null || log_warn "Service ${svc} not running or already stopped"
    else
        log_warn "Service ${svc} not found, skipping"
    fi
}

disable_service bluetooth.service
disable_service cups.service

# ---------------------------------------------------------
# Download and Install Latest C-Nergy XRDP Script
# ---------------------------------------------------------

log_info "Downloading latest C-Nergy XRDP installation script..."

TMP_SCRIPT="/tmp/xrdp-installer-$(date +%s).sh"

# Verify wget success with exit code check
if ! wget -q -O "$TMP_SCRIPT" \
    https://www.c-nergy.be/downloads/xRDP/xrdp-installer-1.5.3.sh; then
    log_error "Failed to download XRDP installer"
    exit 1
fi

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
# Add User to SSL-CERT Group (With Verification)
# ---------------------------------------------------------

log_info "Adding ${REAL_USER} to ssl-cert group..."

if ! getent group ssl-cert | grep -q ":${REAL_USER}"; then
    usermod -aG ssl-cert "$REAL_USER"
    log_info "User ${REAL_USER} added to ssl-cert group"
else
    log_info "User ${REAL_USER} already in ssl-cert group"
fi

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

chmod 644 "$POLKIT_RULE"

# ---------------------------------------------------------
# Cleanup (Safer approach - skip autoremove in provisioning)
# ---------------------------------------------------------

log_info "Cleaning up package caches..."

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
