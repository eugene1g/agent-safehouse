# shellcheck shell=bash

safehouse_trim_whitespace() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

safehouse_to_lowercase() {
  local value="$1"
  printf '%s' "$value" | tr '[:upper:]' '[:lower:]'
}

safehouse_join_by_space() {
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

safehouse_strip_matching_quotes() {
  local value="$1"
  local value_len first_char last_char

  value_len="${#value}"
  if [[ "$value_len" -lt 2 ]]; then
    printf '%s' "$value"
    return 0
  fi

  first_char="${value:0:1}"
  last_char="${value:value_len-1:1}"

  if [[ "$first_char" == "\"" && "$last_char" == "\"" ]]; then
    printf '%s' "${value:1:value_len-2}"
    return 0
  fi

  if [[ "$first_char" == "'" && "$last_char" == "'" ]]; then
    printf '%s' "${value:1:value_len-2}"
    return 0
  fi

  printf '%s' "$value"
}
