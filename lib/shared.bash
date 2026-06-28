#!/bin/bash
#
# Shared helpers for the Aspect Workflows Buildkite plugin: logging and the
# runner-metadata table. Ported from the Workflows-runner branch of
# aspect-build/setup-aspect (index.js). Sourced by hooks/environment.

# Plain informational line on stdout. Callers wrap related output in Buildkite
# log groups with `echo "--- :aspect: ..."` / `echo "+++ ..."` directly.
log() {
  echo "$@"
}

# Warning line. Buildkite renders `~~~` / collapsed groups specially; a plain
# prefixed stderr line is the most portable way to surface a warning and is also
# easy to assert against in tests.
warn() {
  echo "⚠️  $*" >&2
}

# Render the `1`/unset boolean runner flags as yes/no, matching the Aspect CLI's
# own "Workflows runner metadata" block.
yesno() {
  [[ -n "$1" ]] && echo "yes" || echo "no"
}

# Runner-metadata rows: "<label>|<env var>|<formatter>". The formatter is
# optional and is one of: "" (verbatim), "upper", or "yesno". Ordering follows
# the Aspect CLI's metadata block (and setup-aspect's WORKFLOWS_METADATA_ROWS).
# Each row prints only when its env var is set — fields vary by cloud provider
# and runner version.
readonly WORKFLOWS_METADATA_ROWS=(
  "Workflows version|ASPECT_WORKFLOWS_RUNNER_VERSION|"
  "Cloud provider|ASPECT_WORKFLOWS_RUNNER_CLOUD_PROVIDER|upper"
  "Region|ASPECT_WORKFLOWS_RUNNER_REGION|"
  "Availability zone|ASPECT_WORKFLOWS_RUNNER_AZ|"
  "Cloud account|ASPECT_WORKFLOWS_RUNNER_CLOUD_ACCOUNT|"
  "Instance type|ASPECT_WORKFLOWS_RUNNER_INSTANCE_TYPE|"
  "Instance name|ASPECT_WORKFLOWS_RUNNER_INSTANCE_NAME|"
  "Instance ID|ASPECT_WORKFLOWS_RUNNER_INSTANCE_ID|"
  "Image ID|ASPECT_WORKFLOWS_RUNNER_IMAGE_ID|"
  "Group name|ASPECT_WORKFLOWS_RUNNER_GROUP_NAME|"
  "Group queue|ASPECT_WORKFLOWS_RUNNER_GROUP_QUEUE|"
  "Resource type|ASPECT_WORKFLOWS_RUNNER_RESOURCE_TYPE|"
  "Aspect launcher version|ASPECT_WORKFLOWS_RUNNER_ASPECT_LAUNCHER_VERSION|"
  "CI agent version|ASPECT_WORKFLOWS_RUNNER_CI_AGENT_VERSION|"
  "NVMe storage|ASPECT_WORKFLOWS_RUNNER_HAS_NVME_STORAGE|yesno"
  "Preemptible|ASPECT_WORKFLOWS_RUNNER_PREEMPTIBLE|yesno"
  "Warming enabled|ASPECT_WORKFLOWS_RUNNER_WARMING_ENABLED|yesno"
)

# Print the runner-metadata table, one "label: value" line per set env var.
log_workflows_runner_metadata() {
  local row label env_var fmt raw value
  for row in "${WORKFLOWS_METADATA_ROWS[@]}"; do
    IFS='|' read -r label env_var fmt <<< "${row}"
    raw="${!env_var:-}"
    [[ -z "${raw}" ]] && continue
    case "${fmt}" in
      upper) value="$(echo "${raw}" | tr '[:lower:]' '[:upper:]')" ;;
      yesno) value="$(yesno "${raw}")" ;;
      *)     value="${raw}" ;;
    esac
    log "${label}: ${value}"
  done
}
