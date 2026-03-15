#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

PARSED_SUITE=""
PARSED_BATS_ARGS=()

sft_usage() {
  cat <<'EOF'
Usage: ./tests/run.sh [policy|surface|e2e] [bats-options]

Without a suite selector, ./tests/run.sh runs the default non-E2E suites:
  - policy
  - surface

Use `all` to run every suite, including `e2e`:
  - all

Single-file and direct test-path runs are intentionally not supported here.
Use bats directly for ad hoc file targeting, for example:
  bats tests/e2e/codex.bats
  bats tests/policy/integrations/docker.bats
EOF
}

sft_usage_error() {
  printf '%s\n\n' "$1" >&2
  sft_usage >&2
}

sft_cpu_count() {
  local cpu_count

  cpu_count="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  if [[ -n "$cpu_count" ]]; then
    printf '%s\n' "$cpu_count"
    return 0
  fi

  cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  if [[ -n "$cpu_count" ]]; then
    printf '%s\n' "$cpu_count"
    return 0
  fi

  printf '1\n'
}

sft_has_parallel_backend() {
  command -v parallel >/dev/null 2>&1 || command -v rush >/dev/null 2>&1
}

sft_parallel_backend_name() {
  if command -v parallel >/dev/null 2>&1; then
    printf 'GNU parallel\n'
    return 0
  fi

  if command -v rush >/dev/null 2>&1; then
    printf 'rush\n'
    return 0
  fi

  return 1
}

sft_has_jobs_flag() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      -j|--jobs|--jobs=*)
        return 0
        ;;
    esac
  done

  return 1
}

sft_parse_args() {
  local arg next_has_value=0

  PARSED_SUITE=""
  PARSED_BATS_ARGS=()

  for arg in "$@"; do
    if [[ "$next_has_value" -eq 1 ]]; then
      PARSED_BATS_ARGS+=("$arg")
      next_has_value=0
      continue
    fi

    case "$arg" in
      -h|--help)
        sft_usage
        exit 0
        ;;
      --)
        sft_usage_error "tests/run.sh does not accept '--' or direct test targets."
        return 1
        ;;
      --filter-tags|--filter-tags=*)
        sft_usage_error "tests/run.sh manages suite selection with internal tag filters; use bats directly for custom --filter-tags runs."
        return 1
        ;;
      -r|--recursive)
        sft_usage_error "tests/run.sh already runs recursively from the tests root."
        return 1
        ;;
      -f|--filter|--negative-filter|--filter-status|-F|--formatter|--report-formatter|--gather-test-outputs-in|-o|--output|-j|--jobs|--parallel-binary-name|--line-reference-format|--code-quote-style)
        PARSED_BATS_ARGS+=("$arg")
        next_has_value=1
        ;;
      --filter=*|--negative-filter=*|--filter-status=*|--formatter=*|--report-formatter=*|--gather-test-outputs-in=*|--output=*|--jobs=*|--parallel-binary-name=*|--line-reference-format=*|--code-quote-style=*)
        PARSED_BATS_ARGS+=("$arg")
        ;;
      -*)
        PARSED_BATS_ARGS+=("$arg")
        ;;
      policy|surface|e2e|all)
        if [[ -n "$PARSED_SUITE" ]]; then
          sft_usage_error "tests/run.sh accepts at most one suite selector."
          return 1
        fi

        PARSED_SUITE="$arg"
        ;;
      *)
        sft_usage_error "tests/run.sh does not support direct file or directory targets. Use bats directly for ad hoc file runs."
        return 1
        ;;
    esac
  done

  if [[ "$next_has_value" -eq 1 ]]; then
    sft_usage_error "Missing value for the final bats option."
    return 1
  fi
}

sft_requested_jobs() {
  local arg next_is_jobs=0

  for arg in "$@"; do
    if [[ "$next_is_jobs" -eq 1 ]]; then
      printf '%s\n' "$arg"
      return 0
    fi

    case "$arg" in
      -j|--jobs)
        next_is_jobs=1
        ;;
      --jobs=*)
        printf '%s\n' "${arg#--jobs=}"
        return 0
        ;;
    esac
  done

  return 1
}

sft_default_jobs() {
  local jobs cpu_count multiplier max_jobs

  if [[ -n "${SAFEHOUSE_BATS_JOBS:-}" ]]; then
    jobs="${SAFEHOUSE_BATS_JOBS}"
  elif sft_suite_includes_e2e; then
    if [[ -n "${SAFEHOUSE_BATS_E2E_JOBS:-}" ]]; then
      jobs="${SAFEHOUSE_BATS_E2E_JOBS}"
    else
      cpu_count="$(sft_cpu_count)"
      # Live agent TUIs contend on startup latency and remote APIs, so keep the
      # default e2e fanout close to the available CPUs instead of oversubscribing.
      jobs="${cpu_count}"
      max_jobs="${SAFEHOUSE_BATS_E2E_MAX_JOBS:-4}"

      if [[ "$max_jobs" =~ ^[0-9]+$ ]] && [[ "$max_jobs" -ge 1 ]] && [[ "$jobs" -gt "$max_jobs" ]]; then
        jobs="$max_jobs"
      fi
    fi
  else
    cpu_count="$(sft_cpu_count)"
    # The suite is dominated by sandboxed subprocess and filesystem work, so modest oversubscription improves wall time.
    multiplier="${SAFEHOUSE_BATS_JOBS_MULTIPLIER:-4}"
    max_jobs="${SAFEHOUSE_BATS_MAX_JOBS:-48}"

    if [[ "$multiplier" =~ ^[0-9]+$ ]] && [[ "$multiplier" -ge 1 ]]; then
      jobs=$((cpu_count * multiplier))
    else
      jobs="$cpu_count"
    fi

    if [[ "$max_jobs" =~ ^[0-9]+$ ]] && [[ "$max_jobs" -ge 1 ]] && [[ "$jobs" -gt "$max_jobs" ]]; then
      jobs="$max_jobs"
    fi
  fi

  if [[ "$jobs" =~ ^[0-9]+$ ]] && [[ "$jobs" -ge 1 ]]; then
    printf '%s\n' "$jobs"
    return 0
  fi

  printf '1\n'
}

sft_log_mode() {
  local jobs="$1" backend_name="${2:-}"

  if [[ -n "$backend_name" ]]; then
    printf 'Running Bats with %s parallel jobs via %s.\n' "$jobs" "$backend_name" >&2
    return 0
  fi

  printf 'Running Bats serially.\n' >&2
}

sft_log_serial_without_backend() {
  printf 'Running Bats serially. Install GNU parallel (`brew install parallel`) or rush to enable CPU-count parallelism.\n' >&2
}

sft_suite_includes_e2e() {
  case "${PARSED_SUITE:-}" in
    e2e|all)
      return 0
      ;;
  esac

  return 1
}

main() {
  local jobs backend_name requested_jobs parallelize_across_files=0
  local -a bats_args

  sft_parse_args "$@" || exit 1

  bats_args=(--timing --print-output-on-failure)

  if [[ "${#PARSED_BATS_ARGS[@]}" -gt 0 ]] && sft_has_jobs_flag "${PARSED_BATS_ARGS[@]}"; then
    requested_jobs="$(sft_requested_jobs "${PARSED_BATS_ARGS[@]}" || true)"
    if [[ "$requested_jobs" =~ ^[0-9]+$ ]] && [[ "$requested_jobs" -gt 1 ]] && sft_has_parallel_backend; then
      backend_name="$(sft_parallel_backend_name)"
      parallelize_across_files=1
      sft_log_mode "$requested_jobs" "$backend_name"
    elif [[ "$requested_jobs" =~ ^[0-9]+$ ]] && [[ "$requested_jobs" -gt 1 ]]; then
      parallelize_across_files=1
      printf 'Requested %s parallel jobs, but no supported Bats backend is installed. Install GNU parallel (`brew install parallel`) or rush.\n' "$requested_jobs" >&2
    else
      sft_log_mode "1"
    fi
  else
    jobs="$(sft_default_jobs)"
    if [[ "$jobs" -gt 1 ]] && sft_has_parallel_backend; then
      backend_name="$(sft_parallel_backend_name)"
      parallelize_across_files=1
      bats_args+=(--jobs "$jobs")
      sft_log_mode "$jobs" "$backend_name"
    elif [[ "$jobs" -gt 1 ]]; then
      sft_log_serial_without_backend
    else
      sft_log_mode "1"
    fi
  fi

  if sft_suite_includes_e2e && [[ "$parallelize_across_files" -eq 1 ]]; then
    # E2E agent TUIs share shell-local tmux state within a test file, so keep
    # tests in the same file serialized only when Bats file-level parallelism is enabled.
    bats_args+=(--no-parallelize-within-files)
  fi

  case "${PARSED_SUITE:-}" in
    "")
      bats_args+=(--filter-tags "suite:policy" --filter-tags "suite:surface")
      ;;
    all)
      ;;
    policy|surface|e2e)
      bats_args+=(--filter-tags "suite:${PARSED_SUITE}")
      ;;
  esac

  if [[ "${#PARSED_BATS_ARGS[@]}" -gt 0 ]]; then
    exec bats "${bats_args[@]}" "${PARSED_BATS_ARGS[@]}" -r "$SCRIPT_DIR"
  fi

  exec bats "${bats_args[@]}" -r "$SCRIPT_DIR"
}

main "$@"
