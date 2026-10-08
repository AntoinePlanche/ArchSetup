#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run with sudo: sudo bash $0"
    exit 1
fi

echo "[*] Creating /etc/systemd/system/scx.service for scx_lavd..."
cat << 'SERVICE_EOF' > /etc/systemd/system/scx.service
[Unit]
Description=sched-ext LAVD (Latency-Aware Virtual Deadline) Scheduler
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/scx_lavd
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE_EOF

echo "[*] Reloading systemd and enabling scx.service..."
systemctl daemon-reload
systemctl enable --now scx.service

echo "============================================================"
echo "  scx_lavd is now your active and default system scheduler! "
echo "============================================================"
systemctl status scx.service --no-pager
