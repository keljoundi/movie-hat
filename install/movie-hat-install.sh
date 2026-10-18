#!/usr/bin/env bash
# Copyright (c) 2026 Movie Hat
# License: MIT
# Container Guest Installation Script for The Movie Hat

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

RD="\033[01;31m"
YW="\033[33m"
GN="\033[1;92m"
BL="\033[36m"
CL="\033[m"

APP_DIR="/srv/movie-hat"
DB_FILE="/srv/movies.db"
DEFAULT_REPO="keljoundi/movie-hat"
GITHUB_REPO="${GITHUB_REPO:-$DEFAULT_REPO}"
RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"

msg_info() { echo -e "${BL}[INFO]${CL} $1"; }
msg_ok()   { echo -e "${GN}[OK]${CL} $1"; }
msg_err()  { echo -e "${RD}[ERROR]${CL} $1"; }
msg_warn() { echo -e "${YW}[WARN]${CL} $1"; }

msg_info "Updating container package indices..."
apt-get update -y

msg_info "Installing prerequisite system packages..."
apt-get install -y curl sudo sqlite3 ca-certificates gnupg tar openssl

# Install Node.js 22 LTS if not present or outdated
NEED_NODE=0
if ! command -v node >/dev/null 2>&1; then
  NEED_NODE=1
else
  NODE_MAJOR=$(node -v | cut -d'.' -f1 | tr -d 'v')
  if [ "$NODE_MAJOR" -lt 20 ]; then
    NEED_NODE=1
  fi
fi

if [ "$NEED_NODE" -eq 1 ]; then
  msg_info "Setting up Node.js 22.x LTS repository..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
  apt-get update -y
  apt-get install -y nodejs
fi

msg_ok "Node.js $(node -v) and npm $(npm -v) verified."

msg_info "Preparing application and database directories..."
mkdir -p "$APP_DIR" "/srv"
chmod 755 "/srv"

msg_info "Fetching latest Movie Hat release metadata from ${GITHUB_REPO}..."
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null || true)

if [ -n "$RELEASE_JSON" ] && echo "$RELEASE_JSON" | grep -q '"tag_name"'; then
  LATEST_TAG=$(echo "$RELEASE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4)
  DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*\.tar\.gz"' | head -n 1 | cut -d'"' -f4)
  if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_TAG}/movie-hat-${LATEST_TAG}.tar.gz"
  fi
  msg_info "Found latest release: ${LATEST_TAG}"
else
  msg_warn "Could not resolve release via GitHub API. Using fallback release URL tag v1.0.0..."
  LATEST_TAG="v1.0.0"
  DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_TAG}/movie-hat-${LATEST_TAG}.tar.gz"
fi

TMP_ARCHIVE="/tmp/movie-hat-install.tar.gz"
msg_info "Downloading application bundle from ${DOWNLOAD_URL}..."
if ! curl -fsSL -o "$TMP_ARCHIVE" "$DOWNLOAD_URL"; then
  msg_err "Failed to download release archive from ${DOWNLOAD_URL}."
  msg_warn "Ensure a release with asset movie-hat-${LATEST_TAG}.tar.gz has been published to GitHub."
  exit 1
fi

msg_info "Extracting release bundle into ${APP_DIR}..."
tar -xzf "$TMP_ARCHIVE" -C "$APP_DIR"
rm -f "$TMP_ARCHIVE"

msg_info "Installing production dependencies in ${APP_DIR}..."
cd "$APP_DIR"
npm install --omit=dev --no-audit --no-fund

# Configure .env if not already present
if [ ! -f "$APP_DIR/.env" ]; then
  msg_info "Generating initial production configuration (.env)..."
  JWT_SECRET=$(openssl rand -hex 32 2>/dev/null || tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 64)
  cat > "$APP_DIR/.env" << EOF
# The Movie Hat Environment Configuration
PORT=3000
NODE_ENV=production
DB_PATH=${DB_FILE}
JWT_SECRET=${JWT_SECRET}
EOF
  chmod 600 "$APP_DIR/.env"
  msg_ok "Environment created with persistent SQLite storage at ${DB_FILE}"
fi

msg_info "Configuring systemd service (/etc/systemd/system/movie-hat.service)..."
cat > /etc/systemd/system/movie-hat.service << EOF
[Unit]
Description=The Movie Hat Web Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
EnvironmentFile=-${APP_DIR}/.env
ExecStartPre=/usr/bin/node -e "const fs=require('fs'); if(!fs.existsSync('${APP_DIR}/logs')) fs.mkdirSync('${APP_DIR}/logs', {recursive:true});"
ExecStart=/usr/bin/node ${APP_DIR}/server/server.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now movie-hat

# Install in-container update command
msg_info "Configuring in-container update utility (/usr/local/bin/update)..."
if curl -fsSL -o /usr/local/bin/update "${RAW_BASE_URL}/install/update.sh" 2>/dev/null; then
  chmod +x /usr/local/bin/update
else
  # If fetching fails during offline/bootstrap, install embedded copy
  cat > /usr/local/bin/update << 'UPDEOF'
#!/usr/bin/env bash
set -Eeuo pipefail
APP_DIR="/srv/movie-hat"
DEFAULT_REPO="keljoundi/movie-hat"
GITHUB_REPO="${GITHUB_REPO:-$DEFAULT_REPO}"
if [ "$(id -u)" -ne 0 ]; then echo "Must run as root"; exit 1; fi
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest")
LATEST_TAG=$(echo "$RELEASE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4)
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*\.tar\.gz"' | head -n 1 | cut -d'"' -f4)
[ -z "$DOWNLOAD_URL" ] && DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_TAG}/movie-hat-${LATEST_TAG}.tar.gz"
echo "Updating Movie Hat to ${LATEST_TAG}..."
systemctl stop movie-hat
[ -f "$APP_DIR/.env" ] && cp "$APP_DIR/.env" /tmp/.movie-hat-env.bak
curl -fsSL -o /tmp/movie-hat-update.tar.gz "$DOWNLOAD_URL"
tar -xzf /tmp/movie-hat-update.tar.gz -C "$APP_DIR"
rm -f /tmp/movie-hat-update.tar.gz
[ -f /tmp/.movie-hat-env.bak ] && cp /tmp/.movie-hat-env.bak "$APP_DIR/.env" && rm -f /tmp/.movie-hat-env.bak
cd "$APP_DIR" && npm install --omit=dev --no-audit --no-fund
systemctl start movie-hat
echo "Update to ${LATEST_TAG} completed!"
UPDEOF
  chmod +x /usr/local/bin/update
fi

# Clean up apt caches
apt-get autoremove -y >/dev/null 2>&1 || true
apt-get clean >/dev/null 2>&1 || true

msg_ok "The Movie Hat container service is installed, active, and enabled on boot!"
