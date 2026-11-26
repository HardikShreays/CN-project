#!/bin/bash
# Phase 2 demos - run from Mac 2 (edge). Usage: ./phase2_demo.sh A|B|C|D|E
# Every demo restores what it breaks at the end, and tees output to evidence/phase2/
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/hosts.env"
KEY="$HOME/.ssh/id_ed25519_cnlab"
SSHOPTS=(-i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8)
EV="$DIR/../evidence/phase2"; mkdir -p "$EV"
TS(){ date '+%H:%M:%S'; }
say(){ printf '\n\033[1;35m---- %s [%s] ----\033[0m\n' "$*" "$(TS)"; }
run(){ echo "[$1] $2"; ssh "${SSHOPTS[@]}" "$1" "$2"; }
OUT(){ echo "$1"; }

stamp(){ while IFS= read -r l; do echo "[$(TS)] $l"; done; }

demo_A(){
  say "EXTENSION A: backup DNS failover"
  { echo "### Client resolver list (primary $MAC1_IP + backup $MAC3_IP)"; networksetup -getdnsservers Wi-Fi;
    echo; echo "### Resolution BEFORE failure (note ;; SERVER line)"; dig app.team1.test +noall +comments +answer | grep -E 'SERVER|IN';
    say2=""; } 2>&1 | stamp | tee "$EV/A_failover.txt"
  say "STOPPING primary DNS on Mac 1"
  run "$MAC1_USER@$MAC1_IP" 'sudo -n brew services stop dnsmasq'
  { echo; echo "### Resolution DURING failure (resolver should now be $MAC3_IP)"; dig app.team1.test +noall +comments +answer | grep -E 'SERVER|IN';
    echo; echo "### App still reachable through edge"; curl -s https://app.team1.test/api/status; echo; } 2>&1 | stamp | tee -a "$EV/A_failover.txt"
  say "RESTARTING primary DNS on Mac 1 (restore)"
  run "$MAC1_USER@$MAC1_IP" 'sudo -n brew services start dnsmasq'
  sleep 3
  dig app.team1.test +noall +comments +answer | grep -E 'SERVER|IN' | stamp | tee -a "$EV/A_failover.txt"
}

demo_B(){
  say "EXTENSION B: TTL behaviour - record change 10.7.6.180 -> 10.7.6.181"
  LOG="$EV/B_ttl.txt"; : > "$LOG"
  { echo "### Current record + TTL (should be 30)"; dig app.team1.test +noall +answer; } 2>&1 | stamp | tee -a "$LOG"
  run "$MAC1_USER@$MAC1_IP" "sudo -n sed -i '' -E 's|address=/app\\.team1\\.test/[0-9.]+|address=/app.team1.test/10.7.6.181|' /opt/homebrew/etc/dnsmasq.conf && brew services restart dnsmasq"
  { echo; echo "### Immediately after change (cached old answer expected)"; dig app.team1.test +noall +answer; sleep 5; echo; echo "### +5s (still cached)"; dig app.team1.test +noall +answer; } 2>&1 | stamp | tee -a "$LOG"
  say "waiting for TTL expiry (~30s)"
  sleep 30
  { echo "### After TTL expiry (new answer expected)"; dig app.team1.test +noall +answer;
    echo; echo "### Manual flush + immediate resolution (new answer instantly)"; } 2>&1 | stamp | tee -a "$LOG"
  run "$MAC1_USER@$MAC1_IP" "sudo -n sed -i '' -E 's|address=/app\\.team1\\.test/[0-9.]+|address=/app.team1.test/10.7.6.181|' /opt/homebrew/etc/dnsmasq.conf && brew services restart dnsmasq" >/dev/null
  run "$MAC1_USER@$MAC1_IP" "sudo -n sed -i '' -E 's|address=/app\\.team1\\.test/[0-9.]+|address=/app.team1.test/10.7.6.180|' /opt/homebrew/etc/dnsmasq.conf && brew services restart dnsmasq"
  { sudo -n dscacheutil -flushcache 2>/dev/null || true; dscacheutil -flushcache 2>/dev/null; dig app.team1.test +noall +answer; } 2>&1 | stamp | tee -a "$LOG"
  say "EXPLANATION: clients cache DNS answers for the record TTL. A changed record only takes effect for cached clients after TTL expiry; a manual flush bypasses the cache. This is exactly how production systems cut traffic over via DNS."
}

demo_C(){
  say "EXTENSION C: backend isolation (pf)"
  LOG="$EV/C_isolation.txt"; : > "$LOG"
  { echo "### From Mac 2 (edge) -> Mac 3 backend port (ALLOWED)"; curl -s -m 5 "http://$MAC3_IP:3001/api/status"; echo;
    echo "### From Mac 2 (edge) -> Mac 4 backend port (ALLOWED)"; curl -s -m 5 "http://$MAC4_IP:3002/api/status"; echo; } 2>&1 | stamp | tee -a "$LOG"
  say "same request from Mac 1 (non-edge client) - should be BLOCKED"
  run "$MAC1_USER@$MAC1_IP" "curl -s -m 5 http://$MAC3_IP:3001/api/status; echo EXIT=\$?" 2>&1 | stamp | tee -a "$LOG"
  say "same request from Mac 4 (non-edge client) - should be BLOCKED"
  run "$MAC4_USER@$MAC4_IP" "curl -s -m 5 http://$MAC3_IP:3001/api/status; echo EXIT=\$?" 2>&1 | stamp | tee -a "$LOG"
  { echo; echo "### Edge still serves the full app (isolated backends reachable only by nginx)"; curl -s https://app.team1.test/api/status; echo; } 2>&1 | stamp | tee -a "$LOG"
  say "EXPLANATION: pf on the backend Macs passes only Mac 2's IP to ports 3001/3002 and blocks all other sources. Clients must go through the edge, which is the whole point of a reverse proxy."
}

demo_D(){
  say "EXTENSION D: backend failover (nginx passive health checks)"
  LOG="$EV/D_failover.txt"; : > "$LOG"
  { echo "### Baseline: both backends"; for i in 1 2 3 4; do curl -s https://app.team1.test/api/status; echo; done; } 2>&1 | stamp | tee -a "$LOG"
  say "STOPPING Backend A on Mac 3"
  run "$MAC3_USER@$MAC3_IP" 'pkill -f "PORT=3001" || pkill -f "python3 server.py" || true'
  { echo; echo "### While A is down: ALL requests served by B (no client-visible errors)"; for i in 1 2 3 4 5 6; do curl -s https://app.team1.test/api/status; echo; done; } 2>&1 | stamp | tee -a "$LOG"
  say "RESTARTING Backend A"
  run "$MAC3_USER@$MAC3_IP" 'cd ~/CN-Project && nohup env BACKEND=A PORT=3001 python3 server.py >/tmp/backendA.log 2>&1 & sleep 1; curl -s http://127.0.0.1:3001/api/status'
  sleep 11
  { echo; echo "### After A recovers: round-robin resumes"; for i in 1 2 3 4; do curl -s https://app.team1.test/api/status; echo; done; } 2>&1 | stamp | tee -a "$LOG"
  say "EXPLANATION: nginx marks a server down after max_fails within fail_timeout (10s) and routes only to the healthy peer; proxy_next_upstream even retries the first failed request on the peer, so clients see no 502. After fail_timeout it retries A and load balancing resumes. The single point of failure left is the edge itself (Mac 2) - Extension E addresses it."
}

demo_E(){
  say "EXTENSION E: DNS-based edge cutover 10.7.6.180 -> standby 10.7.26.238"
  LOG="$EV/E_cutover.txt"; : > "$LOG"
  say "step 1: standby edge on Mac 3 must already serve the app (cert included)"
  { curl -s --resolve app.team1.test:443:"$MAC3_IP" https://app.team1.test/api/status; echo; } 2>&1 | stamp | tee -a "$LOG"
  say "step 2: repoint DNS record on BOTH resolvers to the standby edge"
  for H in "$MAC1_USER@$MAC1_IP" "$MAC3_USER@$MAC3_IP"; do
    run "$H" "sudo -n sed -i '' -E 's|address=/app\\.team1\\.test/[0-9.]+|address=/app.team1.test/$MAC3_IP|; s|address=/api\\.team1\\.test/[0-9.]+|address=/api.team1.test/$MAC3_IP|' /opt/homebrew/etc/dnsmasq.conf && brew services restart dnsmasq"
  done
  { echo; echo "### Repeated lookups: old IP ($MAC2_IP) while TTL unexpired, then new IP ($MAC3_IP)"; for i in 1 2 3; do dig app.team1.test +short; sleep 10; echo "-- +10s"; done; } 2>&1 | stamp | tee -a "$LOG"
  { echo; echo "### App through the NEW edge (same domain, no cert warning)"; curl -s https://app.team1.test/api/status; echo; } 2>&1 | stamp | tee -a "$LOG"
  say "step 3: restore record to Mac 2 edge"
  for H in "$MAC1_USER@$MAC1_IP" "$MAC3_USER@$MAC3_IP"; do
    run "$H" "sudo -n sed -i '' -E 's|address=/app\\.team1\\.test/[0-9.]+|address=/app.team1.test/$MAC2_IP|; s|address=/api\\.team1\\.test/[0-9.]+|address=/api.team1.test/$MAC2_IP|' /opt/homebrew/etc/dnsmasq.conf && brew services restart dnsmasq"
  done
  { echo; echo "### Restored:"; dig app.team1.test +short; } 2>&1 | stamp | tee -a "$LOG"
  say "EXPLANATION: migrating the edge is a DNS record change. Clients with cached answers keep hitting the old edge for up to TTL seconds - that is why production uses short TTLs before planned cutover."
}

case "${1:-}" in
  A) demo_A ;; B) demo_B ;; C) demo_C ;; D) demo_D ;; E) demo_E ;;
  *) echo "usage: $0 A|B|C|D|E"; exit 1 ;;
esac
printf '\nEvidence saved in %s\n' "$EV"
