# Phase 2 — as deployed (run everything from Mac 2)

Roles: **Mac 3 = Saman** (Backend A + backup DNS + standby edge + firewall), **Mac 4 = Drishti** (Backend B + firewall).

Note: the Extension A backup DNS was deployed on **Mac 3 (Saman)**, not Mac 4 as first planned in
TEAM_GUIDE.md — the requirement is only "another Mac, not Mac 1", and Mac 3 also hosts the
standby edge (Extension E), so one extra machine concentrates the Phase 2 extras.

## Inventory (actual IPs)

| Mac | IP | Role | Services |
|---|---|---|---|
| 1 | 10.7.7.75 | Primary DNS | dnsmasq :53 (records in /opt/homebrew/etc/team.hosts) |
| 2 | 10.7.6.180 | Edge | nginx :443 (TLS, mkcert CA), load balancer |
| 3 | 10.7.26.238 | Backend A + Phase 2 extras | server.py :3001, dnsmasq :53 (backup), nginx :443 (standby), pf |
| 4 | 10.7.21.46 | Backend B | server.py :3002, pf |

Domain: `app.team1.test` -> edge `10.7.6.180` (TTL 30)

## Evaluation redo procedure

Reset to Phase 1 baseline:      `./phase2_reset.sh`  *(needs the one-time SSH prep — see below)*
Re-apply all Phase 2 configs:   `./phase2_setup.sh all`

Run demos live, in this order (each saves evidence to `~/cn-project/evidence/phase2/`):

| Demo | Command | What it shows |
|---|---|---|
| A | `./phase2_demo.sh A` | stop dnsmasq on Mac 1 -> clients resolve via Mac 3 backup |
| B | `./phase2_demo.sh B` | TTL 30: record change, stale cache, expiry, flush |
| C | `./phase2_demo.sh C` | pf: only Mac 2 reaches 3001/3002, clients blocked |
| D | `./phase2_demo.sh D` | stop Backend A -> all traffic on B -> restart -> A+B again |
| E | `./phase2_demo.sh E` | DNS cutover to standby edge on Mac 3, TTL effects |

**No-SSH fallback:** if the SSH one-time prep has not been done, run the demos manually with
the exact per-machine commands in `DEMOS.md` (same demos, copy-paste per Mac).

## One-time SSH prep (only if you want the scripts to drive the other Macs)

Per Mac (1, 3, 4): enable Remote Login, add Mac 2's public key to ~/.ssh/authorized_keys,
and enable passwordless sudo (sudoers.d/cn-lab). Then fill usernames in `hosts.env`.

Evidence lands in `~/cn-project/evidence/phase2/*.txt`.
