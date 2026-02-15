#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"
SAFEHOUSE="${REPO_ROOT}/bin/safehouse.sh"
ADAPTER_DIR="${SCRIPT_DIR}/adapters"
AGENT_PROFILES_DIR="${REPO_ROOT}/profiles/60-agents"
PNPM_AGENTS_DIR="${REPO_ROOT}/tests/e2e/agents/pnpm"
PNPM_AGENTS_BIN_DIR="${PNPM_AGENTS_DIR}/node_modules/.bin"
LOCAL_AGENTS_ROOT="${REPO_ROOT}/tests/e2e/agents"
LOCAL_AGENTS_BIN_DIR="${LOCAL_AGENTS_ROOT}/bin"

STRICT_MODE="${SAFEHOUSE_E2E_LIVE_STRICT:-1}"
ALLOW_PREREQ_SKIP="${SAFEHOUSE_E2E_LIVE_ALLOW_PREREQ_SKIP:-0}"
USE_PNPM_AGENTS="${SAFEHOUSE_E2E_USE_PNPM_AGENTS:-1}"
ALLOW_GLOBAL_BIN="${SAFEHOUSE_E2E_ALLOW_GLOBAL_BIN:-1}"
REQUIRE_BINARIES="${SAFEHOUSE_E2E_LIVE_REQUIRE_BINARIES:-0}"
LIVE_JOBS="${SAFEHOUSE_E2E_LIVE_JOBS:-1}"

PROFILE_ONLY=""
LIST_PROFILES=0

TMP_ROOT=""
pass_count=0
skip_count=0
fail_count=0
total_count=0
executed_count=0
attempted_count=0
NODE_ALLOW_DIRS_RO=""

log_info() {
	echo "INFO: $1"
}

log_pass() {
	echo "PASS: $1"
}

log_skip() {
	echo "SKIP: $1"
}

log_fail() {
	echo "FAIL: $1"
}

usage() {
	cat <<'EOF'
Usage:
  ./tests/e2e/live/run.sh
  ./tests/e2e/live/run.sh --profile <profile>
  ./tests/e2e/live/run.sh --jobs <n>
  ./tests/e2e/live/run.sh --list-profiles

Environment:
  SAFEHOUSE_E2E_LIVE_STRICT
  SAFEHOUSE_E2E_LIVE_ALLOW_PREREQ_SKIP
  SAFEHOUSE_E2E_LIVE_COMMAND_TIMEOUT_SECS
  SAFEHOUSE_E2E_LIVE_JOBS
  SAFEHOUSE_E2E_USE_PNPM_AGENTS
  SAFEHOUSE_E2E_ALLOW_GLOBAL_BIN
EOF
}

# shellcheck disable=SC2329
cleanup() {
	if [[ -n "${TMP_ROOT}" && -d "${TMP_ROOT}" ]]; then
		rm -rf "${TMP_ROOT}"
	fi
}

require_command() {
	local command_name="$1"
	if ! command -v "${command_name}" >/dev/null 2>&1; then
		echo "ERROR: missing required command: ${command_name}" >&2
		exit 1
	fi
}

preflight_sandbox_exec() {
	local preflight_policy
	preflight_policy="$(mktemp /tmp/safehouse-live-preflight.XXXXXX)"
	printf '(version 1)\n(allow default)\n' >"${preflight_policy}"

	if ! sandbox-exec -f "${preflight_policy}" -- /bin/echo preflight-ok >/dev/null 2>&1; then
		rm -f "${preflight_policy}"
		echo "ERROR: sandbox-exec cannot run (nested sandbox or SIP restriction)." >&2
		exit 2
	fi

	rm -f "${preflight_policy}"
}

command_basename_for_profile() {
	local profile_base="$1"

	case "${profile_base}" in
	claude-code) printf '%s\n' "claude" ;;
	cursor-agent) printf '%s\n' "cursor-agent" ;;
	kilo-code) printf '%s\n' "kilo" ;;
	*) printf '%s\n' "${profile_base}" ;;
	esac
}

parse_args() {
	while [[ "$#" -gt 0 ]]; do
		case "$1" in
		--profile)
			PROFILE_ONLY="${2:-}"
			if [[ -z "${PROFILE_ONLY}" ]]; then
				echo "ERROR: --profile requires a value" >&2
				exit 1
			fi
			shift 2
			;;
		--jobs)
			LIVE_JOBS="${2:-}"
			if [[ -z "${LIVE_JOBS}" ]]; then
				echo "ERROR: --jobs requires a value" >&2
				exit 1
			fi
			shift 2
			;;
		--list-profiles)
			LIST_PROFILES=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			echo "ERROR: unknown argument: $1" >&2
			exit 1
			;;
		esac
	done
}

list_profiles() {
	fd -t f '\.sb$' "${AGENT_PROFILES_DIR}" | sort | while IFS= read -r p; do
		[[ -n "${p}" ]] || continue
		basename "${p}" .sb
	done
}

is_mise_shim_path() {
	local path_value="$1"
	[[ "${path_value}" == *"/.local/share/mise/shims/"* ]]
}

resolve_from_mise_installs() {
	local command_basename="$1"
	local candidate=""
	local found=""

	# Common stable symlink path.
	candidate="${HOME}/.local/share/mise/installs/node/latest/bin/${command_basename}"
	if [[ -x "${candidate}" ]]; then
		printf '%s\n' "${candidate}"
		return 0
	fi

	# Fallback to highest lexicographic installed node version path.
	shopt -s nullglob
	for candidate in "${HOME}"/.local/share/mise/installs/node/*/bin/"${command_basename}"; do
		if [[ -x "${candidate}" ]]; then
			found="${candidate}"
		fi
	done
	shopt -u nullglob

	if [[ -n "${found}" ]]; then
		printf '%s\n' "${found}"
		return 0
	fi

	return 1
}

resolve_agent_binary() {
	local command_basename="$1"
	local command_path=""
	local shim_path=""
	local candidate=""

	# Prefer repo-local agent binaries first (regardless of global PATH settings).
	candidate="${LOCAL_AGENTS_BIN_DIR}/${command_basename}"
	if [[ -x "${candidate}" ]]; then
		printf '%s\n' "${candidate}"
		return 0
	fi

	if [[ "${USE_PNPM_AGENTS}" == "1" ]]; then
		candidate="${PNPM_AGENTS_BIN_DIR}/${command_basename}"
		if [[ -x "${candidate}" ]]; then
			printf '%s\n' "${candidate}"
			return 0
		fi
	fi

	if [[ "${ALLOW_GLOBAL_BIN}" != "1" ]]; then
		return 1
	fi

	# Prefer direct user-level installs first (no shim manager required).
	for candidate in \
		"${HOME}/.local/bin/${command_basename}" \
		"${HOME}/.amp/bin/${command_basename}" \
		"${HOME}/.opencode/bin/${command_basename}" \
		"${HOME}/.cargo/bin/${command_basename}"; do
		if [[ -x "${candidate}" ]]; then
			printf '%s\n' "${candidate}"
			return 0
		fi
	done

	# If command resolves on PATH, only accept immediately when not a mise shim.
	if command -v "${command_basename}" >/dev/null 2>&1; then
		command_path="$(command -v "${command_basename}")"
		if ! is_mise_shim_path "${command_path}"; then
			printf '%s\n' "${command_path}"
			return 0
		fi
		shim_path="${command_path}"
	fi

	# Try real binaries under mise installs without invoking shims.
	if resolve_from_mise_installs "${command_basename}"; then
		return 0
	fi

	# If only a shim exists and no direct install path is available, treat as unresolved.
	if [[ -n "${shim_path}" ]]; then
		return 1
	fi

	return 1
}

realpath_or_self() {
	local path_value="$1"
	perl -MCwd=realpath -e 'my $r = realpath($ARGV[0]); print $r ? $r : $ARGV[0];' "${path_value}" 2>/dev/null || printf '%s' "${path_value}"
}

run_profile_live_check() {
	local profile_base="$1"
	local adapter_path="$2"
	local agent_bin="$3"
	local agent_allow_dirs_ro="$4"
	local workdir="$5"
	local forbidden_file="$6"
	local secret_token="$7"
	local response_token="$8"
	local denial_token="$9"
	local transcript_path="${10}"

	local status=0
	local result_rc=0

	log_info "[${profile_base}] asking live LLM positive query (token: ${response_token})"
	log_info "[${profile_base}] asking live LLM negative query for forbidden file: ${forbidden_file}"
	log_info "[${profile_base}] forbidden file contains secret token: ${secret_token}"
	log_info "[${profile_base}] adapter: ${adapter_path}"
	log_info "[${profile_base}] binary: ${agent_bin}"
	log_info "[${profile_base}] add-dirs-ro: ${agent_allow_dirs_ro}"

	attempted_count=$((attempted_count + 1))

	set +e
	SAFEHOUSE="${SAFEHOUSE}" \
		AGENT_BIN="${agent_bin}" \
		AGENT_BIN_DIR="$(dirname "${agent_bin}")" \
		AGENT_ALLOW_DIRS_RO="${agent_allow_dirs_ro}" \
		AGENT_PROFILE="${profile_base}" \
		WORKDIR="${workdir}" \
		FORBIDDEN_FILE="${forbidden_file}" \
		SECRET_TOKEN="${secret_token}" \
		RESPONSE_TOKEN="${response_token}" \
		DENIAL_TOKEN="${denial_token}" \
		TRANSCRIPT_PATH="${transcript_path}" \
		"${adapter_path}"
	status=$?
	set -e

	case "${status}" in
	0)
		pass_count=$((pass_count + 1))
		executed_count=$((executed_count + 1))
		log_pass "[${profile_base}] live LLM query/response and forbidden-read checks passed"
		result_rc=0
		;;
	2)
		if [[ "${ALLOW_PREREQ_SKIP}" == "1" ]]; then
			skip_count=$((skip_count + 1))
			log_skip "[${profile_base}] adapter reported unmet prerequisites (auth/config/setup)"
			result_rc=2
		else
			fail_count=$((fail_count + 1))
			log_fail "[${profile_base}] adapter reported unmet prerequisites; set SAFEHOUSE_E2E_LIVE_ALLOW_PREREQ_SKIP=1 to allow skips"
			result_rc=1
		fi
		;;
	*)
		fail_count=$((fail_count + 1))
		log_fail "[${profile_base}] adapter failed; transcript: ${transcript_path}"
		result_rc=1
		;;
	esac

	return "${result_rc}"
}

main() {
	local profile_path profile_base command_basename adapter_path agent_bin
	local agent_allow_dirs_ro agent_bin_dir
	local case_root workdir forbidden_dir forbidden_file transcript_path
	local secret_token response_token denial_token

	require_command sandbox-exec
	require_command rg
	require_command fd
	require_command perl

	if [[ ! -x "${SAFEHOUSE}" ]]; then
		echo "ERROR: safehouse wrapper is missing or not executable: ${SAFEHOUSE}" >&2
		exit 1
	fi
	if [[ ! -d "${ADAPTER_DIR}" ]]; then
		echo "ERROR: missing adapter directory: ${ADAPTER_DIR}" >&2
		exit 1
	fi
	if [[ ! -d "${AGENT_PROFILES_DIR}" ]]; then
		echo "ERROR: missing agent profiles directory: ${AGENT_PROFILES_DIR}" >&2
		exit 1
	fi

	preflight_sandbox_exec

	# Node-based CLIs installed via pnpm often rely on `#!/usr/bin/env node`.
	# On CI runners, node lives under $HOME/hostedtoolcache/* which Safehouse would deny by default.
	# Add read-only grants for node's bin dir and (when safe) its install prefix.
	if command -v node >/dev/null 2>&1; then
		local node_real node_dir node_prefix
		node_real="$(realpath_or_self "$(command -v node)")"
		node_dir="$(dirname "${node_real}")"
		NODE_ALLOW_DIRS_RO="${node_dir}"
		node_prefix="$(cd "${node_dir}/.." && pwd -P)"
		if [[ "${node_prefix}" != "${HOME}" ]]; then
			NODE_ALLOW_DIRS_RO="${NODE_ALLOW_DIRS_RO}:${node_prefix}"
		fi
	fi

	TMP_ROOT="$(mktemp -d /tmp/safehouse-live-e2e.XXXXXX)"

	run_one_profile() {
		local profile_base="$1"
		local profile_path="${AGENT_PROFILES_DIR}/${profile_base}.sb"
		local command_basename adapter_path agent_bin agent_bin_dir agent_allow_dirs_ro
		local case_root workdir forbidden_dir forbidden_file transcript_path
		local secret_token response_token denial_token

		if [[ ! -f "${profile_path}" ]]; then
			log_fail "[${profile_base}] profile file not found: ${profile_path}"
			fail_count=$((fail_count + 1))
			return 1
		fi

		total_count=$((total_count + 1))
		command_basename="$(command_basename_for_profile "${profile_base}")"
		adapter_path="${ADAPTER_DIR}/${profile_base}.sh"

		if ! agent_bin="$(resolve_agent_binary "${command_basename}")"; then
			if [[ "${REQUIRE_BINARIES}" == "1" ]]; then
				fail_count=$((fail_count + 1))
				log_fail "[${profile_base}] binary not found for command basename '${command_basename}'"
				return 1
			fi
			skip_count=$((skip_count + 1))
			log_skip "[${profile_base}] binary not found for command basename '${command_basename}'"
			return 2
		fi

		if [[ ! -x "${adapter_path}" ]]; then
			if [[ "${STRICT_MODE}" == "1" ]]; then
				fail_count=$((fail_count + 1))
				log_fail "[${profile_base}] binary present (${agent_bin}) but no adapter at ${adapter_path}"
				return 1
			fi
			skip_count=$((skip_count + 1))
			log_skip "[${profile_base}] no adapter yet for installed binary (${agent_bin})"
			return 2
		fi

		case_root="${TMP_ROOT}/${profile_base}"
		workdir="${case_root}/workdir"
		forbidden_dir="${HOME}/.safehouse-live-forbidden.${profile_base}.${RANDOM}"
		forbidden_file="${forbidden_dir}/secret.txt"
		transcript_path="${case_root}/transcript.log"

		mkdir -p "${workdir}" "${forbidden_dir}" "${case_root}"
		secret_token="SAFEHOUSESECRET${RANDOM}${RANDOM}X"
		response_token="SAFEHOUSERESP${RANDOM}${RANDOM}X"
		denial_token="SAFEHOUSEDENIED${RANDOM}${RANDOM}X"
		printf '%s\n' "${secret_token}" >"${forbidden_file}"

		agent_bin_dir="$(dirname "${agent_bin}")"
		agent_allow_dirs_ro="${agent_bin_dir}"
		if [[ "${USE_PNPM_AGENTS}" == "1" ]] && [[ "${agent_bin}" == "${PNPM_AGENTS_BIN_DIR}/"* ]]; then
			agent_allow_dirs_ro="${agent_allow_dirs_ro}:${PNPM_AGENTS_DIR}"
		fi
		if [[ "${agent_bin}" == "${LOCAL_AGENTS_ROOT}/"* ]]; then
			agent_allow_dirs_ro="${agent_allow_dirs_ro}:${LOCAL_AGENTS_ROOT}"
		fi
		if [[ -n "${NODE_ALLOW_DIRS_RO}" ]]; then
			agent_allow_dirs_ro="${agent_allow_dirs_ro}:${NODE_ALLOW_DIRS_RO}"
		fi

		local rc=0
		set +e
		run_profile_live_check \
			"${profile_base}" \
			"${adapter_path}" \
			"${agent_bin}" \
			"${agent_allow_dirs_ro}" \
			"${workdir}" \
			"${forbidden_file}" \
			"${secret_token}" \
			"${response_token}" \
			"${denial_token}" \
			"${transcript_path}"
		rc=$?
		set -e
		rm -rf "${forbidden_dir}"
		return "${rc}"
	}

	if [[ "${PROFILE_ONLY}" != "" ]]; then
		echo "Running live LLM E2E checks for a single agent profile: ${PROFILE_ONLY}"
		echo "Strict mode: ${STRICT_MODE}"
		echo "Allow prerequisite skips: ${ALLOW_PREREQ_SKIP}"
		echo "Use pnpm agents dir: ${USE_PNPM_AGENTS} (${PNPM_AGENTS_DIR})"
		echo "Allow global PATH/home binaries: ${ALLOW_GLOBAL_BIN}"
		echo "Require binaries for all configured profiles: ${REQUIRE_BINARIES}"

		if run_one_profile "${PROFILE_ONLY}"; then
			exit 0
		else
			# N.B. The exit status of the `if ...; then ...; fi` compound command is 0
			# even when the condition fails. Preserve the condition's exit status.
			exit $?
		fi
	fi

	if [[ "${LIVE_JOBS}" != "1" ]]; then
		local jobs="${LIVE_JOBS}"
		local profiles_file log_dir script_path total pass skip fail executed profile log_file rc_file rc

		script_path="${SCRIPT_DIR}/run.sh"
		profiles_file="${TMP_ROOT}/profiles.txt"
		log_dir="${TMP_ROOT}/logs"
		mkdir -p "${log_dir}"

		list_profiles >"${profiles_file}"
		total="$(wc -l <"${profiles_file}" | tr -d '[:space:]')"
		if [[ "${total}" -eq 0 ]]; then
			echo "ERROR: no agent profiles were discovered under ${AGENT_PROFILES_DIR}" >&2
			exit 1
		fi

		echo "Running live LLM E2E checks in parallel across ${total} configured agent profiles..."
		echo "Strict mode: ${STRICT_MODE}"
		echo "Allow prerequisite skips: ${ALLOW_PREREQ_SKIP}"
		echo "Use pnpm agents dir: ${USE_PNPM_AGENTS} (${PNPM_AGENTS_DIR})"
		echo "Allow global PATH/home binaries: ${ALLOW_GLOBAL_BIN}"
		echo "Require binaries for all configured profiles: ${REQUIRE_BINARIES}"
		echo "Live jobs: ${jobs} (set SAFEHOUSE_E2E_LIVE_JOBS or use --jobs)"
		echo "Logs: ${log_dir}"

		xargs -n 1 -P "${jobs}" -I {} bash -c '
profile="$1"
log_dir="$2"
script_path="$3"
log_file="${log_dir}/${profile}.log"
rc_file="${log_file}.rc"

SAFEHOUSE_E2E_LIVE_JOBS=1 "${script_path}" --profile "${profile}" >"${log_file}" 2>&1
rc=$?
printf "%s\n" "${rc}" >"${rc_file}"
exit "${rc}"
' _ {} "${log_dir}" "${script_path}" <"${profiles_file}" || true

		pass=0
		skip=0
		fail=0
		executed=0
		while IFS= read -r profile; do
			[[ -n "${profile}" ]] || continue
			log_file="${log_dir}/${profile}.log"
			rc_file="${log_file}.rc"
			rc="1"
			if [[ -f "${rc_file}" ]]; then
				rc="$(cat "${rc_file}" | tr -d '[:space:]')"
			fi
			case "${rc}" in
			0)
				pass=$((pass + 1))
				executed=$((executed + 1))
				;;
			2)
				skip=$((skip + 1))
				;;
			*)
				fail=$((fail + 1))
				;;
			esac

			echo ""
			echo "===== [${profile}] ====="
			if [[ -f "${log_file}" ]]; then
				cat "${log_file}"
			else
				echo "missing log file: ${log_file}"
			fi
		done <"${profiles_file}"

		echo ""
		echo "Live LLM E2E summary: total=${total} pass=${pass} skip=${skip} fail=${fail} executed=${executed}"

		if [[ "${executed}" -eq 0 ]]; then
			echo "ERROR: no live agent checks executed; install/auth at least one supported agent adapter." >&2
			exit 1
		fi
		if [[ "${fail}" -gt 0 ]]; then
			exit 1
		fi

		exit 0
	fi

	echo "Running live LLM E2E checks for configured agent profiles..."
	echo "Strict mode: ${STRICT_MODE}"
	echo "Allow prerequisite skips: ${ALLOW_PREREQ_SKIP}"
	echo "Use pnpm agents dir: ${USE_PNPM_AGENTS} (${PNPM_AGENTS_DIR})"
	echo "Allow global PATH/home binaries: ${ALLOW_GLOBAL_BIN}"
	echo "Require binaries for all configured profiles: ${REQUIRE_BINARIES}"

	while IFS= read -r profile_path; do
		[[ -n "${profile_path}" ]] || continue
		profile_base="$(basename "${profile_path}" .sb)"
		run_one_profile "${profile_base}" || true
	done < <(fd -t f '\.sb$' "${AGENT_PROFILES_DIR}" | sort)

	echo ""
	echo "Live LLM E2E summary: total=${total_count} attempted=${attempted_count} pass=${pass_count} skip=${skip_count} fail=${fail_count} executed=${executed_count}"

	if [[ "${executed_count}" -eq 0 ]]; then
		echo "ERROR: no live agent checks executed; install/auth at least one supported agent adapter." >&2
		exit 1
	fi
	if [[ "${fail_count}" -gt 0 ]]; then
		exit 1
	fi

	exit 0
}

trap cleanup EXIT
parse_args "$@"

if [[ "${LIST_PROFILES}" == "1" ]]; then
	require_command fd
	list_profiles
	exit 0
fi

main "$@"
