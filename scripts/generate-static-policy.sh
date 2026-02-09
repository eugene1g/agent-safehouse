#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
GENERATOR="${ROOT_DIR}/bin/generate-policy.sh"

output_path="${ROOT_DIR}/generated/agent-safehouse-policy.sb"
template_root="/tmp/agent-safehouse-static-template"
template_home="${template_root}/home"
template_workdir="${template_root}/workspace"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--output PATH]

Description:
  Generate a committed, static baseline policy file in generated/.
  The policy is generated with deterministic template values:
    HOME=${template_home}
    workdir=${template_workdir}

Options:
  --output PATH
      Output file path (default: ${output_path})

  -h, --help
      Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      output_path="$2"
      shift 2
      ;;
    --output=*)
      output_path="${1#*=}"
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

if [[ "$output_path" != /* ]]; then
  output_path="${ROOT_DIR}/${output_path}"
fi

if [[ ! -x "$GENERATOR" ]]; then
  echo "Policy generator is missing or not executable: ${GENERATOR}" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")" "$template_home" "$template_workdir"

(
  cd "$template_workdir"
  HOME="$template_home" "$GENERATOR" --output "$output_path" >/dev/null
)

chmod 0644 "$output_path"

printf '%s\n' "$output_path"
