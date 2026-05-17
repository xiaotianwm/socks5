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

random_port() {
  for _ in $(seq 1 80); do
    local raw
    raw="$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')"
    local port=$((raw % 40000 + 20000))
    if [ "${port}" = "${PORT}" ]; then
      continue
    fi
    if command -v ss >/dev/null 2>&1 && ss -ltn | awk '{print $4}' | grep -q ":${port}$"; then
      continue
    fi
    echo "${port}"
    return 0
  done
  echo "Failed to choose an admin port." >&2
  return 1
}

random_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
    return 0
  fi
  od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
}

detect_host() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null && return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO- --timeout=3 https://api.ipify.org 2>/dev/null && return 0
  fi
  hostname -I 2>/dev/null | awk '{print $1}'
}

read_existing_admin() {
  if [ ! -f "${SERVICE_FILE}" ]; then
    return 0
  fi
  local line
  line="$(grep -E '^ExecStart=' "${SERVICE_FILE}" | tail -n 1 || true)"
  if [ -z "${line}" ]; then
    return 0
  fi
  local existing_port
  local existing_token
  existing_port="$(printf '%s\n' "${line}" | sed -n 's/.*-admin[[:space:]]\+:\([0-9]\+\).*/\1/p')"
  existing_token="$(printf '%s\n' "${line}" | sed -n 's/.*-admin-token[[:space:]]\+\([^[:space:]]\+\).*/\1/p')"
  if [ -n "${existing_port}" ] && [ -z "${ADMIN_PORT:-}" ]; then
    ADMIN_PORT="${existing_port}"
  fi
  if [ -n "${existing_token}" ] && [ -z "${ADMIN_TOKEN:-}" ]; then
    ADMIN_TOKEN="${existing_token}"
  fi
}

read_existing_admin

ADMIN_PORT="${ADMIN_PORT:-$(random_port)}"
ADMIN_TOKEN="${ADMIN_TOKEN:-$(random_token)}"
HOST_IP="${HOST_IP:-$(detect_host)}"
if [ -z "${HOST_IP}" ]; then
  HOST_IP="<server-ip>"
fi
SYSTEMD_USERNAME="${USERNAME//%/%%}"
SYSTEMD_PASSWORD="${PASSWORD//%/%%}"

echo "Installing SOCKS5 service..."
echo "Service: ${SERVICE_NAME}"
echo "Listen:  :${PORT}"
echo "Admin:   :${ADMIN_PORT}"
if [ -f "${SERVICE_FILE}" ]; then
  echo "Existing admin port/token will be reused when available."
fi

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
ExecStart=${INSTALL_PATH} -addr :${PORT} -user ${SYSTEMD_USERNAME} -pass ${SYSTEMD_PASSWORD} -admin :${ADMIN_PORT} -admin-token ${ADMIN_TOKEN}
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
  echo "=========================================="
  echo "SOCKS5:"
  echo "  host: ${HOST_IP}"
  echo "  port: ${PORT}"
  echo "  user: ${USERNAME}"
  echo "  pass: ${PASSWORD}"
  echo ""
  echo "Admin Web:"
  echo "  url: http://${HOST_IP}:${ADMIN_PORT}/?token=${ADMIN_TOKEN}"
  echo ""
  echo "Commands:"
  echo "  status: systemctl status ${SERVICE_NAME}"
  echo "  logs:   journalctl -u ${SERVICE_NAME} -f"
  echo "=========================================="
else
  echo "SOCKS5 service failed to start." >&2
  echo "Check: systemctl status ${SERVICE_NAME}" >&2
  exit 1
fi
