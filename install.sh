#!/bin/bash

set -e
set -u
set -o pipefail

LISTEN_PORT="443"
TARGET_DOMAIN="bing.com"
CONFIG_FILE="/etc/hysteria/config.yaml"
BACKUP_FILE="/etc/hysteria/config.yaml.backup"
CERT_KEY_FILE="/etc/hysteria/server.key"
CERT_CRT_FILE="/etc/hysteria/server.crt"
CERT_USER="hysteria"
SERVICE_NAME="hysteria-server.service"
SERVICE_OVERRIDE_DIR="/etc/systemd/system/${SERVICE_NAME}.d"
PRIORITY_CONF_FILE="${SERVICE_OVERRIDE_DIR}/priority.conf"
SYSCTL_CONF_FILE="/etc/sysctl.d/99-hysteria.conf"
HYSTERIA_PASSWORD=""
SERVER_IPV4=""

error_exit() {
  echo "[ERROR] $1" >&2
  exit 1
}

run_command() {
  shift # Remove description (not used)
  if sudo -n "$@"; then
    : # Success
  else
    if ! sudo "$@"; then
        local exit_code=$?
        error_exit "Command failed (Exit Code: $exit_code): $*"
    fi
  fi
}

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error_exit "$cmd command not found. Please install $cmd."
    fi
}

remove_existing_hy2() {
  check_command curl
  if ! (curl -fsSL https://get.hy2.sh/ | sudo bash -s -- --remove); then
     local exit_code=$?
     echo "[WARNING] Hysteria online removal script failed (Exit Code: $exit_code). Continuing..." >&2
  fi
  run_command "Remove /etc/hysteria" rm -rf /etc/hysteria
  if id -u "$CERT_USER" >/dev/null 2>&1; then
    run_command "Remove user $CERT_USER" userdel -r "$CERT_USER"
  fi
  run_command "Remove systemd link 1" rm -f "/etc/systemd/system/multi-user.target.wants/hysteria-server.service"
  run_command "Remove systemd link 2" rm -f "/etc/systemd/system/multi-user.target.wants/hysteria-server@*.service"
  run_command "Reload systemd daemon" systemctl daemon-reload
}

install_hy2() {
  check_command curl
  if ! (curl -fsSL https://get.hy2.sh/ | sudo bash); then
     local exit_code=$?
     error_exit "Hysteria installation script failed (Exit Code: $exit_code)."
  fi
}

backup_config() {
  if sudo test -f "$CONFIG_FILE"; then
    run_command "Backup $CONFIG_FILE" cp "$CONFIG_FILE" "$BACKUP_FILE"
  fi
}

remove_config() {
  run_command "Remove $CONFIG_FILE" rm -f "$CONFIG_FILE"
}

create_config() {
  if [ -z "$HYSTERIA_PASSWORD" ]; then error_exit "Password not generated."; fi
  run_command "Ensure /etc/hysteria exists" mkdir -p /etc/hysteria
  if ! sudo tee "$CONFIG_FILE" > /dev/null <<EOF
listen: :${LISTEN_PORT}
tls:
  cert: $CERT_CRT_FILE
  key: $CERT_KEY_FILE
auth:
  type: password
  password: "$HYSTERIA_PASSWORD"
fastOpen: true
masquerade:
  type: proxy
  proxy:
    url: https://${TARGET_DOMAIN}
    rewriteHost: true
transport:
  udp:
    hopInterval: 30s
sniff:
  enable: true
  timeout: 2s
  rewriteDomain: false
  tcpPorts: 80,443,8000-9000
  udpPorts: all
resolver:
  type: https
  tcp:
    addr: 8.8.8.8:53
    timeout: 4s
  udp:
    addr: 8.8.4.4:53
    timeout: 4s
  tls:
    addr: 1.1.1.1:853
    timeout: 10s
    sni: cloudflare-dns.com
    insecure: false
  https:
    addr: 1.1.1.1:443
    timeout: 10s
    sni: cloudflare-dns.com
    insecure: false
EOF
  then
      error_exit "Failed to write configuration file '$CONFIG_FILE' (Exit Code: $?)."
  fi
}

generate_cert() {
  check_command openssl
  if ! id -u "$CERT_USER" >/dev/null 2>&1; then error_exit "User '$CERT_USER' not found."; fi
  run_command "Ensure /etc/hysteria exists" mkdir -p /etc/hysteria
  local openssl_chown_cmd
  openssl_chown_cmd=$(cat <<CMD_EOF
set -e
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \\
    -keyout '$CERT_KEY_FILE' -out '$CERT_CRT_FILE' \\
    -subj '/CN=${TARGET_DOMAIN}' -days 36500
chown '$CERT_USER' '$CERT_KEY_FILE'
chown '$CERT_USER' '$CERT_CRT_FILE'
CMD_EOF
)
  if ! sudo bash -c "$openssl_chown_cmd"; then
      local exit_code=$?
      sudo rm -f "$CERT_KEY_FILE" "$CERT_CRT_FILE"
      error_exit "Certificate generation/ownership failed (Exit Code: $exit_code)."
  fi
}

tune_kernel() {
  local sysctl_settings
  sysctl_settings=$(cat <<EOF
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
)
  if ! (echo "$sysctl_settings" | sudo tee "$SYSCTL_CONF_FILE" > /dev/null); then
      error_exit "Failed to write sysctl settings to '$SYSCTL_CONF_FILE' (Exit Code: $?)."
  fi
  run_command "Apply sysctl settings" sysctl -p "$SYSCTL_CONF_FILE"
}

configure_systemd() {
  check_command systemctl
  run_command "Ensure systemd override dir exists" mkdir -p "/etc/systemd/system/${SERVICE_NAME}.d"
  if ! sudo tee "$PRIORITY_CONF_FILE" > /dev/null <<EOF
[Service]
CPUSchedulingPolicy=rr
CPUSchedulingPriority=99
EOF
  then
      error_exit "Failed to write priority config file '$PRIORITY_CONF_FILE' (Exit Code: $?)."
  fi
}

manage_service() {
    check_command systemctl
    run_command "Reload systemd daemon" systemctl daemon-reload
    run_command "Enable/start ${SERVICE_NAME}" systemctl enable --now "${SERVICE_NAME}"
}

# --- Main Execution ---
check_command sudo
check_command openssl
check_command bash
check_command id
check_command curl

if ! sudo -v; then error_exit "Sudo privilege validation failed."; fi

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --port)
      LISTEN_PORT="$2"
      if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || ! [ "$LISTEN_PORT" -ge 1 ] || ! [ "$LISTEN_PORT" -le 65535 ]; then
          error_exit "Invalid port number provided: '$LISTEN_PORT'. Must be 1-65535."
      fi
      shift; shift
      ;;
    --domain)
      TARGET_DOMAIN="$2"
      if ! [[ "$TARGET_DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; then
          error_exit "Invalid domain name provided: '$TARGET_DOMAIN'."
      fi
      shift; shift
      ;;
    *)
      shift
      ;;
  esac
done

HYSTERIA_PASSWORD=$(openssl rand -hex 20)
if [ -z "$HYSTERIA_PASSWORD" ]; then error_exit "Failed to generate password."; fi

remove_existing_hy2
install_hy2
backup_config
remove_config
create_config
generate_cert
tune_kernel
configure_systemd
manage_service

SERVER_IPV4=$(curl -s --connect-timeout 5 api.ipify.org || echo "") # Assign empty on curl failure
if [ -z "$SERVER_IPV4" ]; then
    sleep 2
    SERVER_IPV4=$(curl -s --connect-timeout 5 api.ipify.org || echo "") # Retry
fi

echo "--- Setup Finished ---"
if [ -n "$SERVER_IPV4" ]; then
    echo "Hysteria Connection String (WARNING: Contains password!):"
    echo "hysteria2://${HYSTERIA_PASSWORD}@${SERVER_IPV4}:${LISTEN_PORT}/?sni=${TARGET_DOMAIN}&alpn=h3&insecure=1#Hysteria"
else
    echo "[WARNING] Could not fetch public IP. Connection string incomplete."
    echo "Password: $HYSTERIA_PASSWORD"
    echo "Port: $LISTEN_PORT"
    echo "Domain: $TARGET_DOMAIN"
fi
echo "----------------------"
exit 0

