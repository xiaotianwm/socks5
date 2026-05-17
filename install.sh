#!/usr/bin/env bash
set -euo pipefail

DOWNLOAD_URL="${DOWNLOAD_URL:-https://github.com/xiaotianwm/socks5/raw/main/socks5-server}"
INSTALL_PATH="${INSTALL_PATH:-/usr/local/bin/socks5-server}"
SERVICE_NAME="${SERVICE_NAME:-mysocks5}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

usage() {
  echo "Usage: bash install.sh <port> <username> <password>"
  echo "Example: bash install.sh 1080 admin strong-password"
}

if [ "${EUID}" -ne 0 ]; then
  echo "Please run as root: sudo bash install.sh <port> <username> <password>" >&2
  exit 1
fi

if [ "$#" -ne 3 ]; then
  usage
  exit 1
fi

PORT="$1"
USERNAME="$2"
PASSWORD="$3"

if ! [[ "${PORT}" =~ ^[0-9]+$ ]] || [ "${PORT}" -lt 1 ] || [ "${PORT}" -gt 65535 ]; then
  echo "Invalid port: ${PORT}" >&2
  exit 1
fi

if [ -z "${USERNAME}" ] || [ -z "${PASSWORD}" ]; then
  echo "Username and password cannot be empty." >&2
  exit 1
fi

if [[ "${USERNAME}" =~ [[:space:]] ]] || [[ "${PASSWORD}" =~ [[:space:]] ]]; then
  echo "Username and password cannot contain whitespace." >&2
  exit 1
fi

if [ "${#USERNAME}" -gt 255 ] || [ "${#PASSWORD}" -gt 255 ]; then
  echo "Username and password must be no longer than 255 bytes." >&2
  exit 1
fi

echo "Installing SOCKS5 service..."
echo "Service: ${SERVICE_NAME}"
echo "Listen:  :${PORT}"

if systemctl is-active --quiet "${SERVICE_NAME}"; then
  systemctl stop "${SERVICE_NAME}"
fi

if systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
  systemctl disable "${SERVICE_NAME}"
fi

echo "Downloading binary from ${DOWNLOAD_URL}"
if command -v wget >/dev/null 2>&1; then
  wget -qO "${INSTALL_PATH}" "${DOWNLOAD_URL}"
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "${DOWNLOAD_URL}" -o "${INSTALL_PATH}"
else
  echo "Neither wget nor curl is installed." >&2
  exit 1
fi

chmod 0755 "${INSTALL_PATH}"

cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=Lightweight SOCKS5 Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_PATH} -addr :${PORT} -user ${USERNAME} -pass ${PASSWORD}
Restart=always
RestartSec=5s
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

sleep 1
if systemctl is-active --quiet "${SERVICE_NAME}"; then
  echo "SOCKS5 service is running."
  echo "Port: ${PORT}"
  echo "User: ${USERNAME}"
  echo "Status: systemctl status ${SERVICE_NAME}"
  echo "Logs: journalctl -u ${SERVICE_NAME} -f"
else
  echo "SOCKS5 service failed to start." >&2
  echo "Check: systemctl status ${SERVICE_NAME}" >&2
  exit 1
fi
