#!/bin/bash
# Run as root on the phone: deb-src and build dependencies for build-modem-debs.sh
set -euo pipefail
if ! grep -rqs 'deb-src http://deb.debian.org/debian forky' /etc/apt/sources.list.d/debian-src.list; then
  echo 'deb-src http://deb.debian.org/debian forky main' > /etc/apt/sources.list.d/debian-src.list
fi
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential devscripts quilt equivs git curl >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get build-dep -y -qq modemmanager 81voltd >/dev/null
echo deps-ok
