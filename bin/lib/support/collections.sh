# shellcheck shell=bash

# Purpose: Small Bash 3.2-safe array/env collection helpers.
# Reads globals: none.
# Writes globals: Arrays named by callers via the helpers below.
# Called by: cli/parse.sh, policy/*.sh, runtime/environment.sh.
# Notes: Keep eval isolated to this file for array-by-name handling.

safehouse_validate_collection_name() {
  local collection_name="$1"

  [[ "$collection_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

safehouse_require_collection_name() {
  local collection_name="$1"

  if safehouse_validate_collection_name "$collection_name"; then
    return 0
  fi

  safehouse_fail "Invalid collection variable name: ${collection_name}"
}

safehouse_array_contains_exact() {
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

safehouse_array_contains_exact_by_name() {
  local array_name="$1"
  local needle="$2"
  local value
  local found=1

  safehouse_require_collection_name "$array_name" || return 1

  eval '
    if [[ ${#'"$array_name"'[@]} -gt 0 ]]; then
      for value in "${'"$array_name"'[@]}"; do
        if [[ "$value" == "$needle" ]]; then
          found=0
          break
        fi
      done
    fi
  '

  return "$found"
}

safehouse_array_length() {
  local array_name="$1"
  local length

  safehouse_require_collection_name "$array_name" || return 1
  eval "length=\${#${array_name}[@]}"
  printf '%s\n' "$length"
}

safehouse_array_clear() {
  local array_name="$1"

  safehouse_require_collection_name "$array_name" || return 1
  eval "${array_name}=()"
}

# shellcheck disable=SC2034  # append_value is consumed via eval.
safehouse_array_append() {
  local array_name="$1"
  shift
  local append_value

  safehouse_require_collection_name "$array_name" || return 1
  for append_value in "$@"; do
    eval "${array_name}+=(\"\${append_value}\")"
  done
}

safehouse_array_append_unique() {
  local array_name="$1"
  shift
  local value

  for value in "$@"; do
    if safehouse_array_contains_exact_by_name "$array_name" "$value"; then
      continue
    fi
    safehouse_array_append "$array_name" "$value"
  done
}

safehouse_array_copy() {
  local target_name="$1"
  local source_name="$2"

  safehouse_require_collection_name "$target_name" || return 1
  safehouse_require_collection_name "$source_name" || return 1
  safehouse_array_clear "$target_name"
  eval "
    if [[ \${#${source_name}[@]} -gt 0 ]]; then
      ${target_name}=(\"\${${source_name}[@]}\")
    fi
  "
}

safehouse_array_append_from_array() {
  local target_name="$1"
  local source_name="$2"
  local -a source_values=()

  safehouse_array_copy source_values "$source_name"
  if [[ "${#source_values[@]}" -gt 0 ]]; then
    safehouse_array_append "$target_name" "${source_values[@]}"
  fi
}

safehouse_csv_split_to_array() {
  local target_name="$1"
  local csv="$2"
  local IFS=','
  local -a values=()

  safehouse_require_collection_name "$target_name" || return 1
  safehouse_array_clear "$target_name"
  read -r -a values <<< "$csv"
  if [[ "${#values[@]}" -gt 0 ]]; then
    safehouse_array_append "$target_name" "${values[@]}"
  fi
}

safehouse_env_array_upsert_entry() {
  local array_name="$1"
  local entry="$2"
  local entry_key existing_entry existing_key
  local idx array_length

  safehouse_require_collection_name "$array_name" || return 1
  [[ "$entry" == *=* ]] || return 1
  entry_key="${entry%%=*}"
  [[ -n "$entry_key" ]] || return 1

  eval "array_length=\${#${array_name}[@]}"
  for ((idx = 0; idx < array_length; idx++)); do
    eval "existing_entry=\${${array_name}[${idx}]}"
    existing_key="${existing_entry%%=*}"
    if [[ "$existing_key" == "$entry_key" ]]; then
      eval "${array_name}[${idx}]=\"\${entry}\""
      return 0
    fi
  done

  safehouse_array_append "$array_name" "$entry"
}

safehouse_env_array_append_entry_if_key_missing() {
  local array_name="$1"
  local entry="$2"
  local entry_key existing_entry existing_key
  local idx array_length

  safehouse_require_collection_name "$array_name" || return 1
  [[ "$entry" == *=* ]] || return 1
  entry_key="${entry%%=*}"
  [[ -n "$entry_key" ]] || return 1

  eval "array_length=\${#${array_name}[@]}"
  for ((idx = 0; idx < array_length; idx++)); do
    eval "existing_entry=\${${array_name}[${idx}]}"
    existing_key="${existing_entry%%=*}"
    if [[ "$existing_key" == "$entry_key" ]]; then
      return 0
    fi
  done

  safehouse_array_append "$array_name" "$entry"
}

safehouse_env_array_upsert_entries() {
  local array_name="$1"
  shift
  local entry

  for entry in "$@"; do
    safehouse_env_array_upsert_entry "$array_name" "$entry" || return 1
  done
}

safehouse_env_array_append_entries_if_keys_missing() {
  local array_name="$1"
  shift
  local entry

  for entry in "$@"; do
    safehouse_env_array_append_entry_if_key_missing "$array_name" "$entry" || return 1
  done
}
