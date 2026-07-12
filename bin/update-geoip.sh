#!/usr/bin/env bash
#
# Download/refresh the DB-IP City Lite geo database on the production server
# (used by Ahoy visit geocoding — see config/initializers/geocoder.rb).
# Run from your machine; ssh's to the server. Safe to re-run: downloads to a
# temp file and swaps atomically, so the app never sees a partial file.
#
#   bin/update-geoip.sh            # current month's database
#   bin/update-geoip.sh 2026-06    # a specific month (YYYY-MM)
#
# DB-IP publishes monthly (CC BY 4.0, no account). After a refresh, restart
# the app to remap the file: kamal app boot
#
# The Rails container runs as uid/gid 1000 (see bin/provision-storage.sh),
# so the file must be owned 1000:1000 or the app can't read it.

set -euo pipefail

HOST="${GEOIP_HOST:-root@5.161.252.146}"
MONTH="${1:-$(date +%Y-%m)}"
URL="https://download.db-ip.com/free/dbip-city-lite-${MONTH}.mmdb.gz"
DIR=/var/lib/inkwell/geoip
FILE="$DIR/dbip-city-lite.mmdb"

echo "Fetching DB-IP City Lite $MONTH onto $HOST ..."
ssh "$HOST" "set -euo pipefail
  mkdir -p '$DIR'
  curl -fsSL '$URL' | gunzip > '$FILE.tmp'
  mv '$FILE.tmp' '$FILE'
  chown 1000:1000 '$DIR' '$FILE'
  chmod 750 '$DIR'; chmod 640 '$FILE'
  ls -la '$FILE'"

echo
echo "Done. Restart the app so the initializer picks it up:  kamal app boot"
echo "First time? Backfill history after the restart:        kamal app exec 'bin/rails geoip:backfill'"
