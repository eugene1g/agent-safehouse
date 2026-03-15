# shellcheck shell=bash

# Purpose: Resolve profile keys, profile paths, and deterministic profile lists.
# Reads globals: ROOT_DIR, PROFILES_DIR.
# Writes globals: none.
# Called by: policy/metadata.sh, policy/selection.sh, policy/plan.sh, policy/render.sh.
# Notes: Profile collection writes into caller-named arrays via support/collections.sh.

policy_source_normalize_profile_key() {
  local source="$1"

  if [[ "$source" == profiles/* ]]; then
    printf '%s\n' "$source"
    return 0
  fi

  if [[ -n "${PROFILES_DIR:-}" && "$source" == "${PROFILES_DIR}/"* ]]; then
    printf 'profiles/%s\n' "${source#"${PROFILES_DIR}/"}"
    return 0
  fi

  printf '%s\n' "$source"
}

policy_source_path_from_key() {
  local profile_key="$1"

  if [[ "$profile_key" == profiles/* ]]; then
    printf '%s/%s\n' "$ROOT_DIR" "$profile_key"
    return 0
  fi

  printf '%s\n' "$profile_key"
}

policy_source_collect_sorted_profile_keys_in_dir() {
  local target_array_name="$1"
  local base_dir="$2"
  local dir_path="" profile_key_prefix="" file
  local nullglob_was_set=0
  local LC_ALL=C

  safehouse_array_clear "$target_array_name"

  case "$base_dir" in
    profiles/*)
      profile_key_prefix="${base_dir%/}"
      dir_path="${ROOT_DIR}/${profile_key_prefix}"
      ;;
    "${PROFILES_DIR}"/*)
      dir_path="${base_dir%/}"
      profile_key_prefix="profiles/${dir_path#"${PROFILES_DIR}/"}"
      ;;
    *)
      dir_path="${base_dir%/}"
      profile_key_prefix="$(policy_source_normalize_profile_key "$dir_path")"
      ;;
  esac

  if shopt -q nullglob; then
    nullglob_was_set=1
  fi
  shopt -s nullglob

  for file in "${dir_path%/}/"*.sb; do
    [[ -f "$file" ]] || continue
    safehouse_array_append "$target_array_name" "${profile_key_prefix}/$(basename "$file")"
  done

  if [[ "$nullglob_was_set" -ne 1 ]]; then
    shopt -u nullglob
  fi
}

policy_source_read_profile_content() {
  local profile_key="$1"
  local profile_path

  profile_path="$(policy_source_path_from_key "$profile_key")"
  if [[ ! -f "$profile_path" ]]; then
    safehouse_fail "Missing profile module: ${profile_key}"
    return 1
  fi

  cat "$profile_path"
}
