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
      *)
        echo "Unknown feature in --enable: ${trimmed}" >&2
        echo "Supported features: docker, macos-gui, electron" >&2
        exit 1
        ;;
    esac
  done
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
  for file in "${base_dir}"/*.sb; do
    [[ -e "$file" ]] || continue
    found_any=1
    append_profile "$target" "$file"
  done

  if [[ "$found_any" -eq 0 ]]; then
    echo "No module profiles found in: ${base_dir}" >&2
    exit 1
  fi
}

append_integration_profiles() {
  local target="$1"
  local base_dir="$2"
  local file
  local found_any=0
  local added_any=0

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

  for file in "${base_dir}"/*.sb; do
    [[ -e "$file" ]] || continue
    found_any=1

    local base_name
    base_name="$(basename "$file")"
    if [[ "$base_name" == "docker.sb" && "$enable_docker_integration" -ne 1 ]]; then
      continue
    fi
    if [[ "$base_name" == "macos-gui.sb" && "$enable_macos_gui_integration" -ne 1 ]]; then
      continue
    fi
    if [[ "$base_name" == "electron.sb" && "$enable_electron_integration" -ne 1 ]]; then
      continue
    fi

    added_any=1
    append_profile "$target" "$file"
  done

  if [[ "$found_any" -eq 0 ]]; then
    echo "No integration profiles found in: ${base_dir}" >&2
    exit 1
  fi

  if [[ "$added_any" -eq 0 ]]; then
    echo "No enabled integration profiles found in: ${base_dir}" >&2
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
  local part trimmed resolved
  local -a parts=()

  read -r -a parts <<< "$path_list"
  for part in "${parts[@]}"; do
    trimmed="$(trim_whitespace "$part")"
    [[ -n "$trimmed" ]] || continue

    if [[ ! -e "$trimmed" ]]; then
      echo "Path does not exist: ${trimmed}" >&2
      exit 1
    fi

    resolved="$(normalize_abs_path "$trimmed")"
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
  append_all_module_profiles "$tmp" "${PROFILES_DIR}/40-agents"
  append_integration_profiles "$tmp" "${PROFILES_DIR}/50-integrations"

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

  if [[ ! -d "$invocation_cwd" ]]; then
    echo "Invocation CWD does not exist or is not a directory: $invocation_cwd" >&2
    exit 1
  fi

  if [[ "${#append_profile_paths[@]}" -gt 0 ]]; then
    local raw_profile_path resolved_profile_path
    local -a normalized_append_profile_paths=()

    for raw_profile_path in "${append_profile_paths[@]}"; do
      if [[ -z "$raw_profile_path" ]]; then
        echo "Appended profile path cannot be empty." >&2
        exit 1
      fi
      if [[ ! -e "$raw_profile_path" ]]; then
        echo "Appended profile path does not exist: ${raw_profile_path}" >&2
        exit 1
      fi
      if [[ ! -f "$raw_profile_path" ]]; then
        echo "Appended profile path is not a regular file: ${raw_profile_path}" >&2
        exit 1
      fi
      if [[ ! -r "$raw_profile_path" ]]; then
        echo "Appended profile file is not readable: ${raw_profile_path}" >&2
        exit 1
      fi

      resolved_profile_path="$(normalize_abs_path "$raw_profile_path")"
      normalized_append_profile_paths+=("$resolved_profile_path")
    done

    append_profile_paths=("${normalized_append_profile_paths[@]}")
  fi

  home_dir="$(normalize_abs_path "$home_dir")"

  if [[ "$workdir_flag_set" -eq 1 ]]; then
    if [[ -n "$workdir_value" ]]; then
      if [[ ! -d "$workdir_value" ]]; then
        echo "Workdir does not exist or is not a directory: $workdir_value" >&2
        exit 1
      fi
      effective_workdir="$(normalize_abs_path "$workdir_value")"
    else
      effective_workdir=""
    fi
  elif [[ "$workdir_env_set" -eq 1 ]]; then
    if [[ -n "$workdir_env_value" ]]; then
      if [[ ! -d "$workdir_env_value" ]]; then
        echo "Workdir from SAFEHOUSE_WORKDIR does not exist or is not a directory: $workdir_env_value" >&2
        exit 1
      fi
      effective_workdir="$(normalize_abs_path "$workdir_env_value")"
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
