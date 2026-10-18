#!/usr/bin/env bash
# Copyright (c) 2026 Movie Hat
# License: MIT
# Container-Side In-Place Update Script for The Movie Hat

set -Eeuo pipefail

RD="\033[01;31m"
YW="\033[33m"
GN="\033[1;92m"
BL="\033[36m"
CL="\033[m"

APP_DIR="/srv/movie-hat"
DEFAULT_REPO="keljoundi/movie-hat"
GITHUB_REPO="${GITHUB_REPO:-$DEFAULT_REPO}"

msg_info() { echo -e "${BL}[INFO]${CL} $1"; }
msg_ok()   { echo -e "${GN}[OK]${CL} $1"; }
msg_err()  { echo -e "${RD}[ERROR]${CL} $1"; }
msg_warn() { echo -e "${YW}[WARN]${CL} $1"; }

if [ "$(id -u)" -ne 0 ]; then
  msg_err "This update script must be run as root."
  exit 1
fi

if [ ! -d "$APP_DIR" ] || [ ! -f "$APP_DIR/package.json" ]; then
  msg_err "Movie Hat installation not found at $APP_DIR."
  exit 1
fi

CURRENT_VER=$(node -e "try { console.log(require('${APP_DIR}/package.json').version); } catch(e) { console.log('unknown'); }")

msg_info "Checking for updates from ${GITHUB_REPO}..."
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null || true)

if [ -z "$RELEASE_JSON" ] || ! echo "$RELEASE_JSON" | grep -q '"tag_name"'; then
  msg_err "Failed to query GitHub Releases API for ${GITHUB_REPO}."
  msg_warn "Please check container internet connectivity or GitHub API rate limits."
  exit 1
fi

LATEST_TAG=$(echo "$RELEASE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4)
LATEST_VER="${LATEST_TAG#v}"

DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*\.tar\.gz"' | head -n 1 | cut -d'"' -f4)

if [ -z "$DOWNLOAD_URL" ]; then
  # Fallback to standard release asset URL format
  DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_TAG}/movie-hat-${LATEST_TAG}.tar.gz"
fi

echo -e "\n  Current version: ${YW}${CURRENT_VER}${CL}"
echo -e "  Latest version:  ${GN}${LATEST_VER}${CL} (${LATEST_TAG})\n"

if [ "$CURRENT_VER" = "$LATEST_VER" ]; then
  read -r -p "You already have the latest version installed. Reinstall? [y/N] " response
  case "$response" in
    [yY][eE][sS]|[yY])
      msg_info "Proceeding with reinstallation..."
      ;;
    *)
      msg_ok "Movie Hat is up to date."
      exit 0
      ;;
  esac
fi

msg_info "Stopping movie-hat service..."
systemctl stop movie-hat

# Preserve .env file
if [ -f "$APP_DIR/.env" ]; then
  cp "$APP_DIR/.env" /tmp/.movie-hat-env.bak
fi

TMP_ARCHIVE="/tmp/movie-hat-update.tar.gz"
msg_info "Downloading update archive (${DOWNLOAD_URL})..."
curl -fsSL -o "$TMP_ARCHIVE" "$DOWNLOAD_URL"

msg_info "Extracting new release files into ${APP_DIR}..."
tar -xzf "$TMP_ARCHIVE" -C "$APP_DIR"
rm -f "$TMP_ARCHIVE"

# Restore preserved .env
if [ -f /tmp/.movie-hat-env.bak ]; then
  cp /tmp/.movie-hat-env.bak "$APP_DIR/.env"
  rm -f /tmp/.movie-hat-env.bak
fi

msg_info "Updating production dependencies..."
cd "$APP_DIR"
npm install --omit=dev --no-audit --no-fund

msg_info "Restarting movie-hat service..."
systemctl start movie-hat

# Verify service is running
sleep 2
if systemctl is-active --quiet movie-hat; then
  msg_ok "The Movie Hat updated successfully to v${LATEST_VER}!"
else
  msg_warn "Service did not start immediately. Check logs with: journalctl -u movie-hat -n 50"
fi
