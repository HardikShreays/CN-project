#!/usr/bin/env bash
# Run on Mac 2. Creates a self-signed cert valid for app.team1.test and api.team1.test.
set -euo pipefail
OPENSSL="$(brew --prefix openssl)/bin/openssl"   # brew openssl; macOS LibreSSL lacks some flags
DIR="$(brew --prefix)/etc/nginx/certs"
mkdir -p "$DIR" && cd "$DIR"

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 365 \
  -keyout app.team1.test.key -out app.team1.test.crt \
  -subj "/CN=app.team1.test" \
  -addext "subjectAltName=DNS:app.team1.test,DNS:api.team1.test" \
  -addext "extendedKeyUsage=serverAuth"

chmod 600 app.team1.test.key
"$OPENSSL" x509 -in app.team1.test.crt -noout -subject -ext subjectAltName -dates
echo "Now copy $DIR/app.team1.test.crt (NOT the .key) to every client Mac."
