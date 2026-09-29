# Edge (Mac 2) — nginx reverse proxy, load balancer, TLS

Owner: Hardik

## Setup (Phase 1)

```bash
brew install nginx
./gen-cert.sh                          # makes app.team1.test.crt/.key in /opt/homebrew/etc/nginx/certs
./deploy.sh <MAC3_IP> <MAC4_IP>        # fills IPs into nginx.conf, nginx -t, starts/reloads
```

Copy **only the .crt** to the client Macs, then on each client:

```bash
./trust-cert.sh app.team1.test.crt
./demo.sh                              # dns -> load balancing -> caching
./demo.sh app.team1.test.crt           # if curl ignores the keychain (still validates, no -k)
```

Evidence (Task G): run `./capture.sh` on Mac 2 while a client runs `demo.sh`. The pcap lands in `evidence/`.

Useful while demoing:

```bash
tail -f /opt/homebrew/var/log/nginx/access.log   # client:port -> which backend [status]
nginx -s reload                                  # after editing the conf
nginx -s stop
```

Rollback: `cp /opt/homebrew/etc/nginx/nginx.conf.orig /opt/homebrew/etc/nginx/nginx.conf`

Port 443 blocked? Change `listen 443` to `8443` and use `https://app.team1.test:8443`.

## Tested on my Mac (both backends on localhost)

| Check | Result |
|---|---|
| repeated `/api/status` | `X-Backend` A, B, A, B … |
| TLS | TLSv1.3, ALPN h2 → `HTTP/2 200` |
| `/api/catalog` | `Cache-Control: max-age=60` + ETag; `If-None-Match` → `304` |
| `http://` | `301` → `https://` |
| Backend A stopped | every request served by B, no errors |
| both stopped | `502 Bad Gateway` from nginx |
| A restarted | alternation comes back |

## Extension D — HA failover

- `max_fails=1 fail_timeout=10s`: a backend that errors once is skipped for 10s, then tried again (passive health check; the open-source nginx has no active probes).
- `proxy_next_upstream error timeout http_502 http_503`: the request that hit the dead backend is retried on the other one, so the client never sees the failure.
- `proxy_connect_timeout 2s`: a dead Mac is detected in 2s instead of 60s.
- **Still a single point of failure: the edge itself.** If Mac 2 dies, DNS still gives out its IP and everything fails. The fix is two edges behind a floating IP (keepalived/VRRP), or several DNS A records plus health-checked DNS (like Route 53 failover). A cloud ALB is already several nodes behind one name.

## Extension E — DNS cutover to a standby edge

1. On the standby Mac (say Mac 3): `brew install nginx`, copy `app.team1.test.crt` **and** `.key` from Mac 2 into `/opt/homebrew/etc/nginx/certs/` (copy the key privately, e.g. AirDrop, never commit it), then `./deploy.sh <MAC3_IP> <MAC4_IP>`.
2. Mac 4's pf rules only let Mac 2 in, so add `pass in quick proto tcp from <MAC3_IP> to any port 3002` there. Mac 3 reaching its own backend goes over lo0, which is already allowed.
3. Mac 1 edits `team.hosts` to point `app.team1.test` at Mac 3, then `sudo killall -HUP dnsmasq`.
4. A client that resolved in the last 30s (TTL) still gets `X-Edge: <mac2>`. After the TTL runs out, or after `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`, it gets `X-Edge: <mac3>`. Keep Mac 2 up during this, since old clients are still using it.

## Viva notes

- **Why clients never know backend IPs:** DNS only ever returns Mac 2's IP. nginx opens a *second* TCP connection to a backend, so there are two separate socket pairs (client↔edge:443 and edge:ephemeral↔backend:3001/3002). Backends can change freely and the firewall can hide them.
- **TLS termination:** the handshake (ClientHello → ServerHello → Certificate → key exchange → Finished) happens between the client and nginx. Past the edge it's plain HTTP on the LAN, which the capture shows: 443 is unreadable, 3001/3002 is readable.
- **Cert trust:** it's self-signed, so nobody vouches for it until we add it to each client's keychain. The browser checks that the name is in the SAN (`app.team1.test`, `api.team1.test`), that the dates are valid, and that the signature chains to something trusted.
- **Caching:** within `max-age=60` the browser doesn't even ask (fresh hit). After that it sends `If-None-Match` and gets `304` with no body (conditional). Without an ETag it would be a full `200`. Both backends serve the same ETag, so the 304 works whichever backend answers.
- **Cloud equivalent:** this Mac is doing the job of AWS ALB / GCP LB: TLS termination, a target group (`upstream`), and health checks.
