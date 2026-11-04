# Base images

The image workflow builds these two Linux amd64 + arm64 images:

| Image | Contents |
| --- | --- |
| `ghcr.io/rubio-enterprises/devcontainers/base:latest` | Digest-pinned Microsoft Trixie base with the existing baseline Feature |
| `ghcr.io/rubio-enterprises/devcontainers/base-ci:latest` | The exact base above, plus Actions runner 2.337.0, gh, jq and writable runner/mise cache paths |

These are image identities, not a change to the historical Feature or collection
namespace `ghcr.io/rubio-enterprises/devcontainer-features`.
First publication and anonymous access/package association require a separate
owner checkpoint; source preparation alone does not establish availability.

## Runtime ownership after UID remapping

The Dev Container CLI re-owns the remote user's home when it changes that user's UID/GID,
not directories under `/usr/local/share`. The baseline Feature's `onCreateCommand` therefore
recursively reclaims both `MISE_SHIMS_DIR` and an existing `/usr/local/share/mise` before
repository lifecycle commands. The latter contains mutable preinstalled tools, including
Python site-packages written by setup. Writable shims alone do not establish readiness.

Matching ownership needs no sudo or recursive traversal. A missing system mise tree stays
absent, so the same Feature supports cold local builds. Repair uses non-interactive sudo and
fails if escalation is blocked; CI's fixed UID 1000 does not need repair. Recursive ownership
does not follow tool symlinks outside these trees. Feature tests cover nested writes with
already-writable shims, a sudo-free repeat and blocked escalation, complementing repository
image checks at UID 1000 and 1001.

## Build and validation

`images/base/devcontainer.json` uses the existing baseline Feature installer;
there is no second mise installer. Its workspace is an empty temporary directory,
not the repository checkout. `images/base-ci/Dockerfile` has an empty build
context and uses `COPY --link` to add the digest-pinned runner under
`/opt/actions-runner`, preserving the base's filesystem-layer prefix.

`.github/workflows/base-images.yml` uses the declared Docker x64 and ARM routes
with their existing hosted fallbacks. Each architecture must match its actual
Docker daemon and image configuration; no QEMU emulation qualifies. Both images
are run as UID 1000 with no network and no-new-privileges. Smoke tests verify
runner version, gh/jq/mise, the mise-action-compatible
`$MISE_DATA_DIR/bin/mise` link, writable shims/cache and failed sudo escalation.

Every layer is inspected for standards/repository checkouts and credential
files, retaining the two known Oh My Zsh checkout configurations shipped by the
Microsoft base (root and vscode); these are not organization source. The
layer-inspector regression covers both allowed paths and unrelated rejected
Git checkouts. Checksum-pinned Trivy scans both images and their configuration for
secrets, reporting identifiers and locations, never matched values. The images
contain no standards checkout, provisioning pin or credentials. They do not
fetch standards at runtime.

## CI image release check

A repository image's CI variant is its repository layers rebased onto base-ci, and
`.github`'s rebase verification proves those layers and the runtime configuration
identical to the dev image's. So per-build checks of the CI image only retest what
base-ci adds, and they no longer run per build. Each native `build` job runs
`test/base-image-ci-reference.sh` instead, once per base pair release:

- It builds a reference repository layer over base-ci
  (`test/base-image-ci-reference.Dockerfile`). Its `ENV` and cache directories mirror the
  `environment` stage of the Standards Package image recipe, and the same stage in
  `Rubio-Enterprises/.github` `tests/fixtures/frozen-repository-image-v2.Dockerfile`; keep them in step.
- It runs the runner-payload runtime check as UID 1000 with no network, no-new-privileges, 1 GiB
  and 512 processes: runner, mise, gh and jq run; `UV_LINK_MODE=copy`; the mise, devcontainer cache and
  runner directories are writable; no sudo; no provisioning pin or token in the environment.
- It runs the CI image's cache check for UID 1000: `cache-smoke.sh` seeds nested cache and SDK-home
  metadata as vscode and checks append, create, rename and delete. The script is
  `.github`'s `actions/repository-image/cache-smoke.sh`, checked out at the ref pinned in the workflow and
  shared with the per-build dev image checks (UID 1000 and 1001). Move the ref when that file changes.
- Two fault controls build the same layer with a root-owned runner directory and a root-owned uv
  cache. Each check must fail on its fault, so a check that can no longer fail fails the job.

The job fails the release before assembly and publication if any check fails. CI / UID 1001 stays
omitted: Container Pool runners use UID 1000 and dev images test the migration.

## Digest pairing for rebase

Each native job resolves its base **platform manifest digest** in an ephemeral
local registry and uses that immutable digest in base-ci's `FROM`, not a moving
tag. After both native jobs pass, a read-only assembly job constructs the base
**multiarch index** and stamps these standard OCI image-config labels on each
base-ci platform image with pinned crane's metadata-only mutation:

- `org.opencontainers.image.base.name`:
  `ghcr.io/rubio-enterprises/devcontainers/base:latest`
- `org.opencontainers.image.base.digest`: the exact **base multiarch index**
  digest, `sha256:<64 lowercase hex>`, identical on both base-ci architectures.

The labels live in OCI config `config.Labels`, not manifest annotations. This
matches `.github/actions/repository-image/image.mjs` at
`65f11ddf3b57a2dc4950db4c62cfb0d7ca28a724`: its exported `validatePair`
function is exercised against both assembled architectures. A platform child
digest is deliberately rejected. Base/CI index platform membership is checked;
compressed layers, rootfs diff IDs and runtime configuration stay identical to
the native-smoked, secret-scanned inputs except the one digest label. The
assembly step introduces no filesystem layer or arbitrary configuration value.

Consumers compare the resolved base **index** digest to each base-ci config
label and validate the same-platform layer prefixes before `crane rebase`.
Rebase preserves the repository image's configuration: base-ci's USER/ENV/labels
do not automatically replace it.

OCI layouts preserve the exact manifests and compressed layer blobs across
architecture, assembly and publication jobs. Both final index layouts pass a
job-local push/pull digest roundtrip before export. The publishing job verifies
each pushed **index** digest before moving latest. Do not replace this transport
with Docker save/load, which need not preserve compressed manifest identities.
Use crane's default push of the layout's single index descriptor, not `--index`
(which would publish the outer layout index instead).

## Publication boundary

Pull requests only build, smoke, inspect and scan; they have no package-write
permission or registry login. No standards-reader credential is needed. On a
reviewed default-branch push (or manually authorized default-branch dispatch),
a separate package-write job publishes only after **both** native jobs and the
read-only pairing assembly pass. It publishes commit-scoped `sha-<commit>`
index references, then
advances `latest` for each image. Registry tag updates are not transactional:
consumers must enforce the pairing labels while resolving moving tags.

The OCI source label follows the actual source repository, including an eventual
identity-preserving rename. Public package visibility and package association
must be verified after the first owner-authorized publication; this workflow
does not mutate package visibility, repository settings or runner configuration.
