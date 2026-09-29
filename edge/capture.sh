#!/usr/bin/env bash
# Task G, run on Mac 2 while a client runs demo.sh. Ctrl-C to stop.
# Captures BOTH legs: client -> edge (443, encrypted TLS) and edge -> backends (3001/3002, plain HTTP).
# That contrast is the TLS-termination proof. Open the .pcap in Wireshark.
set -euo pipefail
IF=$(route -n get default | awk '/interface:/{print $2}')
OUT="$(dirname "$0")/../evidence/edge-$(date +%H%M%S).pcap"
mkdir -p "$(dirname "$OUT")"
echo "capturing on $IF -> $OUT"
sudo tcpdump -i "$IF" -w "$OUT" 'tcp port 443 or tcp port 80 or tcp port 3001 or tcp port 3002 or port 53'
