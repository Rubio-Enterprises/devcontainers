#!/bin/sh
# The CLI remaps only the home directory, but mise --system installs mutable
# tools outside it. Repair both trees before repository lifecycle commands.
set -eu
uid="$(id -u)"
owner="$uid:$(id -g)"
for dir in "${MISE_SHIMS_DIR:?MISE_SHIMS_DIR is not set}" /usr/local/share/mise; do
  [ -d "$dir" ] || continue
  [ "$(stat -c '%u' "$dir")" = "$uid" ] && continue
  sudo -n chown -R "$owner" "$dir"
done
