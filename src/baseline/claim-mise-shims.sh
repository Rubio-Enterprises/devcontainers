#!/bin/sh
# The CLI remaps only the home directory, but mise --system installs mutable
# tools outside it. Repair both trees before repository lifecycle commands.
set -eu
owner="$(id -u):$(id -g)"
for dir in "${MISE_SHIMS_DIR:?MISE_SHIMS_DIR is not set}" /usr/local/share/mise; do
  [ -d "$dir" ] || continue
  [ "$(stat -c '%u:%g' "$dir")" = "$owner" ] && continue
  sudo -n chown -R "$owner" "$dir"
done
