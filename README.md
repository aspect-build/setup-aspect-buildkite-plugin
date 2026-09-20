# Setup Aspect Buildkite plugin

A [Buildkite plugin](https://buildkite.com/docs/plugins) that installs the
[Aspect CLI](https://docs.aspect.build/cli/overview) launcher, installs
Bazelisk (skipped automatically if `bazel` is already on PATH), points Bazel at
Aspect Cloud's remote cache and BES, and authenticates with the Aspect API —
all in one step.

Both the remote cache and the web UI that the BES stream powers are available on
Aspect Cloud's Free Tier. See [aspect.build/docs](https://aspect.build/docs) for
more info.

This is the Buildkite counterpart of the
[`aspect-build/setup-aspect`](https://github.com/aspect-build/setup-aspect)
GitHub Action.

The plugin runs in the **`pre-command` hook** — after the repository checkout
(the launcher resolves the repo's pinned CLI version from the workspace, and the
legacy generator reads its `.bazelversion`) and before the step's command (so
`~/.aspect/bazelrc` is in place before any `bazel` call).

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
3. **Runs `aspect setup bazelrc`**, which on CI writes `~/.aspect/bazelrc` and
   a `try-import` for it in `~/.bazelrc`, pointing vanilla `bazel` at the Aspect
   deployment's remote cache and BES. A plain `bazel build //...` then shares a
   cache with every other job and branch and streams the build to Aspect;
   `aspect <task>` reaches the same deployment with no flag of its own: on CI it
   wires the default deployment itself, rc or no rc.

The command is passed no flags: the CLI detects CI and picks that home layout
itself, over the `<workspace>/.aspect/bazelrc` pair it writes off CI — files
meant to be committed, not generated on an agent and thrown away with it. The
settings below override the detection when a pipeline asks.

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
from a Buildkite secret or an agent environment hook — not from pipeline YAML. Without it `~/.aspect/bazelrc` is still written — the task defaults to the
Aspect Cloud deployment and needs no login — but Bazel will reach that cache
unauthenticated.


## Usage

Add the plugin to any step that builds:

```yaml
steps:
  - command:
      - bazel build //...
      - bazel test //...
    plugins:
      - aspect-build/setup-aspect#19a9eb187ad1f1c65c1b6d64a7fc03589041c8ae: ~ # v2026.25.0
```

### Running Aspect tasks instead

`aspect <task>` commands — `aspect build`, `aspect test`, `aspect lint` and the
rest — run the same builds with Aspect's own reporting, and reach the
deployment on CI without a flag of their own:

```yaml
steps:
  - command:
      - aspect build //...
      - aspect test //...
    plugins:
      - aspect-build/setup-aspect#19a9eb187ad1f1c65c1b6d64a7fc03589041c8ae: ~ # v2026.25.0
```

A task configures its own Bazel invocation, so it needs neither the generated
rc nor `--remote` here; what it does need is `aspect` on `PATH`, which this
plugin installs. See [Aspect CLI tasks](https://aspect.build/docs/cli/tasks).

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

- `bash` and `curl` on a Linux or macOS agent, x86_64 or arm64.
- On a stock agent: nothing else. `aspect` and `bazel` are installed when they
  are missing, and `ASPECT_API_TOKEN` is what authenticates the cache.
- On an Aspect Workflows runner (which sets `ASPECT_WORKFLOWS_RUNNER`):
  `aspect`, `bazel` and `rosetta` come from the runner image, and a repo whose
  CLI predates `aspect setup bazelrc` falls back to `rosetta bazelrc`, which
  resolves the Bazel version from a committed `.bazelversion` and has no
  fallback.

## Configuration

Which branch runs, and the credentials it uses, come from the environment:
`ASPECT_WORKFLOWS_RUNNER_*` picks the branch, `ASPECT_API_TOKEN` authenticates,
`ASPECT_LAUNCHER_VERSION` pins the launcher. Secrets do not belong in pipeline
YAML, so the token is not an option here.

The rc task's own flags are options, all unset by default. Unset is not a
default value: leaving a flag off is what lets the CLI apply its own `auto`,
which already detects the runner and the CI host.

| Option | Passes | |
|---|---|---|
| `bazelrc-generate` | — | Whether to write `~/.aspect/bazelrc`, and the `try-import` for it in `~/.bazelrc`, via `aspect setup bazelrc`. On by default — that file is what makes a plain `bazel build //...` share a cache across jobs and stream to Aspect. `false` leaves Bazel's configuration to the repository, on a Workflows runner too; the installs and the login still happen, and `aspect <task>` steps are unaffected either way |
| `bazelrc-remote` | `--remote=<value>` | Which of the deployment's endpoints the generated `~/.aspect/bazelrc` turns on. Unset leaves the CLI's `auto` (cache + BES on CI, nothing off it). Same grammar as `aspect build --remote`: `exec` adds remote execution, `no-cache` / `no-bes` / `no-exec` subtract, `none` enables nothing |
| `bazelrc-home` | `--home=<value>` | Which rc to write. Unset leaves the CLI's `auto` (`~/.aspect/bazelrc` on CI, the checkout's off it). `false` writes the committed `<workspace>/.aspect/bazelrc` pair instead, for a step whose purpose is regenerating it |
| `bazelrc-force` | `--force` | Regenerate `~/.aspect/bazelrc` even if one is already there. Worth setting on a persistent self-hosted agent, whose home directory survives between jobs and would otherwise keep the file the first job wrote. An ephemeral agent starts clean, so this changes nothing there |

```yaml
steps:
  - command: bazel test //...
    plugins:
      - aspect-build/setup-aspect#v1:
          bazelrc-remote: exec
          bazelrc-force: true
```

Which Bazel flags the generated rc carries is a repository choice, not a plugin
one. To drop a flag the generated rc would otherwise set, name it in the repo's
`.aspect/config.axl`, where it covers every CI provider and local runs alike:

```python
def config(ctx: ConfigContext):
    ctx.tasks["setup/bazelrc"].args.omit_bazel_flags = [
        "--execution_log_compact_file",
    ]
```

Endpoints, credentials, and the runner's output paths cannot be omitted.

## Degraded-configuration signal

If the Aspect CLI has no bazelrc task under either name (older than
`v2026.26.44`, before the task existed at all) the plugin falls back to the
legacy `rosetta bazelrc`. If neither is available, the plugin cannot configure
vanilla `bazel` calls: it emits a warning — but it does not fail the build. If
you see this, upgrade the Aspect CLI on the runner image to `v2026.38.30` or
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
