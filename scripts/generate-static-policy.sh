#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
GENERATOR="${ROOT_DIR}/bin/safehouse.sh"

output_dir="${ROOT_DIR}/dist"
default_policy_path="${output_dir}/safehouse.generated.sb"
apps_policy_path="${output_dir}/safehouse-for-apps.generated.sb"
template_root="/tmp/agent-safehouse-static-template"
template_home="${template_root}/home"
template_workdir="${template_root}/workspace"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--output-dir PATH]

Description:
  Generate committed static baseline policy files in dist/:
    - safehouse.generated.sb (default policy)
    - safehouse-for-apps.generated.sb (--enable=macos-gui,electron)
  The policy is generated with deterministic template values:
    HOME=${template_home}
    workdir=${template_workdir}

Options:
  --output-dir PATH
      Output directory (default: ${output_dir})

  -h, --help
      Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      output_dir="$2"
      shift 2
      ;;
    --output-dir=*)
      output_dir="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$output_dir" != /* ]]; then
  output_dir="${ROOT_DIR}/${output_dir}"
fi

if [[ ! -x "$GENERATOR" ]]; then
  echo "Policy generator is missing or not executable: ${GENERATOR}" >&2
  exit 1
fi

default_policy_path="${output_dir%/}/safehouse.generated.sb"
apps_policy_path="${output_dir%/}/safehouse-for-apps.generated.sb"

mkdir -p "$output_dir" "$template_home" "$template_workdir"

(
  cd "$template_workdir"
  HOME="$template_home" "$GENERATOR" --output "$default_policy_path" >/dev/null
  HOME="$template_home" "$GENERATOR" --enable=macos-gui,electron --output "$apps_policy_path" >/dev/null
)

chmod 0644 "$default_policy_path" "$apps_policy_path"

printf '%s\n' "$default_policy_path"
printf '%s\n' "$apps_policy_path"
