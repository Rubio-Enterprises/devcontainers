#!/bin/bash
set -e

# Runs against the auto-generated devcontainer.json that includes the
# 'baseline' feature with no options, as root (--remote-user root): the
# safe.directory checks create repositories owned by another user. See
# https://github.com/devcontainers/cli/blob/main/docs/features/test.md
# The Dev Container CLI puts this library on PATH inside the test container.
# shellcheck source=/dev/null
source dev-container-features-test-lib

check "mise is installed" mise --version
mise_is_at_least() {
  local version
  version="$(mise --version | awk '{print $1}')"
  [[ "$(printf '%s\n' "$1" "$version" | sort -V | head -n 1)" == "$1" ]]
}
check "mise is at least 2026.9.14 (API-free release metadata)" mise_is_at_least 2026.9.14
check "mise is at least 2026.10.19 (standards native config min_version)" mise_is_at_least 2026.10.19
check "mise uses the versions mirror" test "$(mise settings get use_versions_host)" = true
check "gh is not installed" bash -c '! command -v gh'
check "dotfiles install selects the personal profile" test "$DOTFILES_PROFILE" = personal

# git refuses repositories owned by another user unless safe.directory lists
# them. Bind-mounted checkouts can report a foreign owner, so the feature marks
# everything under /workspaces safe, and nothing else.
make_foreign_repo() {
  mkdir -p "$1" && git init -q "$1" && chown -R 12345:12345 "$1"
}
make_foreign_repo /workspaces/foreign-owner
make_foreign_repo /tmp/foreign-owner
check "git trusts a foreign-owned repo under /workspaces" git -C /workspaces/foreign-owner rev-parse --git-dir
check "git still refuses a foreign-owned repo elsewhere" bash -c '! git -C /tmp/foreign-owner rev-parse --git-dir'

# A tool that passes its own GIT_CONFIG_COUNT settings to git must not drop
# the trust: GIT_CONFIG_COUNT replaces earlier GIT_CONFIG_* pairs.
check "a tool's own GIT_CONFIG_COUNT keeps /workspaces trusted" \
  env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=tool \
  git -C /workspaces/foreign-owner rev-parse --git-dir

# A tool from mise configuration runs by name, with no `mise activate` or
# `mise exec --`: plain `docker exec`, lifecycle commands, and tasks see only
# the container environment. A linked fake keeps the check offline; the base
# image ships no node.
mkdir -p /tmp/fake-node/bin
printf '#!/bin/sh\necho fake-node\n' >/tmp/fake-node/bin/node
chmod +x /tmp/fake-node/bin/node
mise link node@0.0.0-baseline /tmp/fake-node
mise use --global node@0.0.0-baseline
check "a mise tool runs by name without activation" test "$(cd /tmp && node)" = fake-node
# Debian's /etc/profile resets PATH; the base image restores it for login shells.
check "a login shell keeps the shims on PATH" test "$(cd /tmp && bash -lc node)" = fake-node

# A Linux UID remap re-owns only the home directory, leaving the shims
# directory owned by the old UID. The onCreateCommand helper, run as the
# remote user, takes it back with sudo so that user's `mise install` can write
# shims. Engines that start containers with no-new-privileges (Colima's
# default) block sudo; there the helper must fail rather than leave a
# directory `mise install` cannot write.
claim=/usr/local/share/rubio-baseline/claim-mise-shims
as_vscode() { runuser -u vscode -- env MISE_SHIMS_DIR="$MISE_SHIMS_DIR" "$@"; }
chown 54321:54321 "$MISE_SHIMS_DIR"
if grep -q '^NoNewPrivs:[[:space:]]*1' /proc/self/status; then
  check "the helper fails when sudo is blocked" bash -c "! runuser -u vscode -- env MISE_SHIMS_DIR='$MISE_SHIMS_DIR' '$claim'"
  chown vscode "$MISE_SHIMS_DIR"
else
  check "the helper reclaims a shims directory left to an old UID" as_vscode "$claim"
  check "the remote user can write shims again" as_vscode test -w "$MISE_SHIMS_DIR"
fi
check "the helper does nothing once the owner UID matches" as_vscode "$claim"
check "system mise installs survive a UID remap even with writable shims" \
  bash "$(dirname "${BASH_SOURCE[0]}")/mise-ownership.sh"

# The generated test container is disposable and runs as root. Block the API
# before testing real release resolution/downloads, with separate empty caches.
printf '\n127.0.0.1 api.github.com\n' >>/etc/hosts
check "fresh GitHub/aqua tools install without GitHub API calls" \
  bash "$(dirname "${BASH_SOURCE[0]}")/no-github-api.sh"

reportResults
