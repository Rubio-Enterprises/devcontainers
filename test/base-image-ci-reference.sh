#!/usr/bin/env bash
# Checks base-ci as a repository image's CI variant runs it: the runner-payload runtime check and the CI image's UID 1000
# cache check. A repository image is built on `base`, rebased onto `base-ci` and then verified to keep its repository layers,
# so per-image checks cannot see anything `base-ci` adds. They run here instead, once per base pair release.
#
# Usage: base-image-ci-reference.sh <base-ci image> <native architecture> <cache-smoke.sh>
# cache-smoke.sh is Rubio-Enterprises/.github's actions/repository-image/cache-smoke.sh, shared with the per-build dev checks.
set -euo pipefail

ci=${1:?base-ci image reference required}
arch=${2:?native architecture required}
cache_smoke=${3:?cache-smoke.sh path required}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test -s "$cache_smoke"
tmp=$(mktemp -d)
tags=()
cleanup() {
  if ((${#tags[@]})); then docker image rm "${tags[@]}" >/dev/null 2>&1 || true; fi
  rm -rf "$tmp"
}
trap cleanup EXIT

# The reference layer's build context is empty and its steps need no network. Sets `built` (not printed: a subshell would
# lose the tag the cleanup removes).
build_reference() {
  built=base-ci-reference:$$-${1:-ok}
  docker build --network none --platform "linux/$arch" --provenance=false --sbom=false \
    --build-arg "BASE=$ci" --build-arg "BREAK=$1" \
    -f "$root/test/base-image-ci-reference.Dockerfile" -t "$built" "$tmp" >&2
  tags+=("$built")
}

# The runner-payload and environment checks the Build Service used to run on every CI image, as the runner's identity
runtime() {
  docker run --rm --network none --security-opt no-new-privileges --user 1000 \
    --memory 1g --pids-limit 512 --entrypoint bash "$1" -euc '
      workspace="$PWD"
      cd /
      /opt/actions-runner/bin/Runner.Listener --version
      mise --version
      /usr/bin/gh --version
      /usr/bin/jq --version
      test "$UV_LINK_MODE" = copy
      test -w /usr/local/share/mise
      test -w /var/cache/devcontainer
      test -w /opt/actions-runner
      test "$(id -u)" = 1000
      if sudo -n true 2>/dev/null; then exit 1; fi
      test -z "${STANDARDS_PIN:-}"
      test -z "${NODE_AUTH_TOKEN:-}"
      test -z "${STANDARDS_VERSION:-}"
      test ! -e "$workspace/.standards/node_modules"
    '
}

# Fixed runner identity (UID 1000) on the merged base-ci filesystem; dev images keep their own UID 1000 and 1001 checks
cache() {
  docker run --rm -i --network none --security-opt no-new-privileges --user root \
    --memory 1g --pids-limit 512 --entrypoint bash "$1" -s -- 1000 <"$cache_smoke"
}

build_reference ""
runtime "$built"
cache "$built"

# A check that cannot fail proves nothing: each fault must be caught by the check meant to catch it
build_reference root-owned-runner
if runtime "$built" >"$tmp/fault.log" 2>&1; then
  echo "Runtime check passed on an image whose runner directory is root-owned" >&2
  exit 1
fi
build_reference root-owned-cache
if cache "$built" >"$tmp/fault.log" 2>&1; then
  echo "Cache check passed on an image whose uv cache is root-owned" >&2
  exit 1
fi
printf 'PASS: linux/%s CI image runtime and UID 1000 cache checks, and both fault controls\n' "$arch"
