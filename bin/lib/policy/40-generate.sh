# Top-level policy generation flow.

validate_sb_input() {
  local label="$1"
  local value="$2"

  if [[ -z "$value" ]]; then
    echo "Missing or empty value for ${label}" >&2
    exit 1
  fi

  validate_sb_string "$value" "${label} value" || exit 1
}

validate_optional_sb_input() {
  local label="$1"
  local value="$2"

  [[ -n "$value" ]] || return 0
  validate_sb_string "$value" "${label} value" || exit 1
}

generate_policy_file() {
  optional_integrations_classified=0
  optional_integrations_explicit_included=()
  optional_integrations_implicit_included=()
  optional_integrations_not_included=()

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
        validate_sb_input "--add-dirs-ro" "$2"
        if [[ -n "$add_dirs_ro_list_cli" ]]; then
          add_dirs_ro_list_cli+=":${2}"
        else
          add_dirs_ro_list_cli="$2"
        fi
        shift 2
        ;;
      --add-dirs-ro=*)
        validate_sb_input "--add-dirs-ro" "${1#*=}"
        if [[ -n "$add_dirs_ro_list_cli" ]]; then
          add_dirs_ro_list_cli+=":${1#*=}"
        else
          add_dirs_ro_list_cli="${1#*=}"
        fi
        shift
        ;;
      --add-dirs)
        [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
        validate_sb_input "--add-dirs" "$2"
        if [[ -n "$add_dirs_list_cli" ]]; then
          add_dirs_list_cli+=":${2}"
        else
          add_dirs_list_cli="$2"
        fi
        shift 2
        ;;
      --add-dirs=*)
        validate_sb_input "--add-dirs" "${1#*=}"
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
        validate_optional_sb_input "--workdir" "$workdir_value"
        workdir_flag_set=1
        shift 2
        ;;
      --workdir=*)
        workdir_value="${1#*=}"
        validate_optional_sb_input "--workdir" "$workdir_value"
        workdir_flag_set=1
        shift
        ;;
      --trust-workdir-config)
        trust_workdir_config=1
        trust_workdir_config_flag_set=1
        trust_workdir_config_source="--trust-workdir-config"
        shift
        ;;
      --trust-workdir-config=*)
        if is_truthy_value "${1#*=}"; then
          trust_workdir_config=1
        elif is_falsey_value "${1#*=}"; then
          trust_workdir_config=0
        else
          echo "Invalid value for --trust-workdir-config: ${1#*=}" >&2
          echo "Supported values: 1/0, true/false, yes/no, on/off" >&2
          exit 1
        fi
        trust_workdir_config_flag_set=1
        trust_workdir_config_source="--trust-workdir-config"
        shift
        ;;
      --append-profile)
        [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
        validate_sb_input "--append-profile" "$2"
        append_profile_paths+=("$2")
        shift 2
        ;;
      --append-profile=*)
        validate_sb_input "--append-profile" "${1#*=}"
        append_profile_paths+=("${1#*=}")
        shift
        ;;
      --output)
        [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
        validate_sb_input "--output" "$2"
        output_path="$2"
        shift 2
        ;;
      --output=*)
        validate_sb_input "--output" "${1#*=}"
        output_path="${1#*=}"
        shift
        ;;
      --explain)
        explain_mode=1
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
    validate_sb_string "$output_path" "--output path" || exit 1
    output_path="$(expand_tilde "$output_path")"
  fi

  if [[ ! -d "$invocation_cwd" ]]; then
    echo "Invocation CWD does not exist or is not a directory: $invocation_cwd" >&2
    exit 1
  fi

  if [[ "$workdir_env_set" -eq 1 && -n "$workdir_env_value" ]]; then
    validate_sb_string "$workdir_env_value" "SAFEHOUSE_WORKDIR" || exit 1
  fi

  if [[ -n "$env_add_dirs_ro_list" ]]; then
    validate_sb_string "$env_add_dirs_ro_list" "SAFEHOUSE_ADD_DIRS_RO" || exit 1
  fi

  if [[ -n "$env_add_dirs_list" ]]; then
    validate_sb_string "$env_add_dirs_list" "SAFEHOUSE_ADD_DIRS" || exit 1
  fi

  if [[ "$trust_workdir_config_flag_set" -eq 0 ]]; then
    if [[ "$trust_workdir_config_env_set" -eq 1 ]]; then
      if is_truthy_value "$trust_workdir_config_env_value"; then
        trust_workdir_config=1
      elif is_falsey_value "$trust_workdir_config_env_value"; then
        trust_workdir_config=0
      else
        echo "Invalid SAFEHOUSE_TRUST_WORKDIR_CONFIG value: ${trust_workdir_config_env_value}" >&2
        echo "Supported values: 1/0, true/false, yes/no, on/off" >&2
        exit 1
      fi
      trust_workdir_config_source="SAFEHOUSE_TRUST_WORKDIR_CONFIG"
    else
      trust_workdir_config=0
      trust_workdir_config_source="default"
    fi
  fi

  if [[ "${#append_profile_paths[@]}" -gt 0 ]]; then
    local raw_profile_path expanded_profile_path resolved_profile_path
    local -a normalized_append_profile_paths=()

    for raw_profile_path in "${append_profile_paths[@]}"; do
      validate_sb_string "$raw_profile_path" "--append-profile path" || exit 1
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
      effective_workdir_source="--workdir"
    else
      effective_workdir=""
      effective_workdir_source="--workdir (disabled)"
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
      effective_workdir_source="SAFEHOUSE_WORKDIR"
    else
      effective_workdir=""
      effective_workdir_source="SAFEHOUSE_WORKDIR (disabled)"
    fi
  else
    effective_workdir="$(resolve_default_workdir "$invocation_cwd")"
  fi

  parse_enabled_features "$enable_csv_list"

  workdir_config_loaded=0
  workdir_config_found=0
  workdir_config_ignored_untrusted=0
  workdir_config_path=""
  if [[ -n "$effective_workdir" ]]; then
    workdir_config_path="${effective_workdir%/}/${workdir_config_filename}"
    if [[ "$trust_workdir_config" -eq 1 ]]; then
      if [[ -e "$workdir_config_path" && ! -f "$workdir_config_path" ]]; then
        echo "Workdir config path exists but is not a regular file: $workdir_config_path" >&2
        exit 1
      fi
      if [[ -f "$workdir_config_path" ]]; then
        workdir_config_found=1
        if [[ ! -r "$workdir_config_path" ]]; then
          echo "Workdir config file is not readable: $workdir_config_path" >&2
          exit 1
        fi
        load_workdir_config "$workdir_config_path"
        workdir_config_loaded=1
      fi
    else
      if [[ -e "$workdir_config_path" ]]; then
        workdir_config_found=1
        workdir_config_ignored_untrusted=1
      fi
    fi
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

  emit_explain_summary
  build_profile
}
