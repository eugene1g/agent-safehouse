# shellcheck shell=bash

safehouse_validate_sb_string() {
  local value="$1"
  local label="${2:-SBPL string}"

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    safehouse_fail "Invalid ${label}: contains control characters and cannot be emitted into SBPL."
    return 1
  fi

  return 0
}

# The output variable must not use the helper's _safehouse_sb_ local prefix.
safehouse_escape_for_sb_into() {
  local _safehouse_sb_value="$2"

  safehouse_require_collection_name "$1" || return 1
  safehouse_validate_sb_string "$_safehouse_sb_value" "SBPL string" || return 1
  _safehouse_sb_value="${_safehouse_sb_value//\\/\\\\}"
  _safehouse_sb_value="${_safehouse_sb_value//\"/\\\"}"
  printf -v "$1" '%s' "$_safehouse_sb_value"
}

safehouse_escape_for_sb() {
  local value

  safehouse_escape_for_sb_into value "$1" || return 1
  printf '%s' "$value"
}

safehouse_replace_literal_stream_required() {
  local from="$1"
  local to="$2"

  # awk -v decodes backslash escapes in assigned values. Pass replacement text
  # through the environment so already-escaped SBPL strings stay byte-for-byte
  # intact (for example, paths containing quotes or backslashes).
  SAFEHOUSE_REPLACE_LITERAL_FROM="$from" \
  SAFEHOUSE_REPLACE_LITERAL_TO="$to" \
  awk '
    BEGIN {
      from = ENVIRON["SAFEHOUSE_REPLACE_LITERAL_FROM"]
      to = ENVIRON["SAFEHOUSE_REPLACE_LITERAL_TO"]
      replaced = 0
    }
    {
      if (from == "") {
        print $0
        next
      }

      line = $0
      out = ""
      from_len = length(from)
      while ((idx = index(line, from)) > 0) {
        replaced = 1
        out = out substr(line, 1, idx - 1) to
        line = substr(line, idx + from_len)
      }

      print out line
    }
    END {
      if (replaced == 0) {
        exit 64
      }
    }
  '
}
