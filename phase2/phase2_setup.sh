#!/bin/bash
# Phase 2 setup - run from Mac 2. Idempotent.
# Usage: ./phase2_setup.sh mac1|mac3|mac4|all
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/hosts.env"
KEY="$HOME/.ssh/id_ed25519_cnlab"
SSHOPTS=(-i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8)
EV="$DIR/../evidence/phase2"; mkdir -p "$EV"

say(){ printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
run(){ echo "[$1] $2"; ssh "${SSHOPTS[@]}" "$1" "$2"; }
put(){ echo "[scp -> $1] $2"; scp -i "$KEY" -o StrictHostKeyChecking=accept-new -q "$2" "$1:$3"; }

record_fix(){ # ensure dnsmasq record points to edge IP
  sudo sed -i '' -E 's|address=/app\.team1\.test/[0-9.]+|address=/app.team1.test/10.7.6.180|; s|address=/api\.team1\.test/[0-9.]+|address=/api.team1.test/10.7.6.180|' "$1"
}

role_mac1(){
  say "MAC 1 ($MAC1_IP): fix stale records, restart dnsmasq, dual-resolver setting"
  run "$MAC1_USER@$MAC1_IP" 'cp /opt/homebrew/etc/dnsmasq.conf /tmp/dnsmasq.conf.phase1bak 2>/dev/null; true'
  put "$MAC1_USER@$MAC1_IP" "$DIR/record_fix.sed" /tmp/record_fix.sed
  run "$MAC1_USER@$MAC1_IP" "sudo -n sh -c 'sed -i '' -E \"s|address=/app\\.team1\\.test/[0-9.]+|address=/app.team1.test/10.7.6.180|; s|address=/api\\.team1\\.test/[0-9.]+|address=/api.team1.test/10.7.6.180|\" /opt/homebrew/etc/dnsmasq.conf && brew services restart dnsmasq'"
  run "$MAC1_USER@$MAC1_IP" 'dig @127.0.0.1 app.team1.test +short; dig @127.0.0.1 api.team1.test +short'
  run "$MAC1_USER@$MAC1_IP" 'sudo -n networksetup -setdnsservers Wi-Fi 127.0.0.1 '"$MAC3_IP"' 2>&1 | true; networksetup -getdnsservers Wi-Fi'
}

role_mac3(){
  say "MAC 3 ($MAC3_IP): backup DNS + standby nginx + pf isolation"
  run "$MAC3_USER@$MAC3_IP" 'brew install -q dnsmasq nginx >/dev/null 2>&1; brew list dnsmasq >/dev/null && brew list nginx >/dev/null && echo TOOLS_OK'
  run "$MAC3_USER@$MAC3_IP" 'mkdir -p ~/CN-Project ~/CN-Project/certs'
  put "$MAC3_USER@$MAC3_IP" "$HOME/cn-project/certs/app.team1.test.pem"     ~/CN-Project/certs/app.team1.test.pem
  put "$MAC3_USER@$MAC3_IP" "$HOME/cn-project/certs/app.team1.test-key.pem" ~/CN-Project/certs/app.team1.test-key.pem
  put "$MAC3_USER@$MAC3_IP" "$DIR/dnsmasq-backup.conf" /tmp/dnsmasq-backup.conf
  sed "s|HARDIK3_USER|$MAC3_USER|g" "$DIR/nginx-standby.conf" > /tmp/nginx-standby.conf
  put "$MAC3_USER@$MAC3_IP" /tmp/nginx-standby.conf /tmp/nginx-standby.conf
  run "$MAC3_USER@$MAC3_IP" "sudo -n sh -c 'cp /opt/homebrew/etc/dnsmasq.conf /tmp/dnsmasq.conf.phase1bak 2>/dev/null; cp /tmp/dnsmasq-backup.conf /opt/homebrew/etc/dnsmasq.conf; mkdir -p /opt/homebrew/etc/nginx; [ -f /opt/homebrew/etc/nginx/nginx.conf ] && cp /opt/homebrew/etc/nginx/nginx.conf /tmp/nginx.conf.phase1bak; cp /tmp/nginx-standby.conf /opt/homebrew/etc/nginx/nginx.conf; brew services restart dnsmasq; brew services restart nginx'"
  # pf isolation for backend port 3001
  put "$MAC3_USER@$MAC3_IP" "$DIR/pf-anchor-mac3.conf" /tmp/cn-isolation.rules
  run "$MAC3_USER@$MAC3_IP" "sudo -n sh -c 'cp /etc/pf.conf /tmp/pf.conf.phase1bak 2>/dev/null; cp /tmp/cn-isolation.rules /etc/pf.anchors/cn-isolation; chmod 644 /etc/pf.anchors/cn-isolation; grep -q \"cn-isolation\" /etc/pf.conf || printf \"anchor \\\"cn-isolation\\\"\\nload anchor \\\"cn-isolation\\\" from \\\"/etc/pf.anchors/cn-isolation\\\"\\n\" >> /etc/pf.conf; pfctl -f /etc/pf.conf && pfctl -E'"
  run "$MAC3_USER@$MAC3_IP" 'sudo -n networksetup -setdnsservers Wi-Fi '"$MAC1_IP"' '"$MAC3_IP"'; networksetup -getdnsservers Wi-Fi'
  say "verify from Mac 2: backup DNS + standby edge"
  dig "@$MAC3_IP" app.team1.test +short | tee -a "$EV/setup_mac3_dns.txt"
  curl -s --resolve app.team1.test:443:"$MAC3_IP" https://app.team1.test/api/status | tee -a "$EV/setup_mac3_edge.txt"; echo
  curl -s -m 4 "http://$MAC3_IP:3001/api/status" | tee -a "$EV/setup_mac3_backend.txt"; echo
}

role_mac4(){
  say "MAC 4 ($MAC4_IP): pf isolation for backend port 3002"
  put "$MAC4_USER@$MAC4_IP" "$DIR/pf-anchor-mac4.conf" /tmp/cn-isolation.rules
  run "$MAC4_USER@$MAC4_IP" "sudo -n sh -c 'cp /etc/pf.conf /tmp/pf.conf.phase1bak 2>/dev/null; cp /tmp/cn-isolation.rules /etc/pf.anchors/cn-isolation; chmod 644 /etc/pf.anchors/cn-isolation; grep -q \"cn-isolation\" /etc/pf.conf || printf \"anchor \\\"cn-isolation\\\"\\nload anchor \\\"cn-isolation\\\" from \\\"/etc/pf.anchors/cn-isolation\\\"\\n\" >> /etc/pf.conf; pfctl -f /etc/pf.conf && pfctl -E'"
  run "$MAC4_USER@$MAC4_IP" 'sudo -n networksetup -setdnsservers Wi-Fi '"$MAC1_IP"' '"$MAC3_IP"'; networksetup -getdnsservers Wi-Fi'
}

case "${1:-}" in
  mac1) role_mac1 ;;
  mac3) role_mac3 ;;
  mac4) role_mac4 ;;
  all)  role_mac1; role_mac3; role_mac4 ;;
  *) echo "usage: $0 mac1|mac3|mac4|all"; exit 1 ;;
esac
