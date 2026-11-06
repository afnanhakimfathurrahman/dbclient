#!/bin/bash
# Runs inside the Linux build container: builds the app from /in/source.tar
# (the app/ folder) and writes db-client-linux-x64.tar.gz to /out.
set -euo pipefail

mkdir -p /src
tar -xf /in/source.tar -C /src
cd /src/app
flutter pub get >/dev/null
flutter build linux --release

rm -rf /pkg && mkdir -p /pkg
cp -r build/linux/x64/release/bundle /pkg/db-client
tar -czf /out/db-client-linux-x64.tar.gz -C /pkg db-client

if ldd /pkg/db-client/db_client | grep "not found"; then
  echo "Missing libraries in the Linux build" >&2
  exit 1
fi
