#!/usr/bin/env bash
# Export an account's Hugo JSON transport from production and download the
# archive for local inspection (docs/hugo-build-pipeline.md §4).
#
#   bin/export-site-prod.sh [account_id]
#
# Prompts for the account id when not given. The tarball lands in the current
# directory. Requires the /var/cache/inkwell/builds mount on the server
# (bin/provision-storage.sh) and a deploy carrying BUILDS_PATH.
set -euo pipefail

# ---- config (adjust if these change) ----------------------------------------
SERVER="root@5.161.252.146"
HOST_BUILDS="/var/cache/inkwell/builds"        # bind mount on the server ...
CONTAINER_BUILDS="/rails/builds"               # ... as the container sees it
# -----------------------------------------------------------------------------

ACCOUNT_ID="${1:-}"
if [[ -z "$ACCOUNT_ID" ]]; then
  read -rp "Account id: " ACCOUNT_ID
fi
[[ "$ACCOUNT_ID" =~ ^[0-9]+$ ]] || { echo "Account id must be a number." >&2; exit 1; }

echo "==> Exporting account $ACCOUNT_ID"
OUTPUT=$(bin/kamal app exec --reuse "bin/rails 'site:export[$ACCOUNT_ID]'")
echo "$OUTPUT"

# The task prints "Archive: <container path>"; kamal may prefix its own noise.
ARCHIVE=$(echo "$OUTPUT" | sed -n 's/.*Archive: //p' | tail -1 | tr -d '\r')
[[ -n "$ARCHIVE" ]] || { echo "No archive path in the task output." >&2; exit 1; }

HOST_ARCHIVE="${ARCHIVE/#$CONTAINER_BUILDS/$HOST_BUILDS}"
echo "==> Downloading $SERVER:$HOST_ARCHIVE"
scp "$SERVER:$HOST_ARCHIVE" .

echo "==> Saved $(basename "$HOST_ARCHIVE")"
