# shellcheck shell=bash
# shellcheck disable=SC2034

policy_optional_integration_features=()
policy_supported_enable_features=""
policy_feature_catalog_initialized=0
policy_supported_enable_synthetic_features=(
  all-agents
  all-apps
  wide-read
)
policy_keychain_requirement_token="55-integrations-optional/keychain.sb"
policy_embedded_optional_integration_features=()
policy_embedded_supported_enable_features=""

policy_value_is_truthy() {
  local value

  value="$(safehouse_to_lowercase "$(safehouse_trim_whitespace "${1:-}")")"
  case "$value" in
    1|true|yes|on)
      return 0
      ;;
  esac

  return 1
}

policy_value_is_falsey() {
  local value

  value="$(safehouse_to_lowercase "$(safehouse_trim_whitespace "${1:-}")")"
  case "$value" in
    0|false|no|off|"")
      return 0
      ;;
  esac

  return 1
}

policy_normalize_feature_name() {
  local candidate

  candidate="$(safehouse_to_lowercase "$(safehouse_trim_whitespace "$1")")"
  if [[ "$candidate" == "onepassword" ]]; then
    candidate="1password"
  fi

  printf '%s\n' "$candidate"
}

policy_optional_integration_feature_basename_from_profile_key() {
  local profile_key="$1"
  local feature

  case "$profile_key" in
    profiles/55-integrations-optional/*.sb)
      feature="${profile_key##*/}"
      feature="${feature%.sb}"
      printf '%s\n' "$feature"
      return 0
      ;;
  esac

  return 1
}

policy_optional_integration_feature_is_user_exposed() {
  local feature="$1"
  [[ -n "$feature" ]]
}

policy_build_supported_enable_features_csv() {
  local feature
  local supported_csv=""
  local need_separator=0

  for feature in "${policy_optional_integration_features[@]}"; do
    if [[ "$need_separator" -eq 1 ]]; then
      supported_csv+=", "
    fi
    supported_csv+="$feature"
    need_separator=1
  done

  for feature in "${policy_supported_enable_synthetic_features[@]}"; do
    if [[ "$need_separator" -eq 1 ]]; then
      supported_csv+=", "
    fi
    supported_csv+="$feature"
    need_separator=1
  done

  printf '%s\n' "$supported_csv"
}

policy_initialize_feature_catalog_from_embedded_values() {
  if [[ "${#policy_embedded_optional_integration_features[@]}" -eq 0 ]]; then
    return 1
  fi

  safehouse_array_copy policy_optional_integration_features policy_embedded_optional_integration_features
  if [[ -n "${policy_embedded_supported_enable_features:-}" ]]; then
    policy_supported_enable_features="${policy_embedded_supported_enable_features}"
  else
    policy_supported_enable_features="$(policy_build_supported_enable_features_csv)"
  fi
  policy_feature_catalog_initialized=1
}

policy_initialize_feature_catalog() {
  local profile_key feature
  local -a optional_profile_keys=()

  policy_optional_integration_features=()
  policy_supported_enable_features=""

  if policy_initialize_feature_catalog_from_embedded_values; then
    return 0
  fi

  policy_source_collect_sorted_profile_keys_in_dir optional_profile_keys "profiles/55-integrations-optional"
  if [[ "${#optional_profile_keys[@]}" -eq 0 ]]; then
    safehouse_fail "No optional integration profiles found in: profiles/55-integrations-optional"
    return 1
  fi

  for profile_key in "${optional_profile_keys[@]}"; do
    feature="$(policy_optional_integration_feature_basename_from_profile_key "$profile_key")" || continue
    policy_optional_integration_feature_is_user_exposed "$feature" || continue
    policy_optional_integration_features+=("$feature")
  done

  policy_supported_enable_features="$(policy_build_supported_enable_features_csv)"
  policy_feature_catalog_initialized=1
}

policy_ensure_feature_catalog_initialized() {
  if [[ "${policy_feature_catalog_initialized:-0}" -eq 1 ]]; then
    return 0
  fi

  policy_initialize_feature_catalog
}

policy_is_known_optional_integration_feature() {
  local candidate="$1"
  local feature

  policy_ensure_feature_catalog_initialized || return 1

  for feature in "${policy_optional_integration_features[@]}"; do
    if [[ "$feature" == "$candidate" ]]; then
      return 0
    fi
  done

  return 1
}

policy_optional_integration_profile_key_from_feature() {
  local feature="$1"

  policy_ensure_feature_catalog_initialized || return 1

  if ! policy_is_known_optional_integration_feature "$feature"; then
    return 1
  fi

  printf 'profiles/55-integrations-optional/%s.sb\n' "$feature"
}

policy_optional_integration_feature_from_profile_key() {
  local profile_key="$1"
  local feature

  policy_ensure_feature_catalog_initialized || return 1
  feature="$(policy_optional_integration_feature_basename_from_profile_key "$profile_key")" || return 1

  if policy_is_known_optional_integration_feature "$feature"; then
    printf '%s\n' "$feature"
    return 0
  fi

  return 1
}
