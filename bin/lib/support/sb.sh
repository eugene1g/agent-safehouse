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

safehouse_escape_for_sb() {
  local value="$1"

  safehouse_validate_sb_string "$value" "SBPL string" || return 1
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

safehouse_replace_literal_stream_required() {
  local from="$1"
  local to="$2"

  awk -v from="$from" -v to="$to" '
    BEGIN { replaced = 0 }
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
