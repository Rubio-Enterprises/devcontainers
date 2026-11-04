#!/bin/sh
set -eu

install_mise() (
  # Renovate updates this pin and patch-bumps the feature version together.
  # renovate: datasource=github-releases depName=jdx/mise
  MISE_VERSION=2026.10.19
  case "$(dpkg --print-architecture)" in
  arm64) arch=arm64 ;;
  amd64) arch=x64 ;;
  *)
    echo "baseline: unsupported mise architecture" >&2
    exit 1
    ;;
  esac

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl minisign
  rm -rf /var/lib/apt/lists/*

  tmp="$(mktemp -d)"
  # Invoked indirectly by the EXIT trap.
  # shellcheck disable=SC2329
  cleanup_mise() {
    status=$?
    rm -rf "$tmp"
    if [ "$status" -ne 0 ]; then
      echo "baseline: mise download/signature/checksum/install failed" >&2
    fi
    exit "$status"
  }
  trap cleanup_mise EXIT
  trap 'exit 1' HUP INT TERM
  cd "$tmp"
  asset="mise-v${MISE_VERSION}-linux-${arch}.tar.gz"
  base="https://github.com/jdx/mise/releases/download/v${MISE_VERSION}"
  for file in SHASUMS256.txt SHASUMS256.txt.minisig "$asset"; do
    curl --fail --show-error --silent --location --retry 3 \
      --proto '=https' --proto-redir '=https' --output "$file" "$base/$file"
  done

  # Pinned upstream key: https://mise.jdx.dev/installing-mise.html#github-releases
  # https://github.com/jdx/mise/blob/main/minisign.pub
  # Never fetch a key alongside the artifacts it is meant to authenticate.
  minisign -Vm SHASUMS256.txt -P RWTC3g8W3z4RZK3V3qv7fa1QY4JEWyBtqIHW+85QlJpZc5yG+uNYNBSZ
  # Require exactly one signed entry for this asset; no per-version hashes.
  awk -v asset="./$asset" '$2 == asset { print; count++ } END { if (count != 1) exit 1 }' \
    SHASUMS256.txt >checksum
  sha256sum --check checksum
  # Extract only the verified executable, not arbitrary archive paths.
  tar -xzf "$asset" mise/bin/mise
  install -m 0755 mise/bin/mise /usr/local/bin/mise
  /usr/local/bin/mise --version
)

install_mise

# containerEnv sets the environment. MISE_SHIMS_DIR moves mise's shims out of
# the user's home, so the static PATH entry finds them for any remote user.
# The remote user's `mise install` writes shims there, so that user owns it.
mkdir -p "$MISE_SHIMS_DIR"
chown "$_REMOTE_USER" "$MISE_SHIMS_DIR"

# The CLI remaps only the home directory after installation. onCreateCommand
# must reclaim the shims and any system mise tree before repository setup.
install -D -m 0755 "$(dirname "$0")/claim-mise-shims.sh" /usr/local/share/rubio-baseline/claim-mise-shims

# git refuses repositories owned by another user unless safe.directory lists
# them, and bind-mounted checkouts can report a foreign owner. System scope is
# protected configuration, so git honors it there, and safe.directory is
# multi-valued, so other entries in /etc/gitconfig add to this one.
if ! git config --system --get-all safe.directory | grep -qxF '/workspaces/*'; then
  git config --system --add safe.directory '/workspaces/*'
fi
