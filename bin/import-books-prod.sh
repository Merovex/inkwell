#!/usr/bin/env bash
# One-off: import the Jekyll _books into the production Inkwell app.
# Stages the source (books + authors + series data + cover images) into the
# running web container, dry-runs, confirms, then runs the real import.
#
#   bin/import-books-prod.sh
set -euo pipefail

# ---- config (adjust if these change) ----------------------------------------
SERVER="root@5.161.252.146"
SITE="/home/bwilson/Work/merovex.press"       # the Jekyll site root (holds _books, _authors, _data, assets)
NAME="inkwell-web"                             # container name fragment
REMOTE_STAGE="/tmp/import"                      # scratch dir on the server
CONTAINER_STAGE="/rails/tmp/import"             # where the task reads from (parent of _books)
# -----------------------------------------------------------------------------

echo "==> Resolving the running $NAME container"
CID=$(ssh "$SERVER" "docker ps -qf name=$NAME | head -1")
[ -n "$CID" ] || { echo "No running $NAME container found." >&2; exit 1; }
echo "    container: $CID"

echo "==> Staging source on the server ($REMOTE_STAGE)"
ssh "$SERVER" "rm -rf $REMOTE_STAGE && mkdir -p $REMOTE_STAGE/assets/images"
scp -rq "$SITE/_books" "$SITE/_authors" "$SITE/_data" "$SERVER:$REMOTE_STAGE/"
scp -rq "$SITE/assets/images/books" "$SERVER:$REMOTE_STAGE/assets/images/"

echo "==> Copying into the container ($CONTAINER_STAGE)"
ssh "$SERVER" "docker exec $CID rm -rf $CONTAINER_STAGE"
ssh "$SERVER" "docker cp $REMOTE_STAGE $CID:$CONTAINER_STAGE"

echo "==> Verifying layout"
ssh "$SERVER" "docker exec $CID ls $CONTAINER_STAGE"
echo "    covers:"
ssh "$SERVER" "docker exec $CID ls $CONTAINER_STAGE/assets/images/books"

echo "==> DRY RUN"
ssh "$SERVER" "docker exec -e DRY_RUN=1 $CID bin/rails 'blog:import_books[$CONTAINER_STAGE/_books]'"

echo
read -r -p "Review the dry run above. Run the REAL import now? (type yes) " ans
if [ "$ans" != "yes" ]; then
  echo "Aborted — nothing imported. Staged files left in the container for a retry."
  exit 0
fi

echo "==> REAL IMPORT"
ssh "$SERVER" "docker exec $CID bin/rails 'blog:import_books[$CONTAINER_STAGE/_books]'"

echo "==> Post-import counts"
ssh "$SERVER" "docker exec $CID bin/rails runner 'puts %(Books: #{Book.current.count}   Series: #{Series.current.count}   Distributors: #{Distributor.count})'"

echo "==> Cleaning up staging"
ssh "$SERVER" "rm -rf $REMOTE_STAGE; docker exec $CID rm -rf $CONTAINER_STAGE"
echo "Done. Spot-check a book with its cover on the live site."
