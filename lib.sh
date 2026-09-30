# Shared helpers, sourced by every person's script. Don't run this directly.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$ROOT/team.env"
for v in MAC1_IP MAC2_IP MAC3_IP MAC4_IP; do
  [ -n "${!v}" ] || { echo "!! $v is empty in team.env - fill in all 4 IPs and git pull"; exit 1; }
done

DOMAIN=app.team$TEAM.test
BREW=$(brew --prefix)                 # /opt/homebrew (Apple Silicon) or /usr/local (Intel)
CRT="$ROOT/edge/$DOMAIN.crt"          # public cert, committed by Hardik; the .key never leaves Mac 2
CURL="curl --cacert $CRT"             # full cert validation against our cert (never -k)

# Fill a config template: IPs, team number, brew prefix.
render() {
  sed -e "s/MAC1_IP/$MAC1_IP/g; s/MAC2_IP/$MAC2_IP/g; s/MAC3_IP/$MAC3_IP/g; s/MAC4_IP/$MAC4_IP/g" \
      -e "s/team1/team$TEAM/g; s#/opt/homebrew#$BREW#g" "$1"
}

# Start dnsmasq on this Mac (primary on Mac 1, backup on Mac 4). $1 = this Mac's IP.
dns_start() {
  render "$ROOT/dns/dnsmasq.conf" | sed "s/THIS_MAC_IP/$1/" > "$BREW/etc/dnsmasq.conf"
  render "$ROOT/dns/team.hosts" > "$BREW/etc/team.hosts"    # always back to Mac 2
  sudo brew services restart dnsmasq
  sleep 1
  echo "--- answer (expect $MAC2_IP, TTL 30):"
  dig @127.0.0.1 +noall +answer "$DOMAIN"
}

# Point app/api.teamN.test at an IP, live. Run on BOTH DNS servers in Phase 2.
dns_point() {
  echo "$1   $DOMAIN api.team$TEAM.test" > "$BREW/etc/team.hosts"
  sudo killall -HUP dnsmasq
  echo "$DOMAIN -> $1 (reloaded)"
  dig @127.0.0.1 +noall +answer "$DOMAIN"
}

# Start nginx as the edge (Hardik on Mac 2; Saman's standby on Mac 3 for Ext E).
edge_start() {
  [ -f "$BREW/etc/nginx/certs/$DOMAIN.key" ] || { echo "!! no $DOMAIN.key in $BREW/etc/nginx/certs - get it from Hardik"; exit 1; }
  local conf="$BREW/etc/nginx/nginx.conf"
  [ -f "$conf.orig" ] || cp "$conf" "$conf.orig"      # rollback copy of brew's default
  render "$ROOT/edge/nginx.conf" > "$conf"
  nginx -t
  if pgrep -x nginx >/dev/null; then nginx -s reload; else nginx; fi
  echo "edge up on :443 -> backends $MAC3_IP:3001, $MAC4_IP:3002"
}

# Ext C: only Mac 2 may reach this backend port. $1 = port.
firewall_on() {
  render "$ROOT/firewall/backend-pf.conf" | sed "s/3001/$1/g" > /tmp/cnproject-pf.conf
  sudo pfctl -a com.apple/cnproject -f /tmp/cnproject-pf.conf
  sudo pfctl -E 2>/dev/null || true
  sudo pfctl -a com.apple/cnproject -s rules
}
firewall_off() { sudo pfctl -a com.apple/cnproject -F rules; echo "firewall rules removed (rollback done)"; }

usage() { echo "usage: $0 <command>"; sed -n 's/^  \([a-z0-9-]*\)) *# \(.*\)/  \1  - \2/p' "$0"; exit 1; }
