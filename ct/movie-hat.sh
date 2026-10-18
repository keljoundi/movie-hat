#!/usr/bin/env bash
# Copyright (c) 2026 Movie Hat
# License: MIT
# Proxmox VE LXC Deployment Script for The Movie Hat

set -Eeuo pipefail

# Visual Formatting
RD="\033[01;31m"
YW="\033[33m"
GN="\033[1;92m"
BL="\033[36m"
BGN="\033[4;92m"
CL="\033[m"
CM=" \u2714 "
CROSS=" \u2716 "

APP="The Movie Hat"
DEFAULT_TAGS="media;movies"
DEFAULT_CPU="1"
DEFAULT_RAM="1024"
DEFAULT_DISK="4"
DEFAULT_OS="debian"
DEFAULT_OS_VERSION="12"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_HOSTNAME="movie-hat"
DEFAULT_REPO="keljoundi/movie-hat"
GITHUB_REPO="${GITHUB_REPO:-$DEFAULT_REPO}"
RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"

msg_info() {
  echo -e "${BL}[INFO]${CL} $1"
}
msg_ok() {
  echo -e "${GN}[OK]${CL} $1"
}
msg_err() {
  echo -e "${RD}[ERROR]${CL} $1"
}
msg_warn() {
  echo -e "${YW}[WARN]${CL} $1"
}

# Verify Root & Proxmox VE Environment
if [ "$(id -u)" -ne 0 ]; then
  msg_err "This script must be run as root on the Proxmox VE host."
  exit 1
fi

if ! command -v pveversion >/dev/null 2>&1 || ! command -v pct >/dev/null 2>&1; then
  msg_err "This script can only be executed on a Proxmox VE host node (pct/pveversion not found)."
  exit 1
fi

clear
cat << "EOF"
  __  __            _        _   _       _
 |  \/  |          (_)      | | | |     | |
 | \  / | _____   ___  ___  | |_| | __ _| |_
 | |\/| |/ _ \ \ / / |/ _ \ |  _  |/ _` | __|
 | |  | | (_) \ V /| |  __/ | | | | (_| | |_
 |_|  |_|\___/ \_/ |_|\___| |_| |_|\__,_|\__|

           Proxmox VE LXC Installer
EOF
echo ""

if ! whiptail --backtitle "Proxmox VE Helper - ${APP}" --title "${APP} LXC Setup" --yesno "This script will create a new LXC container for ${APP}.\n\nDo you want to proceed?" 10 58; then
  msg_info "Installation cancelled by user."
  exit 0
fi

# Configuration Mode (Default vs Advanced)
CHOICE=$(whiptail --backtitle "Proxmox VE Helper - ${APP}" --title "Configuration Mode" --menu "Choose container configuration type:" 12 58 2 \
  "1" "Default Settings (Recommended: 1 CPU, 1024MB RAM, 4GB Disk, DHCP)" \
  "2" "Advanced Settings (Custom specs, storage, static IP, etc.)" \
  3>&1 1>&2 2>&3)

CTID=$(pvesh get /cluster/nextid)
HOSTNAME="$DEFAULT_HOSTNAME"
CORES="$DEFAULT_CPU"
RAM="$DEFAULT_RAM"
DISK_SIZE="${DEFAULT_DISK}G"
BRIDGE="$DEFAULT_BRIDGE"
NET_CONFIG="dhcp"
UNPRIVILEGED="1"

# Determine default storage pool supporting rootdir
DEFAULT_STORAGE=$(pvesm status -content rootdir | awk 'NR>1 {print $1; exit}')
if [ -z "$DEFAULT_STORAGE" ]; then
  DEFAULT_STORAGE="local-lvm"
fi
STORAGE="$DEFAULT_STORAGE"

if [ "$CHOICE" == "2" ]; then
  CTID=$(whiptail --backtitle "Proxmox VE Helper - ${APP}" --inputbox "Set Container ID:" 8 58 "$CTID" --title "Container ID" 3>&1 1>&2 2>&3)
  HOSTNAME=$(whiptail --backtitle "Proxmox VE Helper - ${APP}" --inputbox "Set Hostname:" 8 58 "$HOSTNAME" --title "Hostname" 3>&1 1>&2 2>&3)
  CORES=$(whiptail --backtitle "Proxmox VE Helper - ${APP}" --inputbox "Allocate CPU Cores:" 8 58 "$CORES" --title "CPU Cores" 3>&1 1>&2 2>&3)
  RAM=$(whiptail --backtitle "Proxmox VE Helper - ${APP}" --inputbox "Allocate RAM (MB):" 8 58 "$RAM" --title "RAM Allocation" 3>&1 1>&2 2>&3)
  DISK_INPUT=$(whiptail --backtitle "Proxmox VE Helper - ${APP}" --inputbox "Allocate Disk Size (GB):" 8 58 "${DEFAULT_DISK}" --title "Disk Size" 3>&1 1>&2 2>&3)
  DISK_SIZE="${DISK_INPUT}G"

  STORAGE_POOLS=()
  while IFS= read -r line; do
    [ -n "$line" ] && STORAGE_POOLS+=("$line" "")
  done < <(pvesm status -content rootdir | awk 'NR>1 {print $1}')

  if [ "${#STORAGE_POOLS[@]}" -gt 0 ]; then
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper - ${APP}" --title "Root Disk Storage" --menu "Select storage pool:" 14 58 5 "${STORAGE_POOLS[@]}" 3>&1 1>&2 2>&3)
  fi

  BRIDGE=$(whiptail --backtitle "Proxmox VE Helper - ${APP}" --inputbox "Network Bridge:" 8 58 "$BRIDGE" --title "Network Bridge" 3>&1 1>&2 2>&3)

  NET_TYPE=$(whiptail --backtitle "Proxmox VE Helper - ${APP}" --title "IP Assignment" --menu "Choose IP configuration:" 10 58 2 \
    "dhcp" "Automatic (DHCP)" \
    "static" "Manual Static IP" 3>&1 1>&2 2>&3)

  if [ "$NET_TYPE" == "static" ]; then
    STATIC_IP=$(whiptail --backtitle "Proxmox VE Helper - ${APP}" --inputbox "Enter IPv4 Address with CIDR (e.g. 192.168.1.150/24):" 8 58 "192.168.1.150/24" --title "Static IPv4" 3>&1 1>&2 2>&3)
    GATEWAY=$(whiptail --backtitle "Proxmox VE Helper - ${APP}" --inputbox "Enter Gateway IPv4 (e.g. 192.168.1.1):" 8 58 "192.168.1.1" --title "Gateway IPv4" 3>&1 1>&2 2>&3)
    NET_CONFIG="${STATIC_IP},gw=${GATEWAY}"
  fi

  if whiptail --backtitle "Proxmox VE Helper - ${APP}" --title "Unprivileged Container" --yesno "Create unprivileged container (recommended for security)?" 8 58; then
    UNPRIVILEGED="1"
  else
    UNPRIVILEGED="0"
  fi
fi

msg_info "Validating container template storage..."
TEMPLATE_STORAGE=$(pvesm status -content vztmpl | awk 'NR>1 {print $1; exit}')
if [ -z "$TEMPLATE_STORAGE" ]; then
  TEMPLATE_STORAGE="local"
fi

msg_info "Updating Proxmox appliance template database..."
pveam update >/dev/null 2>&1 || true

TEMPLATE_NAME=$(pveam available -section system | awk '{print $2}' | grep -E "^debian-12-standard_.*\.tar\.(zst|gz)$" | tail -n 1)
if [ -z "$TEMPLATE_NAME" ]; then
  msg_err "Could not find Debian 12 standard template in pveam repository."
  exit 1
fi

LOCAL_TEMPLATE_PATH=$(pvesm path "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_NAME}" 2>/dev/null || true)
if [ ! -f "$LOCAL_TEMPLATE_PATH" ]; then
  msg_info "Downloading container template (${TEMPLATE_NAME})..."
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_NAME"
fi

msg_info "Creating LXC container (${CTID} - ${HOSTNAME})..."
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_NAME}" \
  --ostype debian \
  --hostname "$HOSTNAME" \
  --cores "$CORES" \
  --memory "$RAM" \
  --swap 512 \
  --rootfs "${STORAGE}:${DISK_SIZE}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=${NET_CONFIG},type=veth" \
  --unprivileged "$UNPRIVILEGED" \
  --features nesting=1,keyctl=1 \
  --tags "$DEFAULT_TAGS" \
  --description "<h1>The Movie Hat</h1><p>Full-Stack Movie Selection Hat & Watchlist Manager</p>" \
  --onboot 1

msg_info "Starting LXC container ${CTID}..."
pct start "$CTID"

msg_info "Waiting for container network initialization..."
attempts=0
while [ $attempts -lt 30 ]; do
  if pct exec "$CTID" -- ip -4 addr show eth0 2>/dev/null | grep -q "inet "; then
    break
  fi
  sleep 1
  attempts=$((attempts + 1))
done

# Wait for DNS resolution inside container
attempts=0
while [ $attempts -lt 15 ]; do
  if pct exec "$CTID" -- ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    break
  fi
  sleep 1
  attempts=$((attempts + 1))
done

msg_info "Invoking Movie Hat in-container installation script..."
pct exec "$CTID" -- env GITHUB_REPO="$GITHUB_REPO" bash -c "$(curl -fsSL "${RAW_BASE_URL}/install/movie-hat-install.sh")"

# Retrieve container IPv4
IP_ADDRESS=$(pct exec "$CTID" -- ip -4 addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1)

msg_ok "${APP} LXC setup completed successfully!"
echo -e "\n${GN}================================================================${CL}"
echo -e "  🎉 ${BGN}${APP} is running in Proxmox LXC ${CTID}!${CL}"
echo -e "${GN}================================================================${CL}"
echo -e "  🌐 Web Interface:      ${BL}http://${IP_ADDRESS}:3000${CL}"
echo -e "  📁 Persistent DB:     ${YW}/srv/movies.db${CL}"
echo -e "  ⚙️ Service Command:    ${YW}systemctl status movie-hat${CL}"
echo -e "  🔄 In-Container Update:${YW}update${CL}"
echo -e "${GN}================================================================${CL}"
echo -e "Next steps:"
echo -e "  1. Open ${BL}http://${IP_ADDRESS}:3000${CL} in your browser."
echo -e "  2. Complete the initial Admin Account Setup wizard."
echo -e "  3. (Optional) Provide your TMDb API Key during setup or on Settings."
echo -e "${GN}================================================================${CL}\n"
