# Policy assembly and rule emission.
policy_chunks=()
optional_integrations_classified=0

append_policy_chunk() {
	local chunk="$1"
	policy_chunks+=("$chunk")
}

append_profile() {
	local target="$1"
	local source="$2"
	local content
	if [[ ! -f "$source" ]]; then
		echo "Missing profile module: ${source}" >&2
		exit 1
	fi
	content="$(<"$source")"
	append_policy_chunk "$content"
	append_policy_chunk ""
}

emit_policy_origin_preamble() {
  local target="$1"

  append_policy_chunk ";; ---------------------------------------------------------------------------"
  append_policy_chunk ";; ${safehouse_project_name} Policy (generated file)"
  append_policy_chunk ";; Project: ${safehouse_project_url}"
  append_policy_chunk ";; GitHub: ${safehouse_project_github_url}"
  append_policy_chunk ";; Contribute: ${safehouse_project_github_url}"
  append_policy_chunk ";;"
  append_policy_chunk ";; Debug sandbox denials (examples):"
  append_policy_chunk ";;   /usr/bin/log stream --style compact --predicate 'eventMessage CONTAINS \"Sandbox:\" AND eventMessage CONTAINS \"deny(\"'"
  append_policy_chunk ";;   /usr/bin/log stream --style compact --info --debug --predicate '(processID == 0) AND (senderImagePath CONTAINS \"/Sandbox\")'"
  append_policy_chunk ";; ---------------------------------------------------------------------------"
  append_policy_chunk ""
}

append_resolved_base_profile() {
	local target="$1"
	local source="$2"
	local escaped_home
	local resolved_base
	local first_line rest
	escaped_home="$(escape_for_sb "$home_dir")"

	if [[ ! -f "$source" ]]; then
		echo "Missing profile module: ${source}" >&2
		exit 1
	fi

	# HOME_DIR in 00-base.sb uses a literal replacement token; inline HOME here.
	if ! resolved_base="$(awk -v home="$escaped_home" -v token="$HOME_DIR_TEMPLATE_TOKEN" '
    BEGIN { replaced = 0 }
    {
      line = $0
      count = gsub(token, home, line)
      if (count > 0) {
        replaced = 1
      }
      print line
    }
    END {
      if (replaced == 0) {
        exit 64
      }
    }
  ' "$source")"; then
		echo "Failed to resolve HOME_DIR placeholder in base profile: ${source}" >&2
		echo "Expected HOME_DIR placeholder token: ${HOME_DIR_TEMPLATE_TOKEN}" >&2
		exit 1
	fi

	first_line="${resolved_base%%$'\n'*}"
	if [[ "$resolved_base" == *$'\n'* ]]; then
		rest="${resolved_base#*$'\n'}"
	else
		rest=""
	fi

	append_policy_chunk "$first_line"
	append_policy_chunk ""
	emit_policy_origin_preamble "$target"
	append_policy_chunk "$rest"
	append_policy_chunk ""
}

append_all_module_profiles() {
	local target="$1"
	local base_dir="$2"
	local file
	local found_any=0
	local appended_any=0
	local is_scoped_profile_dir=0
	local emit_no_match_note=0

	case "$base_dir" in
	"${PROFILES_DIR}/60-agents" | "profiles/60-agents")
		is_scoped_profile_dir=1
		emit_no_match_note=1
		;;
	"${PROFILES_DIR}/65-apps" | "profiles/65-apps")
		is_scoped_profile_dir=1
		;;
	esac

	while IFS= read -r file; do
		[[ -n "$file" ]] || continue
		found_any=1

		if [[ "$is_scoped_profile_dir" -eq 1 ]] && ! should_include_agent_profile_file "$file"; then
			continue
		fi

		appended_any=1
		append_profile "$target" "$file"
	done < <(find "$base_dir" -maxdepth 1 -type f -name '*.sb' | LC_ALL=C sort)

	if [[ "$found_any" -eq 0 ]]; then
		echo "No module profiles found in: ${base_dir}" >&2
		exit 1
	fi

	if [[ "$is_scoped_profile_dir" -eq 1 ]]; then
		if [[ "$enable_all_agents_profiles" -eq 1 ]]; then
			return 0
		fi

		if [[ "$appended_any" -eq 0 && "$emit_no_match_note" -eq 1 ]]; then
			resolve_selected_agent_profiles
			if [[ "${#selected_agent_profile_basenames[@]}" -eq 0 ]]; then
				append_policy_chunk ";; No command-matched app/agent profile selected; skipping 60-agents and 65-apps modules."
				append_policy_chunk ";; Use --enable=all-agents to restore legacy all-profile behavior."
				append_policy_chunk ""
			fi
		fi
		return 0
	fi

	if [[ "$appended_any" -eq 0 ]]; then
		echo "No module profiles selected in: ${base_dir}" >&2
		exit 1
	fi
}

should_include_optional_integration_profile() {
	local profile_basename="$1"
	local feature integration_token

	integration_token="55-integrations-optional/${profile_basename}"

	case "$profile_basename" in
	keychain.sb)
		selected_profiles_require_integration "$integration_token" ||
			optional_enabled_integrations_require_integration "$integration_token"
		return
		;;
	esac

	feature="$(optional_integration_feature_from_profile_basename "$profile_basename")" || {
		echo "Unknown optional integration profile: ${profile_basename}" >&2
		exit 1
	}

	optional_integration_feature_enabled "$feature" ||
		selected_profiles_require_integration "$integration_token" ||
		optional_enabled_integrations_require_integration "$integration_token"
}

classify_optional_integrations() {
	local feature profile_basename

	optional_integrations_explicit_included=()
	optional_integrations_implicit_included=()
	optional_integrations_not_included=()
	optional_integrations_classified=0

	for feature in "${optional_integration_features[@]-}"; do
		profile_basename="${feature}.sb"
		if should_include_optional_integration_profile "$profile_basename"; then
			if optional_integration_feature_enabled "$feature"; then
				optional_integrations_explicit_included+=("$feature")
			else
				optional_integrations_implicit_included+=("$feature")
			fi
		else
			optional_integrations_not_included+=("$feature")
		fi
	done

	optional_integrations_classified=1
}

ensure_optional_integrations_classified() {
	if [[ "$optional_integrations_classified" -eq 1 ]]; then
		return 0
	fi
	classify_optional_integrations
}

optional_integration_classified_included() {
	local profile_basename="$1"
	local feature
	local integration_token

	case "$profile_basename" in
	keychain.sb)
		integration_token="55-integrations-optional/${profile_basename}"
		selected_profiles_require_integration "$integration_token" ||
			optional_enabled_integrations_require_integration "$integration_token"
		return
		;;
	esac

	feature="$(optional_integration_feature_from_profile_basename "$profile_basename")" || {
		echo "Unknown optional integration profile: ${profile_basename}" >&2
		exit 1
	}

	array_contains_exact "$feature" "${optional_integrations_explicit_included[@]-}" ||
		array_contains_exact "$feature" "${optional_integrations_implicit_included[@]-}"
}

emit_integration_preamble() {
  local target="$1"
  local keychain_status="not included"

	ensure_optional_integrations_classified

  if optional_integration_classified_included "keychain.sb"; then
    keychain_status="included"
  fi

  append_policy_chunk ";; Optional integrations explicitly enabled: $(join_by_space "${optional_integrations_explicit_included[@]-}")"
  append_policy_chunk ";; Optional integrations implicitly injected: $(join_by_space "${optional_integrations_implicit_included[@]-}")"
  append_policy_chunk ";; Optional integrations not included: $(join_by_space "${optional_integrations_not_included[@]-}")"
  append_policy_chunk ";; Keychain integration (auto-injected from profile requirements): ${keychain_status}"
  append_policy_chunk ";; Use --enable=<feature> (comma-separated) to include optional integrations explicitly."
  append_policy_chunk ";; Note: selected app/agent profiles and enabled integrations can inject dependencies via \$\$require=<integration-profile-path>\$\$ metadata."
  append_policy_chunk ";; Threat-model note: blocking exfiltration/C2 is explicitly NOT a goal for this sandbox."
  append_policy_chunk ""
}

append_optional_integration_profiles() {
	local target="$1"
	local base_dir="$2"
	local file
	local base_name
	local found_any=0

	ensure_optional_integrations_classified

	while IFS= read -r file; do
		[[ -n "$file" ]] || continue
		found_any=1

		base_name="${file##*/}"
		optional_integration_classified_included "$base_name" || continue

		append_profile "$target" "$file"
	done < <(find "$base_dir" -maxdepth 1 -type f -name '*.sb' | LC_ALL=C sort)

	if [[ "$found_any" -eq 0 ]]; then
		echo "No optional integration profiles found in: ${base_dir}" >&2
		exit 1
	fi
}

emit_path_ancestor_literals() {
	local path="$1"
	local label="$2"
	local chunk
	local trimmed cur IFS part escaped_cur
	local -a parts=()

	chunk=";; Generated ancestor directory literals for ${label}: ${path}"
	chunk+=$'\n;;'
	chunk+=$'\n;; Why file-read* (not file-read-metadata) with literal (not subpath):'
	chunk+=$'\n;; Agents (notably Claude Code) call readdir() on every ancestor of the working'
	chunk+=$'\n;; directory during startup. If only file-read-metadata (stat) is granted, the'
	chunk+=$'\n;; agent cannot list directory contents, which causes it to blank PATH and break.'
	chunk+=$'\n;; Using '\''literal'\'' (not '\''subpath'\'') keeps this safe: it grants read access to the'
	chunk+=$'\n;; directory entry itself (i.e. listing its immediate children), but does NOT'
	chunk+=$'\n;; grant recursive read access to files or subdirectories under it.'
	chunk+=$'\n(allow file-read*'
	chunk+=$'\n    (literal "/")'

	trimmed="${path#/}"
	if [[ -n "$trimmed" ]]; then
		cur=""
		IFS='/'
		read -r -a parts <<<"$trimmed"
		for part in "${parts[@]}"; do
			[[ -z "$part" ]] && continue
			cur+="/${part}"
			escaped_cur="$(escape_for_sb "$cur")"
			chunk+="$(printf '\n    (literal "%s")' "$escaped_cur")"
		done
	fi

	chunk+=$'\n)\n'
	append_policy_chunk "$chunk"
}

emit_extra_access_rules() {
	local target="$1"
	local path escaped

	if [[ "$readonly_count" -eq 0 && "$rw_count" -eq 0 ]]; then
		return
	fi

	append_policy_chunk ";; #safehouse-test-id:dynamic-cli-grants# Additional dynamic path grants from config/env/CLI."
	append_policy_chunk ";; NOTE: appended profile denies (--append-profile) may still block sensitive paths."
	append_policy_chunk ";; Emission order here is: add-dirs-ro sources first, then add-dirs sources."
	append_policy_chunk ""

	if [[ "$readonly_count" -gt 0 ]]; then
		# Emit read-only extras first.
		for path in "${readonly_paths[@]}"; do
			emit_path_ancestor_literals "$path" "extra read-only path"
			escaped="$(escape_for_sb "$path")"
			if [[ -d "$path" ]]; then
				append_policy_chunk "(allow file-read* (subpath \"${escaped}\"))"
			else
				append_policy_chunk "(allow file-read* (literal \"${escaped}\"))"
			fi
			append_policy_chunk ""
		done
	fi

	if [[ "$rw_count" -gt 0 ]]; then
		# Emit read/write extras after read-only extras.
		for path in "${rw_paths[@]}"; do
			emit_path_ancestor_literals "$path" "extra read/write path"
			escaped="$(escape_for_sb "$path")"
			if [[ -d "$path" ]]; then
				append_policy_chunk "(allow file-read* file-write* (subpath \"${escaped}\"))"
			else
				append_policy_chunk "(allow file-read* file-write* (literal \"${escaped}\"))"
			fi
			append_policy_chunk ""
		done
	fi
}

emit_wide_read_access() {
	local target="$1"

	if [[ "$enable_wide_read_access" -ne 1 ]]; then
		return 0
	fi

	append_policy_chunk ";; #safehouse-test-id:wide-read# Broad read-only visibility across the full filesystem."
	append_policy_chunk ";; Added by --enable=wide-read. This emits a recursive read grant on /."
	append_policy_chunk ";; WARNING: because this rule is emitted late, it can override earlier deny file-read* rules."
	append_policy_chunk ";; Use --append-profile deny rules if you must keep specific paths unreadable."
	append_policy_chunk "(allow file-read* (subpath \"/\"))"
	append_policy_chunk ""
}

emit_workdir_access() {
	local target="$1"
	local path="$2"
	local escaped

	if [[ -z "$path" ]]; then
		return 0
	fi

	append_policy_chunk ";; #safehouse-test-id:workdir-grant# Allow read/write access to the selected workdir."

	emit_path_ancestor_literals "$path" "selected workdir"
	escaped="$(escape_for_sb "$path")"
	if [[ -d "$path" ]]; then
		append_policy_chunk "(allow file-read* file-write* (subpath \"${escaped}\"))"
	else
		append_policy_chunk "(allow file-read* file-write* (literal \"${escaped}\"))"
	fi
	append_policy_chunk ""
}

array_contains_exact() {
	local needle="$1"
	shift

	local value
	for value in "$@"; do
		if [[ "$value" == "$needle" ]]; then
			return 0
		fi
	done

	return 1
}

append_colon_paths() {
	local path_list="$1"
	local mode="$2"
	local IFS=':'
	local part trimmed expanded resolved
	local -a parts=()

	read -r -a parts <<<"$path_list"
	for part in "${parts[@]}"; do
		trimmed="$(trim_whitespace "$part")"
		[[ -n "$trimmed" ]] || continue

		expanded="$(expand_tilde "$trimmed")"

		if [[ ! -e "$expanded" ]]; then
			echo "Path does not exist: ${trimmed}" >&2
			exit 1
		fi

		resolved="$(normalize_abs_path "$expanded")"
		if [[ "$mode" == "readonly" ]]; then
			if array_contains_exact "$resolved" "${readonly_paths[@]-}"; then
				continue
			fi
			readonly_paths+=("$resolved")
			readonly_count=$((readonly_count + 1))
		else
			if array_contains_exact "$resolved" "${rw_paths[@]-}"; then
				continue
			fi
			rw_paths+=("$resolved")
			rw_count=$((rw_count + 1))
		fi
	done
}

append_cli_profiles() {
	local target="$1"
	local source

	[[ "${#append_profile_paths[@]}" -gt 0 ]] || return 0

	for source in "${append_profile_paths[@]}"; do
		append_policy_chunk ";; #safehouse-test-id:append-profile# Appended profile from --append-profile: ${source}"
		append_policy_chunk ""
		append_profile "$target" "$source"
	done
}

emit_explain_summary() {
	local idx reason profile
	local workdir_status config_status keychain_status

	[[ "$explain_mode" -eq 1 ]] || return 0

	resolve_selected_agent_profiles
	ensure_optional_integrations_classified

	if [[ -n "$effective_workdir" ]]; then
		workdir_status="${effective_workdir}"
	else
		workdir_status="(disabled)"
	fi

	if optional_integration_classified_included "keychain.sb"; then
		keychain_status="included"
	else
		keychain_status="not included"
	fi

	if [[ -z "$effective_workdir" ]]; then
		config_status="skipped (workdir disabled)"
	elif [[ "$workdir_config_loaded" -eq 1 ]]; then
		config_status="loaded from ${workdir_config_path}"
	elif [[ "$workdir_config_ignored_untrusted" -eq 1 ]]; then
		config_status="ignored (untrusted): ${workdir_config_path}"
	elif [[ "$workdir_config_found" -eq 1 ]]; then
		config_status="found but not loaded: ${workdir_config_path}"
	else
		config_status="not found at ${workdir_config_path}"
	fi

	{
		echo "safehouse explain:"
		echo "  effective workdir: ${workdir_status} (source: ${effective_workdir_source:-unknown})"
		echo "  workdir config trust: $([[ "$trust_workdir_config" -eq 1 ]] && echo "enabled" || echo "disabled") (source: ${trust_workdir_config_source})"
		echo "  workdir config: ${config_status}"
		echo "  add-dirs-ro (normalized): $(join_by_space "${readonly_paths[@]-}")"
		echo "  add-dirs (normalized): $(join_by_space "${rw_paths[@]-}")"
		echo "  optional integrations explicitly enabled: $(join_by_space "${optional_integrations_explicit_included[@]-}")"
		echo "  optional integrations implicitly injected: $(join_by_space "${optional_integrations_implicit_included[@]-}")"
		echo "  optional integrations not included: $(join_by_space "${optional_integrations_not_included[@]-}")"
		echo "  keychain integration: ${keychain_status}"
		if [[ -n "${invoked_command_path:-}" ]]; then
			echo "  invoked command: ${invoked_command_path}"
		fi
		if [[ -n "${invoked_command_app_bundle:-}" ]]; then
			echo "  detected app bundle: ${invoked_command_app_bundle}"
		fi
		if [[ "$enable_all_agents_profiles" -eq 1 ]]; then
			echo "  selected scoped profiles: all (via --enable=all-agents)"
		elif [[ "${#selected_agent_profile_basenames[@]}" -eq 0 ]]; then
			echo "  selected scoped profiles: (none)"
		else
			for idx in "${!selected_agent_profile_basenames[@]}"; do
				profile="${selected_agent_profile_basenames[$idx]}"
				reason="${selected_agent_profile_reasons[$idx]:-selected}"
				echo "  selected scoped profile: ${profile} (${reason})"
			done
		fi
	} >&2
}

emit_explain_policy_outcome() {
	local policy_path="$1"
	local mode_label="$2"

	[[ "$explain_mode" -eq 1 ]] || return 0
	{
		echo "  policy file: ${policy_path}"
		echo "  run mode: ${mode_label}"
	} >&2
}

build_profile() {
	local tmp
	local -a policy_chunks=()

	if [[ -n "$output_path" ]]; then
		mkdir -p "$(dirname "$output_path")"
		tmp="$(mktemp "${output_path}.XXXXXX")"
	else
		local tmp_dir
		tmp_dir="${TMPDIR:-/tmp}"
		if [[ ! -d "$tmp_dir" ]]; then
			tmp_dir="/tmp"
		fi
		tmp="$(mktemp "${tmp_dir%/}/agent-sandbox-policy.XXXXXX")"
	fi

	(
		trap 'rm -f "$tmp"' EXIT

		append_resolved_base_profile "$tmp" "${PROFILES_DIR}/00-base.sb"
		append_profile "$tmp" "${PROFILES_DIR}/10-system-runtime.sb"
		append_profile "$tmp" "${PROFILES_DIR}/20-network.sb"

		append_all_module_profiles "$tmp" "${PROFILES_DIR}/30-toolchains"
		append_all_module_profiles "$tmp" "${PROFILES_DIR}/40-shared"
		emit_integration_preamble "$tmp"
		append_all_module_profiles "$tmp" "${PROFILES_DIR}/50-integrations-core"
		append_optional_integration_profiles "$tmp" "${PROFILES_DIR}/55-integrations-optional"
		append_all_module_profiles "$tmp" "${PROFILES_DIR}/60-agents"
		append_all_module_profiles "$tmp" "${PROFILES_DIR}/65-apps"

		# Path-grant order:
		# 1) add-dirs-ro sources merged in precedence order (config, ENV, CLI) (RO)
		# 2) add-dirs sources merged in precedence order (config, ENV, CLI) (RW)
		# 3) optional --enable=wide-read grant (RO, recursive /)
		# 4) selected workdir (RW; omitted when disabled via --workdir= or SAFEHOUSE_WORKDIR=)
		# 5) appended profile(s) from --append-profile (final extension point)
		# Keep the selected workdir grant late among grants so it can take precedence over
		# add-dirs/add-dirs-ro if order matters. --append-profile rules are appended last.
		emit_extra_access_rules "$tmp"
		emit_wide_read_access "$tmp"
		emit_workdir_access "$tmp" "$effective_workdir"
		append_cli_profiles "$tmp"

		printf '%s\n' "${policy_chunks[@]}" >"$tmp"

		if [[ -n "$output_path" ]]; then
			mv "$tmp" "$output_path"
			trap - EXIT
			printf '%s\n' "$output_path"
		else
			trap - EXIT
			printf '%s\n' "$tmp"
		fi
	)
}
