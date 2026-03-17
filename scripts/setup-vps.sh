#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking OS..."
cat /etc/os-release | head -3

echo "==> Checking system resources..."
echo "Memory: $(free -h | awk '/Mem:/ {print $2}')"
echo "Disk: $(df -h / | awk 'NR==2 {print $4}') available"

echo "==> Installing Node.js 22 if needed..."
if command -v node &>/dev/null; then
    NODE_VER=$(node -v)
    echo "Node.js already installed: $NODE_VER"
    if [[ "$NODE_VER" < "v22" ]]; then
        echo "Node.js version too old, upgrading..."
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
        apt-get install -y nodejs
    fi
else
    echo "Installing Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
fi
echo "Node.js: $(node -v)"
echo "npm: $(npm -v)"

echo "==> Installing OpenClaw if needed..."
if command -v openclaw &>/dev/null; then
    echo "OpenClaw already installed: $(openclaw --version 2>/dev/null || echo 'unknown')"
else
    echo "Installing OpenClaw..."
    npm install -g openclaw@latest
fi

echo "==> Creating OpenClaw home directory..."
mkdir -p /root/.openclaw
chmod 700 /root/.openclaw

echo "==> Setting up systemd service..."
cat > /etc/systemd/system/openclaw.service << 'SYSTEMD_EOF'
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
EnvironmentFile=/root/.openclaw/.env
ExecStart=/usr/bin/env openclaw gateway run
Restart=always
RestartSec=5
TimeoutStartSec=90

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

systemctl daemon-reload
systemctl enable openclaw

echo "==> VPS setup complete."
echo "Next steps:"
echo "  1. Copy .env to /root/.openclaw/.env"
echo "  2. Copy openclaw.json to /root/.openclaw/openclaw.json"
echo "  3. Run: systemctl start openclaw"
