# Phase 2 Demo Runbook — manual (no SSH), run demos in order A → E
# Evidence: every command below marked 💾 should be screenshotted or piped to a file.
# After all demos: run RESET commands at the bottom.

────────────────────────────────────────────────────────
DEMO A — Backup DNS failover (Extension A)
────────────────────────────────────────────────────────
Mac 2:  dig app.team1.test | grep -E "SERVER|IN A"     💾  (SERVER: 10.7.7.75)
Mac 1:  sudo brew services stop dnsmasq
Mac 2:  dig app.team1.test | grep -E "SERVER|IN A"     💾  (SERVER: 10.7.26.238 — backup answered!)
Mac 2:  curl -s https://app.team1.test/api/status      💾  (still works)
EXPLAIN: name resolution continued via Mac 3 while primary was down.
         DNS failure ≠ application failure.
Mac 1:  sudo brew services start dnsmasq
Mac 2:  dig app.team1.test | grep SERVER               💾  (back to 10.7.7.75)

────────────────────────────────────────────────────────
DEMO B — DNS TTL / cached record (Extension B)
────────────────────────────────────────────────────────
Mac 2:  dig app.team1.test +noall +answer              💾  (TTL 30, 10.7.6.180)
Mac 1:  sudo sed -i '' 's/10\.7\.6\.180/10.7.6.181/' /opt/homebrew/etc/team.hosts
Mac 1:  sudo killall -HUP dnsmasq
Mac 2:  dig app.team1.test +noall +answer              💾  (STILL old 10.7.6.180 — client cache!)
Mac 2:  sleep 30 && dig app.team1.test +noall +answer  💾  (now 10.7.6.181 — TTL expired)
Mac 2:  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
Mac 2:  dig app.team1.test +noall +answer              💾  (new IP immediately after flush)
EXPLAIN: clients cache answers for the TTL; changes propagate only after expiry.
         This is how production does DNS-based traffic cutover.
Mac 1:  sudo sed -i '' 's/10\.7\.6\.181/10.7.6.180/' /opt/homebrew/etc/team.hosts
Mac 1:  sudo killall -HUP dnsmasq

────────────────────────────────────────────────────────
DEMO C — Backend isolation (Extension C)
────────────────────────────────────────────────────────
Mac 2:  curl -s -m 5 http://10.7.26.238:3001/api/status        💾  (works — edge allowed)
Mac 2:  curl -s -m 5 http://10.7.21.46:3002/api/status        💾  (works — edge allowed)
Mac 4:  curl -s -m 5 http://10.7.26.238:3001/api/status; echo EXIT=$?   💾  (EXIT=28 timeout — blocked)
Mac 1:  curl -s -m 5 http://10.7.21.46:3002/api/status; echo EXIT=$?    💾  (EXIT=28 timeout — blocked)
Mac 2:  curl -s https://app.team1.test/api/status              💾  (app unaffected)
EXPLAIN: pf on backends accepts only Mac 2 (the edge) on 3001/3002.
         Clients must go through the reverse proxy — that is its purpose.
         Rollback copies live at /tmp/pf.conf.phase1bak on Mac 3 & 4.

────────────────────────────────────────────────────────
DEMO D — Backend failover (Extension D)
────────────────────────────────────────────────────────
Mac 2:  for i in {1..6}; do curl -s https://app.team1.test/api/status; echo; done   💾 (A,B,A,B…)
Mac 3:  pkill -f "PORT=3001" ; pkill -f "server.py"
Mac 2:  for i in {1..6}; do curl -s https://app.team1.test/api/status; echo; done   💾 (ALL "backend":"B")
Mac 2:  for i in {1..3}; do curl -s -o /dev/null -w "%{http_code}\n" https://app.team1.test/api/status; done  💾 (200, no 502)
Mac 3:  cd ~/CN-Project && nohup env BACKEND=A PORT=3001 python3 server.py > /tmp/backendA.log 2>&1 &
Mac 2:  sleep 12; for i in {1..4}; do curl -s https://app.team1.test/api/status; echo; done  💾 (A,B again)
EXPLAIN: nginx passive health check (max_fails=2, fail_timeout=10s) + proxy_next_upstream
         retry = no client-visible errors. Remaining SPOF = the edge itself (→ Extension E).

────────────────────────────────────────────────────────
DEMO E — Edge migration / DNS cutover (Extension E)
────────────────────────────────────────────────────────
Mac 2:  curl -s --resolve app.team1.test:443:10.7.26.238 https://app.team1.test/api/status  💾 (standby edge works)
Mac 1:  sudo sed -i '' 's/10\.7\.6\.180/10.7.26.238/' /opt/homebrew/etc/team.hosts
Mac 1:  sudo killall -HUP dnsmasq
Mac 3:  sudo sed -i '' 's/address=\/app\.team1\.test\/[0-9.]*/address=\/app.team1.test\/10.7.26.238/; s/address=\/api\.team1\.test\/[0-9.]*/address=\/api.team1.test\/10.7.26.238/' /opt/homebrew/etc/dnsmasq.conf
Mac 3:  sudo brew services restart dnsmasq
Mac 2:  for i in 1 2 3; do dig app.team1.test +short; sleep 10; done    💾 (old edge until TTL, then 10.7.26.238)
Mac 2:  curl -s https://app.team1.test/api/status                       💾 (app now via STANDBY edge, no cert warning)
EXPLAIN: migrating the edge = changing a DNS record. Cached clients hit the old
         edge for ≤ TTL seconds; that's why you lower TTL before a planned cutover.
RESTORE:
Mac 1:  sudo sed -i '' 's/10\.7\.26\.238/10.7.6.180/' /opt/homebrew/etc/team.hosts && sudo killall -HUP dnsmasq
Mac 3:  sudo sed -i '' 's/address=\/app\.team1\.test\/[0-9.]*/address=\/app.team1.test\/10.7.6.180/; s/address=\/api\.team1\.test\/[0-9.]*/address=\/api.team1.test\/10.7.6.180/' /opt/homebrew/etc/dnsmasq.conf && sudo brew services restart dnsmasq
Mac 2:  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

────────────────────────────────────────────────────────
FULL RESET (back to Phase 1 baseline)
────────────────────────────────────────────────────────
Mac 1:  sudo sed -i '' 's/10\.7\.6\.181/10.7.6.180/; s/10\.7\.26\.238/10.7.6.180/' /opt/homebrew/etc/team.hosts
Mac 1:  sudo killall -HUP dnsmasq
Mac 3:  sudo cp /tmp/pf.conf.phase1bak /etc/pf.conf && sudo pfctl -f /etc/pf.conf && sudo pfctl -d
Mac 3:  brew services stop dnsmasq; brew services stop nginx
Mac 4:  sudo cp /tmp/pf.conf.phase1bak /etc/pf.conf && sudo pfctl -f /etc/pf.conf && sudo pfctl -d
Mac 2:  networksetup -setdnsservers Wi-Fi 10.7.7.75 10.7.26.238

────────────────────────────────────────────────────────
FACULTY-FAULT DIAGNOSIS METHOD (Extension F)
────────────────────────────────────────────────────────
dig app.team1.test            → no answer / wrong IP  = DNS layer
nc -vz app.team1.test 443     → refused/timeout       = TCP layer
curl -v https://app.team1.test → cert/handshake error = TLS layer
curl → 502 / wrong content    = application/backend layer
Always narrate this order out loud during the evaluation.
