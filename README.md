# devcontainers

Dev Container Features and public base images for Rubio-Enterprises repositories, published to GHCR.

The source repository is `Rubio-Enterprises/devcontainers`. Existing Features
and collection metadata keep their `ghcr.io/rubio-enterprises/devcontainer-features`
namespace; the source rename does not change consumer references or lockfiles.
Public base/base-ci images use `ghcr.io/rubio-enterprises/devcontainers/`
(see [base images](docs/base-images.md)).

## Table of Contents

- [Install](#install)
- [Usage](#usage)
- [Test](#test)
- [Release](#release)
- [Contributing](#contributing)
- [License](#license)

## Install

`ghcr.io/rubio-enterprises/devcontainer-features/baseline` is the shared setup
every Rubio-Enterprises Dev Container carries. A repository's
`.devcontainer/devcontainer.json` needs only the upstream base image and this
feature, pinned to an exact version:

```json
{
  "image": "mcr.microsoft.com/devcontainers/base:2.2.1-trixie",
  "features": {
    "ghcr.io/rubio-enterprises/devcontainer-features/baseline:3.0.1": {}
  }
}
```

## Usage

Rebuild the Dev Container after adding the feature. Inside the container, install
and use the repository's tools through mise:

```sh
mise trust
mise run setup   # standards package, pinned tools, git hooks
mise tasks
```

### baseline

It provides:

- **Pinned, signature-verified mise** (2026.10.19, the minimum for the
  standards native config model), installed into `/usr/local/bin` from GitHub
  release downloads for Linux arm64/x64. Debian's
  `minisign` verifies the checksum manifest against the pinned
  [upstream public key](https://mise.jdx.dev/installing-mise.html#github-releases),
  then SHA-256 verifies the tarball before extraction. Verification failures stop
  the build. No GitHub API calls, credentials, or `curl | sh` are needed.
  `MISE_USE_VERSIONS_HOST=true` keeps public GitHub release metadata on mise's
  versions mirror (requires mise >= 2026.9.14). Upstream can still fall back to
  the API on mirror misses; this is not an API firewall. The base image ships git,
  and each repository's mise configuration installs the rest of its tools.
  The GitHub CLI is no longer installed: run authenticated git/gh on the host.
- **mise's shims on `PATH`** for every process in the container: terminals,
  lifecycle commands, VS Code tasks, `devcontainer exec`, and a plain
  `docker exec`. A tool from the repository's mise configuration therefore runs
  by name, without `mise exec --` or `mise activate`. `MISE_SHIMS_DIR` moves the
  shims to `/usr/local/share/mise-shims`, owned by the remote user, so the
  static `PATH` entry does not depend on a home directory. On Linux hosts the
  Dev Container CLI can remap the remote user's UID and re-owns only the home
  directory; the feature's `onCreateCommand` then reclaims the shims directory
  with passwordless `sudo` before any repository lifecycle command runs. On an
  engine that starts containers with `no-new-privileges`, that repository must
  declare `"securityOpt": ["no-new-privileges=false"]` or the container fails
  to start; without a remap the helper never calls `sudo`. Shims apply a
  repository's mise `[env]` only to the tool they launch; use `mise run` or
  `mise exec --` where a command needs those variables.
- **`DOTFILES_PROFILE=personal`**, which the dotfiles installer reads to choose
  the personal profile. Only Rubio-Enterprises repositories use this feature, so
  every other repository falls back to the installer's work default.
- **git `safe.directory` for `/workspaces/*`**, added to `/etc/gitconfig`.
  Bind-mounted checkouts can report a foreign owner, and git then refuses to
  work in them. System scope is protected configuration, so git honors it
  there, and the entry survives tools that pass their own `GIT_CONFIG_COUNT`.
  The `/*` form needs git 2.46 or newer; the Trixie base image ships newer.

It does not install dotfiles. The Dev Container client does that: VS Code's
`dotfiles.repository` setting, which Settings Sync does not sync, or the
CLI's `--dotfiles-repository`. A dotfiles-installed `~/.local/bin/mise` can
shadow this feature's binary: it must also be >= 2026.10.19 for native config. Check
`command -v mise` and `mise --version` after personalization. Version 3 removes
the GitHub CLI, a breaking change for consumers that used it in-container.

## Test

```bash
devcontainer features test --features baseline \
  --base-image mcr.microsoft.com/devcontainers/base:2.2.1-trixie --skip-scenarios \
  --remote-user root .
```

The tests run as root because they create repositories owned by another user,
and they need a Docker daemon. CI runs them in `.github/workflows/test.yaml`.
They also block `api.github.com` in the disposable container and install
`github:sharkdp/fd`, `aqua:jqlang/jq`, and `aqua:BurntSushi/ripgrep` from empty
caches without credentials, rejecting API request URLs in mise's trace.
Use aqua for jq: the generic GitHub backend's default `v` tag prefix turns
`jq-1.8.2` into a nonexistent `vjq-1.8.2` and triggers API fallback.

For installer tampering checks, build a throwaway image with baseline and run
the additional script as root (replace `sol-baseline:verified` with that image):

```bash
docker --context colima-dev run --rm --name sol-baseline-tamper \
  --add-host api.github.com:127.0.0.1 \
  -v "$PWD/src/baseline:/tmp/baseline:ro" \
  -v "$PWD/test/baseline/verification-failures.sh:/tmp/verification-failures.sh:ro" \
  sol-baseline:verified bash /tmp/verification-failures.sh
```

This exercises the actual installer, rejecting corrupt signatures and tarballs
without replacing the existing mise executable.

## Release

The separate [base/base-ci image workflow](docs/base-images.md) reuses baseline
without changing Feature package identities. Its first publication remains
owner-gated.

Bump `version` in `src/<feature>/devcontainer-feature.json` in the same pull
request as the change. On merge, `.github/workflows/release.yaml` publishes
every feature whose version is not in GHCR yet, tagged `MAJOR`,
`MAJOR.MINOR`, `MAJOR.MINOR.PATCH`, and `latest`. Consumers pin the exact
version, and Renovate's devcontainer manager proposes updates.

The repo-local regex manager tracks the annotated `MISE_VERSION` pin in
`src/baseline/install.sh` using `github-releases` for `jdx/mise`, stripping the
tag's `v` prefix. A scoped
[Renovate `bumpVersions` rule](https://docs.renovatebot.com/configuration-options/#bumpversions)
patch-bumps baseline's feature version in the same PR, so merging publishes the
new binary. This generic mechanism is experimental; `bumpVersion` does not
support the regex manager. Review each mise PR for both edits; if the bot omits
the bump, manually increment `src/baseline/devcontainer-feature.json`'s patch
version before merge. The release workflow does not invent versions or commit
back to main. Breaking feature changes still require a reviewed major bump.

## Contributing

Organization changes go through pull requests following
[the org PR template](https://github.com/Rubio-Enterprises/.github/blob/main/.github/PULL_REQUEST_TEMPLATE.md):
a Conventional Commits title,
a linked work item, and What?, Why?, How? and Testing? sections. Use repository
issues for questions and include the template's feedback and dependency context
when relevant.

Run `mise trust && mise run setup` to install `@rubio-enterprises/standards` (export
`NODE_AUTH_TOKEN`, for example `"$(gh auth token)"`, first), the tools and the hooks. Run
`mise run check` for every Check, or `mise run fmt` to apply the Fixers. There is no
`mise run test` task (the Test Gate is opted out in `mise.toml`); use the feature test command
above with a Docker daemon.
For changes under `src/<feature>/`, bump that feature's version in the same PR;
removing an option or environment variable requires a major bump.

## License

[MIT](LICENSE) © 2026 Rubio Enterprises.
