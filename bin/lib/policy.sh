load_workdir_config() {
  local config_path="$1"
  local line trimmed key raw_value value
  local line_number=0

  [[ -f "$config_path" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    trimmed="$(trim_whitespace "$line")"
    [[ -n "$trimmed" ]] || continue
    if [[ "${trimmed:0:1}" == "#" || "${trimmed:0:1}" == ";" ]]; then
      continue
    fi

    if [[ "$trimmed" != *=* ]]; then
      echo "Invalid config line in ${config_path}:${line_number}: expected key=value" >&2
      exit 1
    fi

    key="$(trim_whitespace "${trimmed%%=*}")"
    raw_value="${trimmed#*=}"
    value="$(trim_whitespace "$raw_value")"
    value="$(strip_matching_quotes "$value")"

    case "$key" in
      add-dirs-ro|add_dirs_ro|SAFEHOUSE_ADD_DIRS_RO)
        config_add_dirs_ro_list="$(append_colon_list "$config_add_dirs_ro_list" "$value")"
        ;;
      add-dirs|add_dirs|SAFEHOUSE_ADD_DIRS)
        config_add_dirs_list="$(append_colon_list "$config_add_dirs_list" "$value")"
        ;;
      *)
        # Ignore unknown keys to keep config compatibility simple/forwards-safe.
        ;;
    esac
  done < "$config_path"
}

append_csv_values() {
  local csv="$1"
  local IFS=','
  local value trimmed
  local -a values=()

  read -r -a values <<< "$csv"
  for value in "${values[@]}"; do
    trimmed="$(trim_whitespace "$value")"
    [[ -n "$trimmed" ]] || continue

    if [[ -n "$enable_csv_list" ]]; then
      enable_csv_list+=",${trimmed}"
    else
      enable_csv_list="${trimmed}"
    fi
  done
}

parse_enabled_features() {
  local csv="$1"
  local IFS=','
  local value trimmed
  local -a values=()

  [[ -n "$csv" ]] || return 0

  read -r -a values <<< "$csv"
  for value in "${values[@]}"; do
    trimmed="$(trim_whitespace "$value")"
    [[ -n "$trimmed" ]] || continue

    case "$trimmed" in
      docker)
        enable_docker_integration=1
        ;;
      macos-gui)
        enable_macos_gui_integration=1
        ;;
      electron)
        enable_electron_integration=1
        enable_macos_gui_integration=1
        ;;
      all-agents)
        enable_all_agents_profiles=1
        ;;
      *)
        echo "Unknown feature in --enable: ${trimmed}" >&2
        echo "Supported features: docker, macos-gui, electron, all-agents" >&2
        exit 1
        ;;
    esac
  done
}

append_selected_agent_profile() {
  local candidate="$1"
  local selected

  for selected in "${selected_agent_profile_basenames[@]-}"; do
    if [[ "$selected" == "$candidate" ]]; then
      return 0
    fi
  done

  selected_agent_profile_basenames+=("$candidate")
}

resolve_selected_agent_profiles() {
  local cmd app_bundle_base

  if [[ "$selected_agent_profiles_resolved" -eq 1 ]]; then
    return 0
  fi
  selected_agent_profiles_resolved=1
  selected_agent_profile_basenames=()

  if [[ "$enable_all_agents_profiles" -eq 1 ]]; then
    return 0
  fi

  cmd="$(to_lowercase "${invoked_command_basename:-}")"
  app_bundle_base="$(to_lowercase "$(basename "${invoked_command_app_bundle:-}")")"

  if [[ "$app_bundle_base" == "claude.app" ]]; then
    append_selected_agent_profile "claude-app.sb"
  fi

  case "$cmd" in
    aider)
      append_selected_agent_profile "aider.sb"
      ;;
    amp)
      append_selected_agent_profile "amp.sb"
      ;;
    auggie)
      append_selected_agent_profile "auggie.sb"
      ;;
    claude)
      if [[ "$app_bundle_base" != "claude.app" ]]; then
        append_selected_agent_profile "claude-code.sb"
      fi
      ;;
    claude-code)
      append_selected_agent_profile "claude-code.sb"
      ;;
    cline)
      append_selected_agent_profile "cline.sb"
      ;;
    codex)
      append_selected_agent_profile "codex.sb"
      ;;
    cursor|cursor-agent|agent)
      append_selected_agent_profile "cursor-agent.sb"
      ;;
    droid)
      append_selected_agent_profile "droid.sb"
      ;;
    gemini)
      append_selected_agent_profile "gemini.sb"
      ;;
    opencode)
      append_selected_agent_profile "opencode.sb"
      ;;
    pi)
      append_selected_agent_profile "pi.sb"
      ;;
  esac
}

should_include_agent_profile_file() {
  local file_path="$1"
  local selected_profile base_name

  if [[ "$enable_all_agents_profiles" -eq 1 ]]; then
    return 0
  fi

  resolve_selected_agent_profiles
  base_name="$(basename "$file_path")"

  for selected_profile in "${selected_agent_profile_basenames[@]-}"; do
    if [[ "$selected_profile" == "$base_name" ]]; then
      return 0
    fi
  done

  return 1
}

append_profile() {
  local target="$1"
  local source="$2"
  if [[ ! -f "$source" ]]; then
    echo "Missing profile module: ${source}" >&2
    exit 1
  fi
  cat "$source" >> "$target"
  echo "" >> "$target"
}

append_resolved_base_profile() {
  local target="$1"
  local source="$2"
  local escaped_home
  escaped_home="$(escape_for_sb "$home_dir")"

  if [[ ! -f "$source" ]]; then
    echo "Missing profile module: ${source}" >&2
    exit 1
  fi

  # HOME_DIR in 00-base.sb uses a literal replacement token; inline HOME here.
  awk -v home="$escaped_home" -v token="$HOME_DIR_TEMPLATE_TOKEN" '
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
  ' "$source" >> "$target" || {
    echo "Failed to resolve HOME_DIR placeholder in base profile: ${source}" >&2
    echo "Expected HOME_DIR placeholder token: ${HOME_DIR_TEMPLATE_TOKEN}" >&2
    exit 1
  }
  echo "" >> "$target"
}

append_all_module_profiles() {
  local target="$1"
  local base_dir="$2"
  local file
  local found_any=0
  local appended_any=0
  local is_agent_dir=0

  case "$base_dir" in
    "${PROFILES_DIR}/60-agents"|"profiles/60-agents")
      is_agent_dir=1
      ;;
  esac

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    found_any=1

    if [[ "$is_agent_dir" -eq 1 ]] && ! should_include_agent_profile_file "$file"; then
      continue
    fi

    appended_any=1
    append_profile "$target" "$file"
  done < <(find "$base_dir" -maxdepth 1 -type f -name '*.sb' | LC_ALL=C sort)

  if [[ "$found_any" -eq 0 ]]; then
    echo "No module profiles found in: ${base_dir}" >&2
    exit 1
  fi

  if [[ "$is_agent_dir" -eq 1 ]]; then
    if [[ "$enable_all_agents_profiles" -eq 1 ]]; then
      return 0
    fi

    if [[ "$appended_any" -eq 0 ]]; then
      {
        echo ";; No command-matched agent profile selected; skipping 60-agents modules."
        echo ";; Use --enable=all-agents to restore legacy all-agent profile behavior."
        echo ""
      } >> "$target"
    fi
    return 0
  fi

  if [[ "$appended_any" -eq 0 ]]; then
    echo "No module profiles selected in: ${base_dir}" >&2
    exit 1
  fi
}

emit_integration_preamble() {
  local target="$1"

  local -a opt_in_integrations=()
  if [[ "$enable_docker_integration" -ne 1 ]]; then
    opt_in_integrations+=("docker")
  fi
  if [[ "$enable_macos_gui_integration" -ne 1 ]]; then
    opt_in_integrations+=("macos-gui")
  fi
  if [[ "$enable_electron_integration" -ne 1 ]]; then
    opt_in_integrations+=("electron")
  fi

  if [[ "${#opt_in_integrations[@]}" -gt 0 ]]; then
    echo ";; Opt-in integrations not enabled: ${opt_in_integrations[*]}" >> "$target"
    echo ";; Use --enable=<feature> (comma-separated) to include them." >> "$target"
    echo ";; Note: --enable=electron also enables macos-gui." >> "$target"
    echo "" >> "$target"
  fi

  echo ";; Threat-model note: blocking exfiltration/C2 is explicitly NOT a goal for this sandbox." >> "$target"
  echo "" >> "$target"
}

append_optional_integration_profiles() {
  local target="$1"
  local base_dir="$2"
  local file
  local found_any=0

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    found_any=1

    local base_name
    base_name="$(basename "$file")"
    case "$base_name" in
      docker.sb)
        [[ "$enable_docker_integration" -eq 1 ]] || continue
        ;;
      macos-gui.sb)
        [[ "$enable_macos_gui_integration" -eq 1 ]] || continue
        ;;
      electron.sb)
        [[ "$enable_electron_integration" -eq 1 ]] || continue
        ;;
      *)
        echo "Unknown optional integration profile: ${base_name}" >&2
        exit 1
        ;;
    esac

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

  {
    echo ";; Generated ancestor directory literals for ${label}: ${path}"
    echo ";;"
    echo ";; Why file-read* (not file-read-metadata) with literal (not subpath):"
    echo ";; Agents (notably Claude Code) call readdir() on every ancestor of the working"
    echo ";; directory during startup. If only file-read-metadata (stat) is granted, the"
    echo ";; agent cannot list directory contents, which causes it to blank PATH and break."
    echo ";; Using 'literal' (not 'subpath') keeps this safe: it grants read access to the"
    echo ";; directory entry itself (i.e. listing its immediate children), but does NOT"
    echo ";; grant recursive read access to files or subdirectories under it."
    echo "(allow file-read*"
    echo "    (literal \"/\")"

    local trimmed cur IFS part escaped_cur
    local -a parts=()
    trimmed="${path#/}"
    if [[ -n "$trimmed" ]]; then
      cur=""
      IFS='/'
      read -r -a parts <<< "$trimmed"
      for part in "${parts[@]}"; do
        [[ -z "$part" ]] && continue
        cur+="/${part}"
        escaped_cur="$(escape_for_sb "$cur")"
        echo "    (literal \"${escaped_cur}\")"
      done
    fi

    echo ")"
    echo ""
  }
}

emit_extra_access_rules() {
  local target="$1"
  local path escaped

  if [[ "$readonly_count" -eq 0 && "$rw_count" -eq 0 ]]; then
    return
  fi

  {
    echo ";; #safehouse-test-id:dynamic-cli-grants# Additional dynamic path grants from config/env/CLI."
    echo ";; NOTE: appended profile denies (--append-profile) may still block sensitive paths."
    echo ";; Emission order here is: add-dirs-ro sources first, then add-dirs sources."
    echo ""
  } >> "$target"

  if [[ "$readonly_count" -gt 0 ]]; then
    # Emit read-only extras first.
    for path in "${readonly_paths[@]}"; do
      emit_path_ancestor_literals "$path" "extra read-only path" >> "$target"
      escaped="$(escape_for_sb "$path")"
      if [[ -d "$path" ]]; then
        echo "(allow file-read* (subpath \"${escaped}\"))" >> "$target"
      else
        echo "(allow file-read* (literal \"${escaped}\"))" >> "$target"
      fi
      echo "" >> "$target"
    done
  fi

  if [[ "$rw_count" -gt 0 ]]; then
    # Emit read/write extras after read-only extras.
    for path in "${rw_paths[@]}"; do
      emit_path_ancestor_literals "$path" "extra read/write path" >> "$target"
      escaped="$(escape_for_sb "$path")"
      if [[ -d "$path" ]]; then
        echo "(allow file-read* file-write* (subpath \"${escaped}\"))" >> "$target"
      else
        echo "(allow file-read* file-write* (literal \"${escaped}\"))" >> "$target"
      fi
      echo "" >> "$target"
    done
  fi
}

emit_workdir_access() {
  local target="$1"
  local path="$2"
  local escaped

  if [[ -z "$path" ]]; then
    return 0
  fi

  {
    echo ";; #safehouse-test-id:workdir-grant# Allow read/write access to the selected workdir."
  } >> "$target"

  emit_path_ancestor_literals "$path" "selected workdir" >> "$target"
  escaped="$(escape_for_sb "$path")"
  if [[ -d "$path" ]]; then
    echo "(allow file-read* file-write* (subpath \"${escaped}\"))" >> "$target"
  else
    echo "(allow file-read* file-write* (literal \"${escaped}\"))" >> "$target"
  fi
  echo "" >> "$target"
}

append_colon_paths() {
  local path_list="$1"
  local mode="$2"
  local IFS=':'
  local part trimmed expanded resolved
  local -a parts=()

  read -r -a parts <<< "$path_list"
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
      readonly_paths+=("$resolved")
      readonly_count=$((readonly_count + 1))
    else
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
    {
      echo ";; #safehouse-test-id:append-profile# Appended profile from --append-profile: ${source}"
      echo ""
    } >> "$target"
    append_profile "$target" "$source"
  done
}

build_profile() {
  local tmp

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

  # Path-grant order:
  # 1) add-dirs-ro sources merged in precedence order (config, ENV, CLI) (RO)
  # 2) add-dirs sources merged in precedence order (config, ENV, CLI) (RW)
  # 3) selected workdir (RW; omitted when disabled via --workdir= or SAFEHOUSE_WORKDIR=)
  # 4) appended profile(s) from --append-profile (final extension point)
  # Keep the selected workdir grant last among grants so it can take precedence over
  # add-dirs/add-dirs-ro if order matters. --append-profile rules are appended last.
  emit_extra_access_rules "$tmp"
  emit_workdir_access "$tmp" "$effective_workdir"
  append_cli_profiles "$tmp"

  if [[ -n "$output_path" ]]; then
    mv "$tmp" "$output_path"
    trap - EXIT
    printf '%s\n' "$output_path"
  else
    trap - EXIT
    printf '%s\n' "$tmp"
  fi
}

generate_policy_file() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --enable)
        [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
        append_csv_values "$2"
        shift 2
        ;;
      --enable=*)
        append_csv_values "${1#*=}"
        shift
        ;;
      --add-dirs-ro)
        [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
        if [[ -n "$add_dirs_ro_list_cli" ]]; then
          add_dirs_ro_list_cli+=":${2}"
        else
          add_dirs_ro_list_cli="$2"
        fi
        shift 2
        ;;
      --add-dirs-ro=*)
        if [[ -n "$add_dirs_ro_list_cli" ]]; then
          add_dirs_ro_list_cli+=":${1#*=}"
        else
          add_dirs_ro_list_cli="${1#*=}"
        fi
        shift
        ;;
      --add-dirs)
        [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
        if [[ -n "$add_dirs_list_cli" ]]; then
          add_dirs_list_cli+=":${2}"
        else
          add_dirs_list_cli="$2"
        fi
        shift 2
        ;;
      --add-dirs=*)
        if [[ -n "$add_dirs_list_cli" ]]; then
          add_dirs_list_cli+=":${1#*=}"
        else
          add_dirs_list_cli="${1#*=}"
        fi
        shift
        ;;
      --workdir)
        [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
        workdir_value="$2"
        workdir_flag_set=1
        shift 2
        ;;
      --workdir=*)
        workdir_value="${1#*=}"
        workdir_flag_set=1
        shift
        ;;
      --append-profile)
        [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
        append_profile_paths+=("$2")
        shift 2
        ;;
      --append-profile=*)
        append_profile_paths+=("${1#*=}")
        shift
        ;;
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

  if [[ -z "$home_dir" ]]; then
    echo "HOME is not set; set HOME in the environment before running this script." >&2
    exit 1
  fi

  if [[ ! -d "$home_dir" ]]; then
    echo "HOME does not exist or is not a directory: $home_dir" >&2
    exit 1
  fi

  home_dir="$(normalize_abs_path "$home_dir")"

  if [[ -n "$output_path" ]]; then
    output_path="$(expand_tilde "$output_path")"
  fi

  if [[ ! -d "$invocation_cwd" ]]; then
    echo "Invocation CWD does not exist or is not a directory: $invocation_cwd" >&2
    exit 1
  fi

  if [[ "${#append_profile_paths[@]}" -gt 0 ]]; then
    local raw_profile_path expanded_profile_path resolved_profile_path
    local -a normalized_append_profile_paths=()

    for raw_profile_path in "${append_profile_paths[@]}"; do
      if [[ -z "$raw_profile_path" ]]; then
        echo "Appended profile path cannot be empty." >&2
        exit 1
      fi
      expanded_profile_path="$(expand_tilde "$raw_profile_path")"
      if [[ ! -e "$expanded_profile_path" ]]; then
        echo "Appended profile path does not exist: ${raw_profile_path}" >&2
        exit 1
      fi
      if [[ ! -f "$expanded_profile_path" ]]; then
        echo "Appended profile path is not a regular file: ${raw_profile_path}" >&2
        exit 1
      fi
      if [[ ! -r "$expanded_profile_path" ]]; then
        echo "Appended profile file is not readable: ${raw_profile_path}" >&2
        exit 1
      fi

      resolved_profile_path="$(normalize_abs_path "$expanded_profile_path")"
      normalized_append_profile_paths+=("$resolved_profile_path")
    done

    append_profile_paths=("${normalized_append_profile_paths[@]}")
  fi

  if [[ "$workdir_flag_set" -eq 1 ]]; then
    if [[ -n "$workdir_value" ]]; then
      local resolved_workdir_value
      resolved_workdir_value="$(expand_tilde "$workdir_value")"
      if [[ ! -d "$resolved_workdir_value" ]]; then
        echo "Workdir does not exist or is not a directory: $workdir_value" >&2
        exit 1
      fi
      effective_workdir="$(normalize_abs_path "$resolved_workdir_value")"
    else
      effective_workdir=""
    fi
  elif [[ "$workdir_env_set" -eq 1 ]]; then
    if [[ -n "$workdir_env_value" ]]; then
      local resolved_workdir_env_value
      resolved_workdir_env_value="$(expand_tilde "$workdir_env_value")"
      if [[ ! -d "$resolved_workdir_env_value" ]]; then
        echo "Workdir from SAFEHOUSE_WORKDIR does not exist or is not a directory: $workdir_env_value" >&2
        exit 1
      fi
      effective_workdir="$(normalize_abs_path "$resolved_workdir_env_value")"
    else
      effective_workdir=""
    fi
  else
    effective_workdir="$(resolve_default_workdir "$invocation_cwd")"
  fi

  parse_enabled_features "$enable_csv_list"

  if [[ -n "$effective_workdir" ]]; then
    workdir_config_path="${effective_workdir%/}/${workdir_config_filename}"
    if [[ -e "$workdir_config_path" && ! -f "$workdir_config_path" ]]; then
      echo "Workdir config path exists but is not a regular file: $workdir_config_path" >&2
      exit 1
    fi
    if [[ -f "$workdir_config_path" && ! -r "$workdir_config_path" ]]; then
      echo "Workdir config file is not readable: $workdir_config_path" >&2
      exit 1
    fi
    load_workdir_config "$workdir_config_path"
  fi

  combined_add_dirs_ro_list="$(append_colon_list "$combined_add_dirs_ro_list" "$config_add_dirs_ro_list")"
  combined_add_dirs_ro_list="$(append_colon_list "$combined_add_dirs_ro_list" "$env_add_dirs_ro_list")"
  combined_add_dirs_ro_list="$(append_colon_list "$combined_add_dirs_ro_list" "$add_dirs_ro_list_cli")"

  combined_add_dirs_list="$(append_colon_list "$combined_add_dirs_list" "$config_add_dirs_list")"
  combined_add_dirs_list="$(append_colon_list "$combined_add_dirs_list" "$env_add_dirs_list")"
  combined_add_dirs_list="$(append_colon_list "$combined_add_dirs_list" "$add_dirs_list_cli")"

  if [[ -n "$combined_add_dirs_ro_list" ]]; then
    append_colon_paths "$combined_add_dirs_ro_list" "readonly"
  fi

  if [[ -n "$combined_add_dirs_list" ]]; then
    append_colon_paths "$combined_add_dirs_list" "rw"
  fi

  build_profile
}
