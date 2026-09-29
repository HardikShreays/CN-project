#!/usr/bin/env bash
# Run on Mac 2 (or on the standby edge for Extension E).
# Usage: ./deploy.sh <MAC3_IP> <MAC4_IP>
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: $0 <backendA_ip> <backendB_ip>"; exit 1; }

CONF="$(brew --prefix)/etc/nginx/nginx.conf"
[ -f "$CONF.orig" ] || cp "$CONF" "$CONF.orig"   # rollback: cp nginx.conf.orig nginx.conf
sed -e "s/MAC3_IP/$1/" -e "s/MAC4_IP/$2/" "$(dirname "$0")/nginx.conf" > "$CONF"

nginx -t
if pgrep -x nginx >/dev/null; then nginx -s reload; else nginx; fi
echo "edge up -> backends $1:3001, $2:3002"
