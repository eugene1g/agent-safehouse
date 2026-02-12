# Policy option/config parsing helpers and feature toggle handling.

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

is_truthy_value() {
  local value
  value="$(to_lowercase "$(trim_whitespace "${1:-}")")"
  case "$value" in
    1|true|yes|on)
      return 0
      ;;
  esac
  return 1
}

is_falsey_value() {
  local value
  value="$(to_lowercase "$(trim_whitespace "${1:-}")")"
  case "$value" in
    0|false|no|off|"")
      return 0
      ;;
  esac
  return 1
}

join_by_space() {
  local -a values=("$@")
  if [[ "${#values[@]}" -eq 0 ]]; then
    printf '%s\n' "(none)"
    return 0
  fi
  if [[ "${#values[@]}" -eq 1 && -z "${values[0]}" ]]; then
    printf '%s\n' "(none)"
    return 0
  fi
  printf '%s\n' "${values[*]}"
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

    if [[ "$trimmed" == "onepassword" ]]; then
      trimmed="1password"
    fi

    if is_known_optional_integration_feature "$trimmed"; then
      set_optional_integration_feature_enabled "$trimmed"
      continue
    fi

    case "$trimmed" in
      all-agents)
        enable_all_agents_profiles=1
        ;;
      wide-read)
        enable_wide_read_access=1
        ;;
      *)
        echo "Unknown feature in --enable: ${trimmed}" >&2
        echo "Supported features: ${supported_enable_features}" >&2
        exit 1
        ;;
    esac
  done
}

optional_integration_feature_flag_var() {
  local feature="$1"
  local normalized

  case "$feature" in
    1password)
      printf '%s\n' "enable_onepassword_integration"
      return 0
      ;;
    "")
      return 1
      ;;
  esac

  normalized="${feature//-/_}"
  printf 'enable_%s_integration\n' "$normalized"
}

set_optional_integration_feature_enabled() {
  local feature="$1"
  local var_name

  var_name="$(optional_integration_feature_flag_var "$feature")" || return 1
  printf -v "$var_name" '%s' "1"
}

optional_integration_feature_enabled() {
  local feature="$1"
  local var_name

  var_name="$(optional_integration_feature_flag_var "$feature")" || return 1
  [[ "${!var_name:-0}" -eq 1 ]]
}

is_known_optional_integration_feature() {
  local candidate="$1"
  local feature

  for feature in "${optional_integration_features[@]-}"; do
    if [[ "$feature" == "$candidate" ]]; then
      return 0
    fi
  done

  return 1
}

optional_integration_feature_from_profile_basename() {
  local profile_basename="$1"
  local feature

  [[ "$profile_basename" == *.sb ]] || return 1
  feature="${profile_basename%.sb}"

  if is_known_optional_integration_feature "$feature"; then
    printf '%s\n' "$feature"
    return 0
  fi

  return 1
}

optional_integration_profile_path_from_feature() {
  local feature="$1"

  if ! is_known_optional_integration_feature "$feature"; then
    return 1
  fi

  printf '%s/55-integrations-optional/%s.sb\n' "$PROFILES_DIR" "$feature"
}

optional_enabled_integrations_require_integration() {
  local integration="$1"
  local feature profile_path

  for feature in "${optional_integration_features[@]-}"; do
    optional_integration_feature_enabled "$feature" || continue

    profile_path="$(optional_integration_profile_path_from_feature "$feature")" || continue
    if profile_declares_requirement "$profile_path" "$integration"; then
      return 0
    fi
  done

  return 1
}
