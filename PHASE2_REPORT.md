# Phase 2 Final Report — Harden, Recover, Troubleshoot

**Team 1** · Hardik (Mac 2, lead) · Prateek (Mac 1) · **Saman (Mac 3)** · Drishti (Mac 4)
**Deployment date:** 25 Nov 2026 · **Domain:** `app.team1.test` → edge `10.7.6.180`, TTL 30

---

## 1. What changed from Phase 1

Phase 1 gave us a working pipeline: private DNS on Mac 1 → nginx edge on Mac 2 → Python backends
on Mac 3/4, all over trusted HTTPS (mkcert CA). Phase 2 did not rebuild anything — it added
resilience and isolation on top:

| Extension | What was added | Where |
|---|---|---|
| A | Second DNS resolver + dual resolver lists on clients | **Mac 3 (Saman)** dnsmasq :53 |
| B | Live-reloadable DNS record file + TTL 30 caching demo | Mac 1 `/opt/homebrew/etc/team.hosts` |
| C | pf firewall: backends accept ONLY the edge on 3001/3002 | Mac 3 + Mac 4 (`/etc/pf.anchors/cn-isolation`) |
| D | nginx passive health checks (`max_fails=2 fail_timeout=10s`) | Mac 2 upstream block |
| E | Standby edge nginx with same cert + DNS cutover | **Mac 3 (Saman)** nginx :443 |

Deployment note: Extension A was deployed on **Mac 3 (Saman)** rather than Mac 4 as first
sketched in TEAM_GUIDE.md. The requirement is "a second resolver on another Mac (not Mac 1)",
which is satisfied; concentrating the Phase 2 extras on Mac 3 also matches Extension E, which
needs the standby edge there anyway.

## 2. Extension A — Backup DNS

**Done.** Mac 3 runs dnsmasq with the same records as Mac 1 (both names → 10.7.6.180,
local-ttl=30, upstreams 1.1.1.1/8.8.8.8). Clients (Mac 2/3/4) list two resolvers:
`10.7.7.75` then `10.7.26.238`; Mac 1 lists itself first.

**Verified live:** `dig @10.7.26.238 app.team1.test +short` → `10.7.6.180`
(evidence: `evidence/phase2/setup_verification.txt`).

**Failover demo** (DEMOS.md, Demo A): stop dnsmasq on Mac 1 → `dig` on a client shows
`;; SERVER: 10.7.26.238` answering, HTTPS keeps working → restart primary → SERVER returns
to 10.7.7.75. One-liner for the viva: **a DNS failure (can't find names) and an application
failure (names work, service dead) are different layers with different fixes.**

## 3. Extension B — TTL and controlled record change

**Done.** Records live in `/opt/homebrew/etc/team.hosts` on Mac 1, loaded via `addn-hosts`,
so a record change needs only `sudo killall -HUP dnsmasq` (no service restart). Every record
has TTL 30, and clients cache answers client-side.

**Demo** (Demo B): change record → clients keep the OLD answer until the 30 s TTL expires →
new answer after expiry → manual cache flush (`dscacheutil -flushcache` + HUP mDNSResponder)
shows the new answer instantly. Viva point: this is exactly how production moves traffic
between data centres — lower TTL, change record, let caches age out.

## 4. Extension C — Service isolation (pf firewall)

**Done.** On Mac 3 and Mac 4 an anchor `/etc/pf.anchors/cn-isolation` (referenced from
/etc/pf.conf) contains three rules: allow loopback; allow only 10.7.6.180 (Mac 2) to the
backend port (3001 on Mac 3, 3002 on Mac 4); block drop everyone else.

**Verified live:** the edge reaches both backends normally
(`curl http://10.7.26.238:3001/api/status` → Backend A OK, port 3002 → Backend B OK).
Non-edge clients time out (curl exit 28) — demonstrated in Demo C from Mac 4/Mac 1.

**Rollback kept:** `/tmp/pf.conf.phase1bak` on both machines; original pf.conf restored and
pf disabled with `pfctl -d` for the reset (phase2_reset.sh).

## 5. Extension D — High-availability failover

**Done.** Mac 2 upstream now declares `server ...:3001 max_fails=2 fail_timeout=10s` and
`server ...:3002 max_fails=2 fail_timeout=10s`.

**Observed live during deployment:** Backend A (Mac 3) was down while Phase 2 was being
installed — nginx automatically routed every request to Backend B with **zero client-visible
errors** (no 502s), and load balancing A/B resumed after Backend A restarted:
```
{"backend": "B", ...} {"backend": "A", ...} {"backend": "B", ...} {"backend": "A", ...}
```
Demo D repeats this deliberately, including the restart and recovery.

**Remaining single point of failure:** the edge itself (Mac 2). Eliminating it fully needs a
second active edge + health-checked failover (VRRP/keepalived-style) — our Extension E
provides the DNS-based version of that mitigation.

## 6. Extension E — Controlled edge migration (DNS cutover)

**Done.** Mac 3 runs a standby nginx with the same upstream, same TLS certificate
(`app.team1.test`), same protocols. Verified live:
`curl --resolve app.team1.test:443:10.7.26.238 https://app.team1.test/api/status` → Backend A OK.

**Demo** (Demo E): point the record at 10.7.26.238 on BOTH resolvers → clients with cached
answers keep hitting the old edge for ≤ 30 s (TTL effect visible with repeated `dig`) →
then traffic flows through the standby edge, same domain, no certificate warning → record
restored. This is production-style blue/green migration via DNS.

## 7. Extension F — Troubleshooting readiness

The fixed diagnosis order we will narrate at the faculty-fault challenge:
`dig` (DNS layer) → `nc -vz ... 443` (TCP layer) → `curl -v` (TLS layer) → response body/502
(application layer). The full runbook with expected outputs is `phase2/DEMOS.md`.

## 8. Evidence index

| File | Contents |
|---|---|
| `evidence/phase2/setup_verification.txt` | backup DNS answer, standby edge 200, edge→backends OK, round-robin A/B |
| `evidence/phase2/A_failover.txt` ... `E_cutover.txt` | filled during demo rehearsal (DEMOS.md tees every step) |
| Wireshark Phase 1 capture | DNS query/response, TCP handshake, TLS handshake |

## 9. Learning summary (one paragraph per extension)

- **A:** Redundancy at the resolver layer is cheap (one extra dnsmasq) but only helps if
  clients are configured to *try* it — resilience is a client-side policy, not just a server.
- **B:** DNS is eventually consistent by design; TTL is the knob controlling how long stale
  answers live. Manual flush = operators' escape hatch during migrations.
- **C:** A reverse proxy is pointless if backends are reachable directly — pf turned that
  architectural intent into an enforced rule, and taught us to keep rollback copies.
- **D:** Load balancers are also health managers: passive checks + upstream retry removed a
  whole class of user-visible errors with two config tokens.
- **E:** Edge machines are replaceable if the *name* points at the role, not the machine —
  DNS + short TTL is a poor man's load balancer for planned failover.
- **F:** Systems debugging is a layered search, not guesswork: test each layer in isolation,
  in order, and narrate — methodology earns partial credit even when the fix is incomplete.
