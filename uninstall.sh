#!/usr/bin/env bash
set -euo pipefail

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
[[ ${EUID} -eq 0 ]] || die "Run with sudo: sudo $0"

NGINX_CONF="/etc/nginx/conf.d/vcore-hmi-standalone.conf"
[[ -f "$NGINX_CONF" ]] || die "HMI Nginx config not found: $NGINX_CONF"
grep -q '^# Managed by V-Core HMI install.sh$' "$NGINX_CONF" || die "The config does not have the installer marker; refusing to remove it."

BACKUP=""
for candidate in "${NGINX_CONF}.backup."*; do
    [[ -f "$candidate" ]] || continue
    if [[ -z "$BACKUP" || "$candidate" > "$BACKUP" ]]; then BACKUP="$candidate"; fi
done

ROLLBACK_CONF="$(mktemp /tmp/vcore-hmi-nginx-uninstall.XXXXXX)"
cp -a "$NGINX_CONF" "$ROLLBACK_CONF"
restore_hmi_config() { cp -a "$ROLLBACK_CONF" "$NGINX_CONF"; rm -f "$ROLLBACK_CONF"; }

if [[ -n "$BACKUP" ]]; then
    cp -a "$BACKUP" "$NGINX_CONF"
    printf 'Restored previous Nginx config from %s\n' "$BACKUP"
else
    rm -f "$NGINX_CONF"
fi

if ! nginx -t; then
    restore_hmi_config
    die "Nginx validation failed; the HMI config has been restored."
fi
if systemctl is-active --quiet nginx; then
    if ! systemctl reload nginx; then
        restore_hmi_config
        nginx -t && systemctl reload nginx || true
        die "Nginx reload failed; the HMI config has been restored."
    fi
fi
rm -f "$ROLLBACK_CONF"

printf 'V-Core HMI Nginx listener removed. Web files were left in the user's apps/vcore-hmi directory.\n'
