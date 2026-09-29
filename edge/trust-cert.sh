#!/usr/bin/env bash
# Run on each CLIENT Mac (Mac 1, Mac 4) after copying the .crt over from Mac 2.
# Usage: ./trust-cert.sh app.team1.test.crt
# Undo:  sudo security remove-trusted-cert -d app.team1.test.crt
set -euo pipefail
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "${1:-app.team1.test.crt}"
echo "trusted. Safari/Chrome should show the padlock on https://app.team1.test with no warning."
