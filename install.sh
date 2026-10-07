#!/usr/bin/env bash
set -euo pipefail

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

if [[ ${EUID} -ne 0 ]]; then
    die "Run with sudo, for example: sudo $0 pi"
fi

APP_USER="${1:-${SUDO_USER:-pi}}"
HMI_PORT="${2:-8081}"
MOONRAKER_HOST="${3:-127.0.0.1}"
MOONRAKER_PORT="${4:-7125}"

[[ "$APP_USER" != root ]] || die "Choose the regular Linux account that owns the printer home directory."
getent passwd "$APP_USER" >/dev/null || die "Linux user '$APP_USER' does not exist."
[[ "$HMI_PORT" =~ ^[0-9]+$ ]] && (( HMI_PORT > 0 && HMI_PORT < 65536 )) || die "Invalid HMI port: $HMI_PORT"
[[ "$MOONRAKER_PORT" =~ ^[0-9]+$ ]] && (( MOONRAKER_PORT > 0 && MOONRAKER_PORT < 65536 )) || die "Invalid Moonraker port: $MOONRAKER_PORT"
[[ "$MOONRAKER_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || die "Use a hostname or IPv4 address for Moonraker."
command -v nginx >/dev/null || die "Nginx is not installed."
command -v systemctl >/dev/null || die "systemd is required to reload Nginx."

APP_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"
[[ -n "$APP_HOME" && "$APP_HOME" == /* ]] || die "Could not determine the home directory for '$APP_USER'."
[[ "$APP_HOME" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "The selected home directory contains characters that need manual Nginx escaping."
APP_GROUP="$(id -gn "$APP_USER")"
APP_DIR="$APP_HOME/apps/vcore-hmi"
WEB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/web"
NGINX_CONF="/etc/nginx/conf.d/vcore-hmi-standalone.conf"

[[ -f "$WEB_DIR/index.html" && -f "$WEB_DIR/manifest.webmanifest" ]] || die "The web/ bundle is missing. Run this script from the repository checkout."
mkdir -p "$APP_DIR"
chown "$APP_USER:$APP_GROUP" "$APP_HOME/apps" "$APP_DIR"
chmod 755 "$APP_HOME/apps" "$APP_DIR"
for file in index.html manifest.webmanifest icon-192.png icon-512.png; do
    [[ -f "$WEB_DIR/$file" ]] || die "Missing web file: $file"
    install -o "$APP_USER" -g "$APP_GROUP" -m 644 "$WEB_DIR/$file" "$APP_DIR/$file"
done

BACKUP=""
ROLLBACK_CONF=""
if [[ -e "$NGINX_CONF" ]]; then
    ROLLBACK_CONF="$(mktemp /tmp/vcore-hmi-nginx-rollback.XXXXXX)"
    cp -a "$NGINX_CONF" "$ROLLBACK_CONF"
fi
if [[ -e "$NGINX_CONF" ]] && ! grep -q '^# Managed by V-Core HMI install.sh$' "$NGINX_CONF"; then
    BACKUP="${NGINX_CONF}.backup.$(date +%Y%m%d-%H%M%S)"
    cp -a "$NGINX_CONF" "$BACKUP"
    printf 'Saved existing Nginx config to %s\n' "$BACKUP"
fi

TMP_CONF="$(mktemp /etc/nginx/conf.d/vcore-hmi-standalone.conf.XXXXXX)"
restore_config() {
    rm -f "$NGINX_CONF"
    if [[ -n "$ROLLBACK_CONF" && -e "$ROLLBACK_CONF" ]]; then
        cp -a "$ROLLBACK_CONF" "$NGINX_CONF"
    fi
}
cleanup() {
    rm -f "$TMP_CONF"
    [[ -z "$ROLLBACK_CONF" ]] || rm -f "$ROLLBACK_CONF"
}
trap cleanup EXIT

cat >"$TMP_CONF" <<EOF
# Managed by V-Core HMI install.sh
server {
    listen ${HMI_PORT} default_server;
    server_name _;

    root ${APP_DIR};
    index index.html;
    client_max_body_size 0;

    location /websocket {
        proxy_pass http://${MOONRAKER_HOST}:${MOONRAKER_PORT}/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    location ~ ^/(printer|api|access|machine|server)/ {
        proxy_pass http://${MOONRAKER_HOST}:${MOONRAKER_PORT}\$request_uri;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Scheme \$scheme;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
chmod 644 "$TMP_CONF"
mv -f "$TMP_CONF" "$NGINX_CONF"

if ! nginx -t; then
    restore_config
    die "Nginx rejected the HMI config; the previous config has been restored."
fi

if systemctl is-active --quiet nginx; then
    if ! systemctl reload nginx; then
        restore_config
        nginx -t && systemctl reload nginx || true
        die "Nginx could not reload; the previous config has been restored."
    fi
else
    systemctl start nginx || {
        restore_config
        nginx -t && systemctl start nginx || true
        die "Nginx could not start; the previous config has been restored."
    }
fi

printf '\nV-Core HMI installed.\n'
printf 'Open: http://<printer-ip>:%s/\n' "$HMI_PORT"
printf 'Web files: %s\n' "$APP_DIR"
printf 'Nginx config: %s\n' "$NGINX_CONF"
