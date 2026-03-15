# shellcheck shell=bash

# Purpose: Parse metadata embedded in .sb profile comments.
# Reads globals: none.
# Writes globals: none.
# Called by: policy/plan.sh and tests that validate metadata parsing behavior.
# Notes: Requirements and exec env defaults are parsed by separate helpers on purpose.

policy_metadata_extract_csv_metadata_from_line() {
  local line="$1"
  local metadata_key="$2"
  local metadata_pattern=""

  # shellcheck disable=SC2016  # Single quotes keep the regex's literal \$ tokens intact.
  metadata_pattern='^[[:space:]]*;;[[:space:]]*\$\$'"${metadata_key}"'=([^$]+)\$\$'

  if [[ "$line" =~ $metadata_pattern ]]; then
    printf '%s\n' "$(safehouse_trim_whitespace "${BASH_REMATCH[1]}")"
  fi
}

policy_metadata_extract_requirement_csv_from_line() {
  local line="$1"

  policy_metadata_extract_csv_metadata_from_line "$line" "require"
}

policy_metadata_extract_command_alias_csv_from_line() {
  local line="$1"

  policy_metadata_extract_csv_metadata_from_line "$line" "command"
}

policy_metadata_emit_normalized_csv_tokens_from_csv() {
  local raw_csv="$1"
  local raw_entry normalized_entry
  local -a raw_entries=()

  safehouse_csv_split_to_array raw_entries "$raw_csv"
  if [[ "${#raw_entries[@]}" -gt 0 ]]; then
    for raw_entry in "${raw_entries[@]}"; do
      normalized_entry="$(safehouse_to_lowercase "$(safehouse_trim_whitespace "$raw_entry")")"
      if [[ -n "$normalized_entry" ]]; then
        printf '%s\n' "$normalized_entry"
      fi
    done
  fi
}

policy_metadata_emit_requirement_tokens_from_csv() {
  local raw_csv="$1"

  policy_metadata_emit_normalized_csv_tokens_from_csv "$raw_csv"
}

policy_metadata_emit_command_alias_tokens_from_csv() {
  local raw_csv="$1"

  policy_metadata_emit_normalized_csv_tokens_from_csv "$raw_csv"
}

policy_metadata_default_command_alias_from_profile_key() {
  local profile_key="$1"
  local profile_basename=""

  profile_basename="$(basename "$profile_key" .sb)"
  printf '%s\n' "$(safehouse_to_lowercase "$profile_basename")"
}

policy_metadata_emit_profile_requirement_tokens() {
  local profile_key="$1"
  local line raw_requirements

  while IFS= read -r line || [[ -n "$line" ]]; do
    raw_requirements="$(policy_metadata_extract_requirement_csv_from_line "$line")"
    [[ -n "$raw_requirements" ]] || continue
    policy_metadata_emit_requirement_tokens_from_csv "$raw_requirements"
  done < <(policy_source_read_profile_content "$profile_key")
}

policy_metadata_emit_profile_command_alias_tokens() {
  local profile_key="$1"
  local line raw_command_aliases
  local found_metadata=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    raw_command_aliases="$(policy_metadata_extract_command_alias_csv_from_line "$line")"
    [[ -n "$raw_command_aliases" ]] || continue
    found_metadata=1
    policy_metadata_emit_command_alias_tokens_from_csv "$raw_command_aliases"
  done < <(policy_source_read_profile_content "$profile_key")

  if [[ "$found_metadata" -eq 0 ]]; then
    policy_metadata_default_command_alias_from_profile_key "$profile_key"
  fi
}

policy_metadata_extract_exec_env_default_entry_from_line() {
  local line="$1"
  local metadata_entry=""

  [[ "$line" == *"\$\$exec-env-default="*"\$\$"* ]] || return 0

  metadata_entry="${line#*\$\$exec-env-default=}"
  metadata_entry="${metadata_entry%%\$\$*}"
  metadata_entry="$(safehouse_trim_whitespace "$metadata_entry")"
  if [[ -n "$metadata_entry" ]]; then
    printf '%s\n' "$metadata_entry"
  fi
}

policy_metadata_normalize_exec_env_default_entry() {
  local raw_entry="$1"
  local source_profile="$2"
  local key value

  if [[ "$raw_entry" != *=* ]]; then
    safehouse_fail "Invalid \$\$exec-env-default metadata in ${source_profile}: expected NAME=VALUE."
    return 1
  fi

  key="$(safehouse_trim_whitespace "${raw_entry%%=*}")"
  value="$(safehouse_trim_whitespace "${raw_entry#*=}")"

  if ! safehouse_validate_env_var_name "$key"; then
    safehouse_fail "Invalid \$\$exec-env-default metadata in ${source_profile}: ${key} is not a valid environment variable name."
    return 1
  fi

  safehouse_validate_sb_string "$value" "\$\$exec-env-default value in ${source_profile}" || return 1
  printf '%s=%s\n' "$key" "$value"
}

policy_metadata_emit_profile_exec_env_defaults() {
  local profile_key="$1"
  local line raw_entry normalized_entry

  while IFS= read -r line || [[ -n "$line" ]]; do
    raw_entry="$(policy_metadata_extract_exec_env_default_entry_from_line "$line")"
    [[ -n "$raw_entry" ]] || continue
    normalized_entry="$(policy_metadata_normalize_exec_env_default_entry "$raw_entry" "$profile_key")" || return 1
    printf '%s\n' "$normalized_entry"
  done < <(policy_source_read_profile_content "$profile_key")
}
