# Agent context

This repo follows the Rubio-Enterprises standards from `@rubio-enterprises/standards`: run `mise run setup` once per clone, and `mise run check` before committing (`mise run fmt` applies the Fixers). Feature tests run in `test.yaml`.

Repo-specific context (in-progress migrations, gotchas, agent guidance):

The `Rubio-Enterprises/devcontainers` source repository publishes Features to
`ghcr.io/rubio-enterprises/devcontainer-features/<id>` and public base/base-ci
images under `ghcr.io/rubio-enterprises/devcontainers/`. Keep the existing Feature
and collection package namespace independent of the source repository name.
See `docs/base-images.md` for image build/publication work. `baseline` is the org
Dev Container baseline. See `README.md` for what it
provides, how to test it, and how releases work.

- Keep the repository public: clients pull features from GHCR without
  registry credentials.
- Any change under `src/<feature>/` bumps that feature's `version` in the same
  pull request; merging publishes it. Removing an option or environment
  variable is a major bump.
- Feature tests need a Docker daemon (`devcontainer features test`).
