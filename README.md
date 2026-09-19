# Setup Aspect Buildkite plugin

A [Buildkite plugin](https://buildkite.com/docs/plugins) that sets a step up so
that **raw `bazel <verb>` calls** — not just `aspect <task>` — reach an Aspect
cache.

This is the Buildkite counterpart of the
[`aspect-build/setup-aspect`](https://github.com/aspect-build/setup-aspect)
GitHub Action.

The plugin runs in the **`pre-command` hook** — after the repository checkout
(so the rc generator can read the workspace's `.bazelversion`) and before the
step's command (so the rc is in place before any `bazel` call).

## Two modes

The setup looks at `ASPECT_WORKFLOWS_RUNNER` and takes one of two paths.

### On any Buildkite agent — the Aspect remote cache

This is the path that lets an existing pipeline try Aspect without moving to
Aspect Workflows runners. It:

1. **Installs the Aspect CLI launcher and Bazelisk**, each skipped when the
   binary is already on `PATH`. The launcher reads `.aspect/version.axl` from
   your repository and fetches the matching CLI on first use, so the CLI version
   stays pinned by the repo; `ASPECT_LAUNCHER_VERSION` pins only the launcher.
2. **Authenticates** with `aspect auth login --with-api-token` when
   `ASPECT_API_TOKEN` is set. The token is piped on stdin — never an argument —
   and the short-lived JWT the CLI persists is what later `aspect` calls and the
   Bazel credential helper use.
3. **Writes `~/.bazelrc`** with `aspect setup bazelrc --home`, pointing vanilla
   `bazel` at the Aspect deployment's remote cache and BES. A plain
   `bazel build //...` then shares a cache with every other job and branch and
   streams the build to Aspect; `aspect build --remote //...` reaches the same
   deployment.

`--home` is what keeps the rc out of the checkout. Without it the task writes
`<workspace>/.aspect/bazelrc` and a `try-import` in the workspace `.bazelrc` —
files meant to be committed, not generated on a runner and thrown away with it.

### On an Aspect Workflows runner — the runner's own caches

`aspect <task>` already wires itself into the runner's remote cache, BES
backend, and local NVMe disk cache. Steps that call `bazel` directly would otherwise miss all of
that, so the setup:

1. **Logs the runner's metadata** for traceability.
2. **Waits for cache warming to complete.** `aspect <task>` performs this wait
   itself; a vanilla `bazel` call would otherwise race the still-running
   bootstrap warming — competing for CPU/disk and missing the warmed caches.
3. **Authenticates**, as above.
4. **Generates the runner's Bazel rc** via `aspect setup bazelrc`, with a legacy
   fallback for runners whose CLI predates that task. If neither is available it
   warns but **does not fail the build** — warming is done and `aspect <task>`
   steps are unaffected.

## Authentication

Set `ASPECT_API_TOKEN` to a long-lived `<CLIENT_ID>:<SECRET>` Aspect API token,
from a Buildkite secret or an agent environment hook — not from pipeline YAML. Without it the rc is still written — the task defaults to the
Aspect Cloud deployment and needs no login — but Bazel will reach that cache
unauthenticated.


## Usage

Add the plugin to any step that runs `bazel` directly:

```yaml
steps:
  - command: bazel test //...
    plugins:
      - aspect-build/setup-aspect#19a9eb187ad1f1c65c1b6d64a7fc03589041c8ae: ~ # v2026.25.0
```

`aspect <task>` steps don't need the plugin (they self-configure), but it's
harmless to apply it pipeline-wide.

### Pin to a commit SHA

**Pin to a full-length commit SHA**, not a branch or tag — tags are mutable and
can be repointed at malicious code, so SHA-pinning is the recommended way to
consume third-party plugins. Annotate with the version in a trailing comment for
readability and let Renovate keep the SHA fresh:

```yaml
plugins:
  - aspect-build/setup-aspect#19a9eb187ad1f1c65c1b6d64a7fc03589041c8ae: ~ # v2026.25.0
```

Find the latest SHA on the [Releases page](https://github.com/aspect-build/setup-aspect-buildkite-plugin/releases).

## Requirements

- An Aspect Workflows Buildkite runner (sets `ASPECT_WORKFLOWS_RUNNER`). On any
  other agent the plugin no-ops.
- `bash` on the agent. `aspect`, `bazel`, and `rosetta` are provided by the
  Workflows runner image.

## Configuration

None. The plugin's behavior is driven entirely by the runner's
`ASPECT_WORKFLOWS_RUNNER_*` environment variables.

## Degraded-configuration signal

If the Aspect CLI has no bazelrc task under either name (older than
`v2026.26.44`, before the task existed at all) the plugin falls back to the
legacy `rosetta bazelrc`. If neither is available, the plugin cannot configure
vanilla `bazel` calls: it emits a warning — but it does not fail the build. If
you see this, upgrade the Aspect CLI on the runner image to `v2026.38.10` or
newer: https://github.com/aspect-build/aspect-cli/releases.

`rosetta` is the legacy generator that a future major Aspect Workflows release
will remove; once it is gone, `aspect setup bazelrc` is the only path.

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md). In short:

```sh
docker-compose run --rm tests   # BATS suite via buildkite/plugin-tester
```

CI ([.buildkite/pipeline.yml](.buildkite/pipeline.yml)) runs the tests, the
plugin linter, and shellcheck.

## License

Apache-2.0. See [LICENSE](LICENSE).
