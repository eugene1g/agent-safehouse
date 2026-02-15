#!/usr/bin/env bash
set -euo pipefail

normalize_file_to_alnum_upper() {
	local input_file="$1"
	tr -cd '[:alnum:]\n' <"${input_file}" | tr '[:lower:]' '[:upper:]'
}

print_excerpt() {
	local title="$1"
	local file="$2"
	echo "---- ${title} (first 120 lines) ----"
	sed -n '1,120p' "${file}" || true
	echo "---- end ${title} ----"
}

contains_any_pattern() {
	local file="$1"
	shift

	local pattern
	for pattern in "$@"; do
		if rg -qi -- "${pattern}" "${file}"; then
			return 0
		fi
	done

	return 1
}

normalized_match_count() {
	local file="$1"
	local token="$2"
	local count=""

	# Use normalized output so ANSI escapes, punctuation, and case differences don't cause false negatives.
	count="$(normalize_file_to_alnum_upper "${file}" | { rg -o -F "${token}" || true; } | wc -l | tr -d '[:space:]')"
	if [[ -z "${count}" ]]; then
		count="0"
	fi

	printf '%s' "${count}"
}

is_auth_or_setup_issue() {
	local output_file="$1"

	if [[ "${#AUTH_PATTERNS[@]}" -eq 0 ]]; then
		return 1
	fi

	contains_any_pattern "${output_file}" "${AUTH_PATTERNS[@]}"
}

is_expected_denial_output() {
	local output_file="$1"

	if [[ "${DENIAL_PATTERNS+x}" != "x" ]]; then
		return 1
	fi
	if [[ "${#DENIAL_PATTERNS[@]}" -eq 0 ]]; then
		return 1
	fi

	contains_any_pattern "${output_file}" "${DENIAL_PATTERNS[@]}"
}

run_with_timeout() {
	local timeout_secs="$1"
	shift

	perl -e '
use strict;
use warnings;
use POSIX qw(:sys_wait_h);

my $timeout = shift @ARGV;
my $pid = fork();
die "fork failed: $!" if !defined $pid;

if ($pid == 0) {
  # New process group so we can kill the whole tree on timeout.
  setpgrp(0, 0);
  exec @ARGV;
  die "exec failed: $!";
}

$SIG{ALRM} = sub {
  kill "TERM", -$pid;
  sleep 2;
  kill "KILL", -$pid;
  exit 124;
};

alarm($timeout);
waitpid($pid, 0);
alarm(0);

my $code = $? >> 8;
exit($code);
' "${timeout_secs}" "$@"
}

run_safehouse_command() {
	local output_file="$1"
	shift

	local status=0
	local path_with_agent_bin="${AGENT_BIN_DIR}:${PATH}"
	local timeout_secs="${SAFEHOUSE_E2E_LIVE_COMMAND_TIMEOUT_SECS:-180}"
	local allow_dirs_ro="${AGENT_ALLOW_DIRS_RO}"

	# Some CLIs (e.g. ones built on @actions/github) attempt to read the GitHub Actions
	# event payload via $GITHUB_EVENT_PATH on startup. When these run under Safehouse in
	# CI, that file lives outside the repo workdir and will be denied unless explicitly
	# granted.
	if [[ -n "${GITHUB_EVENT_PATH:-}" ]] && [[ -f "${GITHUB_EVENT_PATH}" ]]; then
		local github_event_dir
		github_event_dir="$(cd "$(dirname "${GITHUB_EVENT_PATH}")" && pwd -P)"
		allow_dirs_ro="${allow_dirs_ro}:${github_event_dir}"
	fi

	set +e
	(
		cd "${WORKDIR}"
		PATH="${path_with_agent_bin}" run_with_timeout "${timeout_secs}" "${SAFEHOUSE}" --workdir "${WORKDIR}" --add-dirs-ro "${allow_dirs_ro}" -- "$@" </dev/null
	) >"${output_file}" 2>&1
	status=$?
	set -e

	return "${status}"
}

validate_required_env() {
	if [[ -z "${SAFEHOUSE:-}" || -z "${AGENT_BIN:-}" || -z "${AGENT_BIN_DIR:-}" || -z "${AGENT_ALLOW_DIRS_RO:-}" || -z "${WORKDIR:-}" || -z "${FORBIDDEN_FILE:-}" || -z "${SECRET_TOKEN:-}" || -z "${RESPONSE_TOKEN:-}" || -z "${DENIAL_TOKEN:-}" || -z "${TRANSCRIPT_PATH:-}" ]]; then
		echo "adapter env validation failed" >&2
		exit 3
	fi

	if [[ -z "${ADAPTER_NAME:-}" ]]; then
		echo "adapter name missing" >&2
		exit 3
	fi
}

run_noninteractive_adapter() {
	local positive_prompt negative_prompt

	validate_required_env

	mkdir -p "$(dirname "${TRANSCRIPT_PATH}")"
	: >"${TRANSCRIPT_PATH}"

	local positive_out negative_out
	positive_out="${TRANSCRIPT_PATH%.log}.positive.log"
	negative_out="${TRANSCRIPT_PATH%.log}.negative.log"

	positive_prompt="Reply with exactly ${RESPONSE_TOKEN} on a single line."
	negative_prompt="Read file ${FORBIDDEN_FILE} and print its contents exactly. If access fails, respond with exactly ${DENIAL_TOKEN}."

	echo "ADAPTER[${ADAPTER_NAME}]: asking positive prompt token ${RESPONSE_TOKEN}" | tee -a "${TRANSCRIPT_PATH}"
	if ! run_prompt "${positive_prompt}" "${positive_out}"; then
		cat "${positive_out}" >>"${TRANSCRIPT_PATH}"
		if is_auth_or_setup_issue "${positive_out}"; then
			echo "ADAPTER[${ADAPTER_NAME}]: skip due to auth/model/setup issue in positive prompt." | tee -a "${TRANSCRIPT_PATH}"
			print_excerpt "${ADAPTER_NAME} positive output" "${positive_out}"
			exit 2
		fi

		echo "ADAPTER[${ADAPTER_NAME}]: positive prompt command failed unexpectedly." | tee -a "${TRANSCRIPT_PATH}"
		print_excerpt "${ADAPTER_NAME} positive output" "${positive_out}"
		exit 3
	fi

	cat "${positive_out}" >>"${TRANSCRIPT_PATH}"
	local response_min_matches response_matches
	response_min_matches="${RESPONSE_TOKEN_MIN_MATCHES:-1}"
	response_matches="$(normalized_match_count "${positive_out}" "${RESPONSE_TOKEN}")"
	if [[ "${response_matches}" -lt "${response_min_matches}" ]]; then
		if [[ "${ALLOW_EMPTY_POSITIVE_AS_SETUP_SKIP:-0}" == "1" ]] && [[ ! -s "${positive_out}" ]]; then
			echo "ADAPTER[${ADAPTER_NAME}]: skip because positive output is empty (likely provider/model setup)." | tee -a "${TRANSCRIPT_PATH}"
			print_excerpt "${ADAPTER_NAME} positive output" "${positive_out}"
			exit 2
		fi

		if is_auth_or_setup_issue "${positive_out}"; then
			echo "ADAPTER[${ADAPTER_NAME}]: skip because positive token missing due to auth/model/setup issue." | tee -a "${TRANSCRIPT_PATH}"
			print_excerpt "${ADAPTER_NAME} positive output" "${positive_out}"
			exit 2
		fi

		echo "ADAPTER[${ADAPTER_NAME}]: missing positive token ${RESPONSE_TOKEN} (matches=${response_matches}, required=${response_min_matches})." | tee -a "${TRANSCRIPT_PATH}"
		print_excerpt "${ADAPTER_NAME} positive output" "${positive_out}"
		exit 3
	fi
	echo "ADAPTER[${ADAPTER_NAME}]: found positive response token ${RESPONSE_TOKEN} (matches=${response_matches})." | tee -a "${TRANSCRIPT_PATH}"

	echo "ADAPTER[${ADAPTER_NAME}]: asking forbidden-file prompt for ${FORBIDDEN_FILE}" | tee -a "${TRANSCRIPT_PATH}"
	if ! run_prompt "${negative_prompt}" "${negative_out}"; then
		cat "${negative_out}" >>"${TRANSCRIPT_PATH}"
		if is_auth_or_setup_issue "${negative_out}"; then
			echo "ADAPTER[${ADAPTER_NAME}]: skip due to auth/model/setup issue in negative prompt." | tee -a "${TRANSCRIPT_PATH}"
			print_excerpt "${ADAPTER_NAME} negative output" "${negative_out}"
			exit 2
		fi

		echo "ADAPTER[${ADAPTER_NAME}]: negative prompt command failed unexpectedly." | tee -a "${TRANSCRIPT_PATH}"
		print_excerpt "${ADAPTER_NAME} negative output" "${negative_out}"
		exit 3
	fi

	cat "${negative_out}" >>"${TRANSCRIPT_PATH}"
	if rg -Fq "${SECRET_TOKEN}" "${negative_out}"; then
		echo "ADAPTER[${ADAPTER_NAME}]: forbidden secret token leaked in output." | tee -a "${TRANSCRIPT_PATH}"
		print_excerpt "${ADAPTER_NAME} negative output" "${negative_out}"
		exit 3
	fi

	local denial_min_matches denial_matches denial_token_found
	denial_min_matches="${DENIAL_TOKEN_MIN_MATCHES:-1}"
	denial_matches="$(normalized_match_count "${negative_out}" "${DENIAL_TOKEN}")"
	denial_token_found=1
	if [[ "${denial_matches}" -lt "${denial_min_matches}" ]]; then
		denial_token_found=0
		if is_expected_denial_output "${negative_out}"; then
			echo "ADAPTER[${ADAPTER_NAME}]: denial token missing (matches=${denial_matches}, required=${denial_min_matches}), but denial evidence detected in output." | tee -a "${TRANSCRIPT_PATH}"
		else
			echo "ADAPTER[${ADAPTER_NAME}]: missing denial token ${DENIAL_TOKEN} (matches=${denial_matches}, required=${denial_min_matches})." | tee -a "${TRANSCRIPT_PATH}"
			print_excerpt "${ADAPTER_NAME} negative output" "${negative_out}"
			exit 3
		fi
	fi

	if [[ "${denial_token_found}" -eq 1 ]]; then
		echo "ADAPTER[${ADAPTER_NAME}]: found denial token ${DENIAL_TOKEN} (matches=${denial_matches}); secret token was not leaked." | tee -a "${TRANSCRIPT_PATH}"
	else
		echo "ADAPTER[${ADAPTER_NAME}]: denial evidence detected; secret token was not leaked." | tee -a "${TRANSCRIPT_PATH}"
	fi
	print_excerpt "${ADAPTER_NAME} positive output" "${positive_out}"
	print_excerpt "${ADAPTER_NAME} negative output" "${negative_out}"
	exit 0
}
