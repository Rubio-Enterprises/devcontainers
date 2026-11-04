#!/bin/bash
set -euo pipefail

claim=/usr/local/share/rubio-baseline/claim-mise-shims
system=/usr/local/share/mise
fixture="$system/installs/baseline-ownership/0.0.0"
scratch=$(mktemp -d)
trap 'rm -rf "$fixture" "$scratch"' EXIT
as_vscode() { runuser -u vscode -- env MISE_SHIMS_DIR="$MISE_SHIMS_DIR" "$@"; }

chown vscode:vscode "$MISE_SHIMS_DIR"
if [ ! -d "$system" ]; then
  as_vscode "$claim"
  test ! -e "$system"
fi

mkdir -p "$fixture/lib/site-packages" "$scratch/bin"
printf 'seed\n' >"$fixture/lib/site-packages/seed"
ln -s "$scratch/external" "$fixture/external"
printf 'external\n' >"$scratch/external"
chown -R 54321:54321 "$fixture"
chown 54321:54321 "$system"

if grep -q '^NoNewPrivs:[[:space:]]*1' /proc/self/status; then
  if as_vscode "$claim"; then
    echo 'ownership repair silently succeeded with sudo blocked' >&2
    exit 1
  fi
  exit 0
fi

as_vscode "$claim"
# shellcheck disable=SC2016
as_vscode sh -ec '
  dir=$1
  printf "append\n" >>"$dir/seed"
  mkdir "$dir/new"
  mv "$dir/seed" "$dir/new/renamed"
  rm "$dir/new/renamed"
  rmdir "$dir/new"
' sh "$fixture/lib/site-packages"
test "$(stat -c '%u:%g' "$fixture/lib/site-packages")" = "$(id -u vscode):$(id -g vscode)"
test "$(stat -c '%u:%g' "$scratch/external")" = '0:0'

chmod 755 "$scratch" "$scratch/bin"
printf '#!/bin/sh\nexit 99\n' >"$scratch/bin/sudo"
chmod 755 "$scratch/bin/sudo"
as_vscode env PATH="$scratch/bin:/usr/bin:/bin" "$claim"
printf 'mise ownership: nested writes, symlink isolation and sudo-free repeat passed\n'
