# CN Project — Team Guide

**Team:** Hardik (lead) · Prateek · Saman · Drishti
**Goal:** a laptop types `https://app.team1.test`. Our own DNS turns that name into Mac 2's IP, Mac 2 (nginx) handles HTTPS, and Mac 2 passes the request to Backend A or B. Then we prove every step with tools.

You don't need to know networking to *run* this. Everything is one command. You **do** need to understand it for the viva, so read the "Understand it" box under your name.

---

## Who does what

| Person | Laptop | Runs | Phase 1 | Phase 2 | Paperwork |
|---|---|---|---|---|---|
| **Prateek** | Mac 1 | `./prateek.sh` | LAN check (A), DNS server (B), DNS failure demos | TTL demo (Ext B) | IP table, topology diagram |
| **Hardik** | Mac 2 | `./hardik.sh` | nginx edge + load balancing (D), HTTPS (E) | HA failover (Ext D), edge cutover (Ext E), fault drills (Ext F) | Architecture doc, final report |
| **Saman** | Mac 3 | `./saman.sh` | Backend A (C), caching (F) | Firewall (Ext C), standby edge (Ext E) | Config bundle + backend notes |
| **Drishti** | Mac 4 | `./drishti.sh` | Backend B (C), Wireshark captures (G) | Backup DNS (Ext A) | Evidence folder |

Everyone also has `./everyone.sh` (checks and demos any Mac can run).
Type any script with no command, e.g. `./saman.sh`, to see its list of commands.

```
Client (Mac 1 / Mac 4)
   │ 1. "where is app.team1.test?"  ──UDP 53──▶  Mac 1 dnsmasq (backup: Mac 4)
   │ 2. HTTPS to that IP            ──TCP 443─▶  Mac 2 nginx  (TLS ends here)
   │                                                ├──TCP 3001──▶ Mac 3 Backend A
   │                                                └──TCP 3002──▶ Mac 4 Backend B
```

---

## Step 0 — Everyone, once (about 1 hour)

- [ ] Install Homebrew from https://brew.sh (paste the command it shows into Terminal).
- [ ] `brew install --cask wireshark-app` (everyone), then:
  - Prateek and Drishti: `brew install dnsmasq`
  - Hardik and Saman: `brew install nginx openssl`
- [ ] Get the project: `git clone https://github.com/HardikShreays/CN-project.git && cd CN-project`
- [ ] **All 4 Macs on the same phone hotspot or home router, not college Wi-Fi.** College Wi-Fi usually blocks laptop-to-laptop traffic.
- [ ] System Settings → Network → Firewall → Options → turn **off** "stealth mode", otherwise ping fails.
- [ ] Run `./everyone.sh info` and send your `ip` line to the group.
- [ ] **Stop your IP from changing**, because a changed IP breaks everything. Go to System Settings → Wi-Fi → Details (next to the network) → TCP/IP → Configure IPv4: **Manually**. Enter the same IP, subnet mask and router that `info` showed.
- [ ] **Hardik** fills the 4 IPs into `team.env`, then commits and pushes. Everyone else runs `git pull`.

> **`team.env` is the only file anyone edits.** All the scripts read the IPs from it.
> If an IP changes: fix `team.env`, push, everyone pulls, and each person reruns their start command.

**Gate 1 (Prateek checks):** everyone runs `./everyone.sh ping`. All 4 lines should show `0.0% packet loss`.

---

## Prateek — Mac 1 — DNS

### Phase 1
- [ ] **Task A:** collect everyone's `./everyone.sh info` output into one IP table (name, IP, netmask, gateway, MAC, role). Screenshot `./everyone.sh ping` from each Mac. Draw the diagram above in draw.io using real IPs.
- [ ] **Task B:** `./prateek.sh dns`
  You should see `app.team1.test. 30 IN A <Mac 2 IP>`. 30 is the TTL in seconds.
- [ ] Make your own Mac use it: `./everyone.sh use-dns`
- [ ] Ask **Drishti and Saman** to run `./everyone.sh use-dns` too.
- [ ] Watch queries arrive live: `./prateek.sh log` (Ctrl-C to quit). Screenshot it while someone runs `dig app.team1.test`.

**Failure demos (screenshot each, then undo):**
| Demo | Do | You'll see | Undo |
|---|---|---|---|
| Wrong DNS server | on a client: `./everyone.sh use-dns 10.9.9.9` then `dig app.team1.test` and `ping <Mac 2 IP>` | dig times out, ping works. **DNS and IP are separate layers.** | `./everyone.sh use-dns` |
| Wrong record | `./prateek.sh point 10.9.9.9`, client runs `./everyone.sh demo` | the name resolves (to the wrong IP) but HTTPS fails. **DNS is a phonebook, not a connection.** | `./prateek.sh restore` |

### Phase 2 — Ext B (TTL)
- [ ] `./prateek.sh ttl-demo`: this Mac keeps getting the **old** IP for about 30s, while `dig` (which skips the cache) shows the new one right away. Screenshot it.
- [ ] Run it again, and in a second tab run `./everyone.sh flush` right after the record changes. The change is instant.
- [ ] From Phase 2 on, any `point` / `restore` must also be done on **Drishti's** backup DNS (`./drishti.sh point <ip>`).

> **Understand it:** DNS uses UDP port 53. dnsmasq is *authoritative* for `team1.test` (it answers itself) and *forwards* everything else to 8.8.8.8. The TTL tells clients how long to cache the answer, which is why a DNS change isn't instant in real systems (migrations lower the TTL first). We use `.test` because `.local` belongs to macOS mDNS/Bonjour. Cloud equivalent: Route 53 private hosted zone.

---

## Hardik — Mac 2 — Edge (nginx, HTTPS, load balancing)

### Phase 1
- [ ] **Task E first:** `./hardik.sh cert`, then `git add edge/app.team1.test.crt && git commit -m "edge cert" && git push`
  Everyone pulls. The `.key` never leaves this Mac and is git-ignored.
- [ ] Wait until Saman and Drishti have their backends running, then run **Task D:** `./hardik.sh edge`
- [ ] Client Macs (Mac 1, Mac 4) run `./everyone.sh trust` once, so the browser shows no warning.
- [ ] From a client: `./everyone.sh demo`. You should see `x-backend: A` and `x-backend: B` alternating, `HTTP/2 200`, then `200` followed by `304`.
- [ ] Open `https://app.team1.test` in Safari: padlock, no warning, and no IP in the URL.
- [ ] `./hardik.sh log` shows which backend served each request.
- [ ] `./hardik.sh capture` while a client runs `demo`. Traffic on 443 is encrypted, while traffic on 3001/3002 is readable HTTP. That contrast is the TLS-termination proof.

**Failure demos:**
| Demo | Do | You'll see |
|---|---|---|
| Both backends down | Saman and Drishti press Ctrl-C | `502 Bad Gateway`. DNS and TLS still work, so the fault is *behind* the edge. |
| Wrong port | client: `curl https://app.team1.test:9443` | `Connection refused` (a TCP RST in Wireshark). The host is fine; the port is wrong. |

### Phase 2
- [ ] **Ext D (failover):** Saman presses Ctrl-C on Backend A, and a client runs `./everyone.sh demo`: all B, no errors. Saman restarts A, wait about 10s, and A/B alternate again.
- [ ] **Ext E (edge cutover):** AirDrop `app.team1.test.key` and `.crt` from `/opt/homebrew/etc/nginx/certs/` to Saman, who puts them in the same folder on Mac 3 (`mkdir -p /opt/homebrew/etc/nginx/certs` first). Saman runs `./saman.sh standby-edge`. Both DNS servers run `point <Mac 3 IP>`. The client's `demo` shows `x-edge` change from your Mac's name to Saman's after the TTL. Then `./hardik.sh stop` to prove Mac 2 isn't needed. Afterwards: `./hardik.sh edge`, and both DNS servers run `restore`.
- [ ] **Ext F (fault drills):** one person secretly breaks something, another runs `./everyone.sh diagnose` and reads down the list. **The first FAIL is the broken layer.** Do at least 3 drills.

> **Understand it:** nginx is a *reverse* proxy: it sits in front of servers, whereas a forward proxy sits in front of clients. Clients only ever learn Mac 2's IP from DNS, and nginx opens a *second* TCP connection to a backend, so backends stay hidden and can change. TLS handshake: ClientHello → ServerHello → Certificate → key exchange → Finished. After that everything is encrypted. The browser trusts our cert because it's in the keychain and the name matches the SAN (`app.team1.test`). Round-robin = take turns; least_conn = pick the least busy. Failover: `max_fails=1 fail_timeout=10s` skips a dead backend for 10s, and `proxy_next_upstream` retries the failed request on the other backend (these are *passive* health checks). **Still a single point of failure: nginx itself.** The fix is two edges plus a floating IP (keepalived/VRRP) or DNS failover. Cloud equivalent: AWS ALB.

---

## Saman — Mac 3 — Backend A, caching, firewall

### Phase 1
- [ ] **Task C:** `./saman.sh backend`. Leave the window open. Click **Allow** if macOS asks about python3.
- [ ] Check from Hardik's Mac: `curl -i http://<Mac 3 IP>:3001/api/status` should show `X-Backend: A`.
- [ ] Check it listens on all interfaces: `lsof -iTCP:3001 -sTCP:LISTEN` should show `*:3001`, not `127.0.0.1`.
- [ ] **Task F (caching):** on a client, `./everyone.sh demo` shows `cache-control: max-age=60`, an `etag`, and then `304`. Also in Safari/Chrome: DevTools → Network → open `https://app.team1.test/api/catalog` twice. The second load says "(disk cache)".
- [ ] **Failure demo:** Ctrl-C your backend during Hardik's failover demo.

### Phase 2
- [ ] **Ext C (firewall):** `./saman.sh firewall-on`
  - From Mac 1: `nc -vz -G 3 <Mac 3 IP> 3001` **times out** (blocked).
  - From Mac 2: `curl http://<Mac 3 IP>:3001/api/status` **works**, so the edge still gets in.
  - A client's `./everyone.sh demo` still works, because it goes through the edge.
  - Then **roll back**: `./saman.sh firewall-off` (the rules must be restored after the demo).
- [ ] **Ext E:** `./saman.sh standby-edge` once Hardik has AirDropped the cert and key. Stop it with `./saman.sh standby-stop`.

> **Understand it:** a socket is IP + port, and each connection is a pair of sockets. `0.0.0.0` means "listen on every network card", while `127.0.0.1` means "only this Mac", so other Macs couldn't reach it. Caching has three cases. A **fresh hit** within 60s sends no request at all. A **conditional request** sends `If-None-Match`; the answer is `304` with no body. A **full request** gets a `200` with a body. The firewall *drops* packets silently, which looks like a timeout; a *reject* would give "connection refused" immediately. CDNs use exactly these cache headers.

---

## Drishti — Mac 4 — Backend B, Wireshark, backup DNS

### Phase 1
- [ ] **Task C:** `./drishti.sh backend`. Leave it open, click **Allow**, and check it the same way Saman does (port 3002, `X-Backend: B`).
- [ ] Be a client: `./everyone.sh use-dns` then `./everyone.sh trust`.
- [ ] **Task G (the key evidence):** in a *second* Terminal tab run `./drishti.sh capture`. It records one full request and saves a `.pcap` in `evidence/06-wireshark/`. Open it in Wireshark and filter with `dns || tcp.port==443`. Screenshot and label:
  - [ ] DNS query + response (UDP 53, answer = Mac 2's IP)
  - [ ] SYN → SYN/ACK → ACK (your port like 5xxxx → 443; click a packet to show Seq/Ack numbers)
  - [ ] Client Hello, Server Hello, **Certificate**, key exchange, Change Cipher Spec, Finished
  - [ ] "Application Data", which is the HTTP, now encrypted
  - [ ] Capture Hardik's wrong-port demo too and screenshot the RST.
- [ ] Make a one-page OSI sheet: DNS and HTTP = Application · TLS = between Application and Transport · TCP/UDP = Transport · IP = Network · Wi-Fi/Ethernet = Link.

### Phase 2 — Ext A (backup DNS)
- [ ] `./drishti.sh backup-dns`
- [ ] Clients switch to both servers: `./everyone.sh use-dns both`
- [ ] Prateek runs `./prateek.sh stop`. A client's `dig app.team1.test` still answers after a short pause, and the `SERVER:` line now shows Mac 4. Screenshot it, then Prateek runs `./prateek.sh dns` again.
- [ ] Remember: record changes now go on **both** DNS servers (`./drishti.sh point <ip>` / `restore`).

> **Understand it:** the TCP three-way handshake happens before any data. Seq/Ack numbers make TCP reliable: every byte is counted and acknowledged. The client uses a random *ephemeral* port (49152+), while servers use *well-known* ports (53, 443). DNS uses UDP because it's one small question and one answer, with no handshake needed. The payload is unreadable in Wireshark because TLS encrypts it. The client moves to the second DNS server only after the first one times out. A **DNS failure** means names don't resolve at all. An **app failure** means names resolve but you get a 502 or "refused".

---

## Evidence folder (anything must be findable in 30 seconds)

```
evidence/01-lan  02-dns  03-lb  04-tls  05-caching  06-wireshark  07-failures  08-phase2-backup-dns  08-phase2-ttl  08-phase2-firewall  08-phase2-failover  08-phase2-cutover
```
Tip: save terminal output directly, e.g. `./everyone.sh demo | tee evidence/03-lb/demo.txt`.
Drishti owns the folder; everyone drops their screenshots into it.

## Gates — don't move on until the gate passes

| Gate | Done when | Who |
|---|---|---|
| G1 LAN | `./everyone.sh ping` all green on every Mac; IPs fixed; IP table done | Prateek |
| G2 DNS + backends | `dig app.team1.test` works on 2 clients; Mac 2 can curl both backends | Prateek, Saman, Drishti |
| G3 Edge | `https://app.team1.test` with no warning; A/B alternate | Hardik |
| G4 Evidence | 304 shown, `.pcap` labelled, 5 failure demos screenshotted | Saman, Drishti, all |
| **Phase 1 review** | full dry run of demo steps 1–8 | all |
| G5 | backup DNS, TTL, firewall, failover | Drishti, Prateek, Saman, Hardik |
| G6 | edge cutover + 3 fault drills | Hardik + all |
| **Final** | full 11-step dry run **twice**, rotating who presents each step | all |

## Final demo — 11 steps and the command for each
1. Topology + IP table: Prateek's diagram
2. Everyone on the LAN: `./everyone.sh ping`
3. DNS: `dig app.team1.test`
4. HTTPS by name: Safari `https://app.team1.test`
5. Load balancing: `./everyone.sh demo`
6. Wireshark: Drishti's labelled `.pcap`
7. Caching: `./everyone.sh demo` (the 304 part)
8. Backend down: Saman presses Ctrl-C, then `./everyone.sh demo`
9. Phase 2: backup DNS / TTL / cutover
10. Faculty fault: `./everyone.sh diagnose`, read top to bottom
11. Viva: everyone, from understanding, not from notes

## When something breaks
| Symptom | Likely cause | Fix |
|---|---|---|
| ping fails between Macs | college Wi-Fi or stealth mode | use a hotspot; turn stealth mode off |
| everything broke after a reconnect | IP changed | fix it in System Settings, update `team.env`, push/pull, rerun start commands |
| `dig` gives no answer | DNS not running, or client not pointed at it | `./prateek.sh dns`, `./everyone.sh use-dns` |
| 502 Bad Gateway | both backends down, or a wrong IP in `team.env` | start the backends; check IPs; `./hardik.sh edge` |
| cert warning in the browser | cert not trusted, or old cert | `git pull`, `./everyone.sh trust` |
| internet stopped working | DNS pointed at a stopped server | `./everyone.sh use-dns reset` |
| "!! MAC1_IP is empty" | `team.env` not filled or not pulled | `git pull` |

Using an Intel Mac? Nothing changes; the scripts detect `/usr/local` automatically.
**Every evening:** one person explains their part to the other three, without notes.
