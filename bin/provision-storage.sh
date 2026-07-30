#!/usr/bin/env bash
#
# Provision persistent storage for the Inkwell Kamal deployment.
# Run as root on the production server (5.161.252.146).
#
# Creates the bind-mount directories referenced in config/deploy.yml:
#   /var/lib/inkwell           -> /rails/storage (SQLite DBs + Active Storage)
#   /var/lib/inkwell/logs      -> /rails/log
#   /var/cache/inkwell/builds  -> /rails/builds (Hugo build workspaces)
#
# /var/lib holds irreplaceable state (back it up); /var/cache holds
# regenerable scratch (don't). The Rails container runs as uid/gid 1000, so
# the dirs must be owned by 1000 or the app can't write to them. Safe to
# re-run (idempotent).

set -euo pipefail

BASE=/var/lib/inkwell
CACHE=/var/cache/inkwell
APP_UID=1000
APP_GID=1000

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

echo "Creating $BASE, $BASE/logs, and $CACHE/builds ..."
mkdir -p "$BASE/logs" "$CACHE/builds"

echo "Setting ownership to $APP_UID:$APP_GID ..."
chown -R "$APP_UID:$APP_GID" "$BASE" "$CACHE"

echo "Setting permissions to 750 ..."
chmod -R 750 "$BASE" "$CACHE"

echo
echo "Done. Current state:"
ls -ld "$BASE" "$BASE/logs" "$CACHE/builds"
