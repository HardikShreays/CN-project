#!/bin/bash
# Phase 2 RESET - restore the Phase 1 baseline. Run from Mac 2. Usage: ./phase2_reset.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/hosts.env"
KEY="$HOME/.ssh/id_ed25519_cnlab"
SSHOPTS=(-i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8)
say(){ printf '\n\033[1;33m== %s ==\033[0m\n' "$*"; }
run(){ echo "[$1] $2"; ssh "${SSHOPTS[@]}" "$1" "$2"; }

say "MAC 1: DNS record back to Mac 2 edge, dnsmasq running"
run "$MAC1_USER@$MAC1_IP" "sudo -n sh -c 'sed -i '' -E \"s|address=/app\\.team1\\.test/[0-9.]+|address=/app.team1.test/$MAC2_IP|; s|address=/api\\.team1\\.test/[0-9.]+|address=/api.team1.test/$MAC2_IP|\" /opt/homebrew/etc/dnsmasq.conf; brew services restart dnsmasq; brew services start dnsmasq'"

say "MAC 3: disable pf (restore), stop backup DNS + standby nginx"
run "$MAC3_USER@$MAC3_IP" "sudo -n sh -c 'cp /tmp/pf.conf.phase1bak /etc/pf.conf 2>/dev/null; pfctl -f /etc/pf.conf; pfctl -d' ; brew services stop dnsmasq; brew services stop nginx"

say "MAC 4: disable pf (restore)"
run "$MAC4_USER@$MAC4_IP" "sudo -n sh -c 'cp /tmp/pf.conf.phase1bak /etc/pf.conf 2>/dev/null; pfctl -f /etc/pf.conf; pfctl -d'"

say "Mac 2 (this machine): single-resolver DNS restored"
networksetup -setdnsservers Wi-Fi "$MAC1_IP"
dscacheutil -flushcache 2>/dev/null; true

say "final check"
run "$MAC1_USER@$MAC1_IP" 'dig @127.0.0.1 app.team1.test +short'
curl -s https://app.team1.test/api/status; echo
