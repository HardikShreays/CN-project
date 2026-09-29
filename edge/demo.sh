#!/usr/bin/env bash
# Demo steps 3, 4, 5, 7 from a client Mac. Rerun with Backend A stopped for step 8.
# Usage: ./demo.sh [app.team1.test.crt]   (pass the crt if curl doesn't pick up the keychain)
set -u
H=app.team1.test
CA=${1:+--cacert $1}   # still full validation, just an explicit trust anchor (never -k)

echo "== DNS: $H should be Mac 2's IP"
dig +noall +answer "$H"

echo "== load balancing"
for i in 1 2 3 4 5 6; do
  curl -s $CA -o /dev/null -D - "https://$H/api/status" | grep -iE '^x-(backend|edge)' | tr -d '\r' | paste -sd' ' -
done

echo "== caching: full 200, then conditional 304"
curl -sI $CA "https://$H/api/catalog" | grep -iE '^HTTP|cache-control|etag'
ETAG=$(curl -sI $CA "https://$H/api/catalog" | awk 'tolower($1)=="etag:"{print $2}' | tr -d '\r')
curl -sI $CA -H "If-None-Match: $ETAG" "https://$H/api/catalog" | head -1
