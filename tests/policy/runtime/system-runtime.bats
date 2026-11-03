#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash
load ../procargs_utils.bash

@test "[POLICY-ONLY] default profile includes the system-runtime source and generated HOME ancestor metadata" {
  local profile
  profile="$(safehouse_profile)"

  sft_assert_includes_source "$profile" "10-system-runtime.sb"
  sft_assert_contains "$profile" "#safehouse-test-id:home-ancestor-metadata#"
}

@test "[POLICY-ONLY] generated HOME ancestor block is metadata-only and literal-scoped through HOME" { # https://github.com/eugene1g/agent-safehouse/issues/11
  local profile home_block

  profile="$(safehouse_profile)"
  home_block="$(awk '/#safehouse-test-id:home-ancestor-metadata#/ { capture=1 } capture { print } capture && $0 == ")" { exit }' <<<"$profile")"

  sft_assert_contains "$home_block" "(allow file-read-metadata"
  sft_assert_contains "$home_block" "(literal \"$HOME\")"
  sft_assert_not_contains "$home_block" "(subpath \"$HOME\")"
}

@test "[POLICY-ONLY] default profile emits resolved read-only grants for symlinked built-in paths" {
  local profile resolved_resolv

  sft_require_cmd_or_skip realpath
  [ -e /private/etc/resolv.conf ] || skip "/private/etc/resolv.conf is not present"

  resolved_resolv="$(realpath /private/etc/resolv.conf)"
  [[ "$resolved_resolv" != "/private/etc/resolv.conf" ]] || skip "/private/etc/resolv.conf does not resolve away from itself on this host"

  profile="$(safehouse_profile)"

  sft_assert_contains "$profile" "#safehouse-test-id:resolved-built-in-path#"
  sft_assert_contains "$profile" "/private/etc/resolv.conf -> ${resolved_resolv}"
  sft_assert_contains "$profile" "(literal \"${resolved_resolv}\")"
}

@test "[POLICY-ONLY] default profile keeps xcode-select pointer symlinks unexpanded" {
  local profile

  [ -e /private/var/select/developer_dir ] || skip "/private/var/select/developer_dir is not present"
  [ -e /private/var/db/xcode_select_link ] || skip "/private/var/db/xcode_select_link is not present"

  profile="$(safehouse_profile)"

  sft_assert_not_contains "$profile" "/private/var/select/developer_dir ->"
  sft_assert_not_contains "$profile" "/var/select/developer_dir ->"
  sft_assert_not_contains "$profile" "/private/var/db/xcode_select_link ->"
  sft_assert_not_contains "$profile" "/var/db/xcode_select_link ->"
}

@test "[POLICY-ONLY] default profile includes always-on network, shared, and core integration sources" {
  local profile

  profile="$(safehouse_profile)"

  sft_assert_includes_source "$profile" "20-network.sb"
  sft_assert_includes_source "$profile" "40-shared/agent-common.sb"
  sft_assert_contains "$profile" "(allow ipc-posix-sem)"
  sft_assert_includes_source "$profile" "40-shared/ipc-sysv-sem.sb"
  sft_assert_contains "$profile" "(allow ipc-sysv-sem)"
  sft_assert_includes_source "$profile" "50-integrations-core/container-runtime-default-deny.sb"
  sft_assert_includes_source "$profile" "50-integrations-core/git.sb"
  sft_assert_includes_source "$profile" "50-integrations-core/scm-clis.sb"
  sft_assert_includes_source "$profile" "50-integrations-core/ssh-agent-default-deny.sb"
  sft_assert_includes_source "$profile" "50-integrations-core/worktree-common-dir.sb"
  sft_assert_includes_source "$profile" "50-integrations-core/worktrees.sb"
}

@test "[EXECUTION] default sandbox can read standard runtime paths and devices" {
  safehouse_ok -- /bin/ls /usr/bin
  safehouse_ok -- /bin/cat /dev/null
  safehouse_ok -- /bin/dd if=/dev/urandom bs=1 count=1
}

@test "[EXECUTION] default sandbox can read resolver config through built-in symlink-aware grants" {
  [ -e /etc/resolv.conf ] || skip "/etc/resolv.conf is not present"
  [ -e /private/etc/resolv.conf ] || skip "/private/etc/resolv.conf is not present"

  safehouse_ok -- /bin/cat /etc/resolv.conf >/dev/null
  safehouse_ok -- /bin/cat /private/etc/resolv.conf >/dev/null
}

@test "[EXECUTION] default sandbox gets metadata on HOME itself but no general home read access" { # https://github.com/eugene1g/agent-safehouse/issues/11
  local fake_home secret_file

  fake_home="$(sft_fake_home)" || return 1
  secret_file="${fake_home}/secret.txt"
  printf '%s\n' "secret" > "$secret_file"

  HOME="$fake_home" safehouse_ok -- /usr/bin/stat -f '%N' "$fake_home" >/dev/null
  HOME="$fake_home" safehouse_denied -- /usr/bin/stat -f '%N' "$secret_file"
  HOME="$fake_home" safehouse_denied -- /bin/ls "$fake_home"
  HOME="$fake_home" safehouse_denied -- /bin/cat "$secret_file"
}

@test "[EXECUTION] default sandbox only lists the ~/.config and ~/.cache roots by default" { # https://github.com/eugene1g/agent-safehouse/issues/11
  local fake_home config_dir cache_dir config_file cache_file

  fake_home="$(sft_fake_home)" || return 1
  config_dir="${fake_home}/.config"
  cache_dir="${fake_home}/.cache"
  config_file="${config_dir}/tool.conf"
  cache_file="${cache_dir}/tool.cache"

  mkdir -p "$config_dir" "$cache_dir"
  printf '%s\n' "cfg" > "$config_file"
  printf '%s\n' "cache" > "$cache_file"

  HOME="$fake_home" safehouse_ok -- /bin/ls "$config_dir" >/dev/null
  HOME="$fake_home" safehouse_ok -- /bin/ls "$cache_dir" >/dev/null
  HOME="$fake_home" safehouse_denied -- /bin/cat "$config_file"
  HOME="$fake_home" safehouse_denied -- /bin/cat "$cache_file"
}

@test "[EXECUTION] default sandbox can read ~/.local/bin entries but not write them" {
  local fake_home local_bin_dir helper_path planted_path

  fake_home="$(sft_fake_home)" || return 1
  local_bin_dir="${fake_home}/.local/bin"
  helper_path="${local_bin_dir}/voice-helper"
  planted_path="${local_bin_dir}/planted"

  mkdir -p "$local_bin_dir"
  printf '%s\n' "installed-helper" > "$helper_path"

  HOME="$fake_home" safehouse_ok -- /bin/ls "$local_bin_dir" >/dev/null
  HOME="$fake_home" safehouse_ok -- /bin/cat "$helper_path"

  # ~/.local/bin is on the user's PATH. Anything planted here would run later
  # outside the sandbox, so writes stay denied for new and existing entries.
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "$planted_path"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "$helper_path"
}

@test "[EXECUTION] the ~/.local/bin grant does not open symlink targets elsewhere" {
  local fake_home target shim

  fake_home="$(sft_fake_home)" || return 1
  target="${fake_home}/.local/share/unknown-tool/bin/unknown-tool"
  shim="${fake_home}/.local/bin/unknown-tool"

  sft_make_fake_command "$target" || return 1
  mkdir -p "${fake_home}/.local/bin" || return 1
  /bin/ln -sfn "$target" "$shim"

  # The shim resolves because ~/.local/bin is readable. The payload is a Mach-O
  # binary, which execs without a read grant; a script would need one, since its
  # interpreter reads the file. Reading the payload stays denied either way.
  HOME="$fake_home" safehouse_ok -- "$shim"
  HOME="$fake_home" safehouse_denied -- /bin/cat "$target"
}

@test "[POLICY-ONLY] default profile grants XDG base directory roots creation, literal-scoped" {
  local profile xdg_block

  profile="$(safehouse_profile)"
  xdg_block="$(awk '/#safehouse-test-id:xdg-root-create#/ { capture=1 } capture { print } capture && $0 == ")" { exit }' <<<"$profile")"

  sft_assert_contains "$xdg_block" "(allow file-write-create"
  sft_assert_contains "$xdg_block" "(home-literal \"/.cache\")"
  sft_assert_contains "$xdg_block" "(home-literal \"/.config\")"
  sft_assert_contains "$xdg_block" "(home-literal \"/.local\")"
  sft_assert_contains "$xdg_block" "(home-literal \"/.local/share\")"
  sft_assert_contains "$xdg_block" "(home-literal \"/.local/state\")"

  # The roots are bootstrapped as directory entries only; nothing below them is opened here.
  sft_assert_not_contains "$xdg_block" "home-subpath"
  sft_assert_not_contains "$xdg_block" "home-prefix"
}

@test "[EXECUTION] default sandbox can create missing XDG base directory roots" {
  local fake_home root

  fake_home="$(sft_fake_home)" || return 1

  # A fresh macOS home ships none of these, so tools must be able to mkdir them
  # before their own per-tool grants under each root become reachable.
  # ~/.local must exist before its own children can be created.
  for root in .cache .config .local .local/share .local/state; do
    HOME="$fake_home" safehouse_ok -- /bin/mkdir "${fake_home}/${root}"
    [ -d "${fake_home}/${root}" ]
  done
}

@test "[EXECUTION] creating an XDG root does not open the tool directories below it" {
  local fake_home

  fake_home="$(sft_fake_home)" || return 1
  mkdir -p "${fake_home}/.cache" "${fake_home}/.local/share" "${fake_home}/.local/state"

  # This is the scoping boundary: bootstrapping the roots must not let an
  # unguarded tool claim its own subdirectory under them. Tools that legitimately
  # need one carry an explicit subpath grant (e.g. ~/.cache/uv in python.sb).
  HOME="$fake_home" safehouse_denied -- /bin/mkdir "${fake_home}/.cache/safehouse-unguarded-tool"
  HOME="$fake_home" safehouse_denied -- /bin/mkdir "${fake_home}/.local/share/safehouse-unguarded-tool"
  HOME="$fake_home" safehouse_denied -- /bin/mkdir "${fake_home}/.local/state/safehouse-unguarded-tool"
}

@test "[EXECUTION] default sandbox can write to tmp" {
  local tmp_canary
  tmp_canary="/tmp/safehouse-bats-tmp-canary.$$"
  rm -f "$tmp_canary"

  safehouse_ok -- /usr/bin/touch "$tmp_canary"
  sft_assert_file_exists "$tmp_canary"
  rm -f "$tmp_canary"
}

@test "[EXECUTION] default sandbox keeps device writes constrained" {
  safehouse_denied -- /bin/sh -c 'printf x > /dev/zero'
}

@test "[EXECUTION] default sandbox keeps shell startup files denied" {
  [ -e /private/etc/zshrc ] || skip "/private/etc/zshrc is not present"

  safehouse_denied -- /bin/cat /private/etc/zshrc
}

@test "[POLICY-ONLY] default profile grants read-only access to the Nix store and profile pointers" {
  local profile
  profile="$(safehouse_profile)"

  sft_assert_contains "$profile" "(subpath \"/nix/store\")"
  sft_assert_contains "$profile" "(subpath \"/nix/var/nix/profiles\")"
  sft_assert_contains "$profile" "(literal \"/nix\")"
  sft_assert_contains "$profile" "(home-literal \"/.nix-profile\")"
  sft_assert_contains "$profile" "(home-literal \"/.local/state/nix/profile\")"
  sft_assert_contains "$profile" "(home-subpath \"/.local/state/nix/profiles\")"

  # Store read-only-ness and the sealed ~/.config/nix are asserted behaviorally
  # by the [EXECUTION] tests below rather than by scraping the rendered policy.
}

@test "[EXECUTION] default sandbox cannot read ~/.config/nix, which may hold access-tokens" {
  local fake_home nix_config

  fake_home="$(sft_fake_home)" || return 1
  nix_config="${fake_home}/.config/nix"

  # ~/.config/nix is deliberately not granted: only the nix CLI reads it (out of
  # scope for running installed programs), and nix.conf commonly carries
  # credentials such as access-tokens = github.com=ghp_....
  mkdir -p "$nix_config"
  printf '%s\n' "access-tokens = github.com=ghp_canary" > "${nix_config}/nix.conf"

  HOME="$fake_home" safehouse_denied -- /bin/cat "${nix_config}/nix.conf"
  HOME="$fake_home" safehouse_denied -- /bin/ls "$nix_config"
}

@test "[EXECUTION] default sandbox cannot read ~/.pypirc, which may hold upload tokens" {
  local fake_home pypirc

  fake_home="$(sft_fake_home)" || return 1
  pypirc="${fake_home}/.pypirc"

  # ~/.pypirc is deliberately not granted: only publishing tools read it
  # (`twine upload`, probably `setuptools upload`, NOT: `uv publish`),
  # whose use is out of scope inside the sandbox. It carries a plaintext
  # PyPI API token that usually has upload scope.
  printf '%s\n' "[pypi]" "username = __token__" "password = pypi-AgEIcHlwaS5vcmcCJGNhbmFyeQ" \
    > "$pypirc"

  HOME="$fake_home" safehouse_denied -- /bin/cat "$pypirc"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "$pypirc"
}

@test "[EXECUTION] Nix store is readable but not writable in the default sandbox" {
  [ -d /nix/store ] || skip "/nix/store not present (Nix not installed)"

  safehouse_ok -- /bin/ls /nix/store >/dev/null

  safehouse_denied -- /usr/bin/touch "/nix/store/safehouse-write-canary.$$"
}

@test "[EXECUTION] default sandbox reads Nix profile pointers but not the rest of ~/.local/state" {
  local fake_home nix_profiles other_state

  fake_home="$(sft_fake_home)" || return 1
  nix_profiles="${fake_home}/.local/state/nix/profiles"
  other_state="${fake_home}/.local/state/other"

  mkdir -p "$nix_profiles" "$other_state"
  printf '%s\n' "profile-marker" > "${nix_profiles}/default"
  printf '%s\n' "secret" > "${other_state}/secret"

  # ~/.nix-profile and ~/.local/state/nix/profile are symlinks into the store in real
  # setups; here we only need the link itself to be resolvable/readable.
  /bin/ln -sfn "${nix_profiles}/default" "${fake_home}/.nix-profile"
  /bin/ln -sfn "${nix_profiles}/default" "${fake_home}/.local/state/nix/profile"

  # Granted: the profiles dir + its contents (home-subpath) and the pointer symlinks.
  # NOTE: this readdir also exercises traversal through ~/.local/state and
  # ~/.local/state/nix, which have no metadata grant of their own — if this
  # assertion fails, the profile needs a file-read-metadata grant on those parents.
  HOME="$fake_home" safehouse_ok -- /bin/ls "$nix_profiles" >/dev/null
  HOME="$fake_home" safehouse_ok -- /bin/cat "${nix_profiles}/default" >/dev/null
  HOME="$fake_home" safehouse_ok -- /usr/bin/readlink "${fake_home}/.nix-profile" >/dev/null
  HOME="$fake_home" safehouse_ok -- /usr/bin/readlink "${fake_home}/.local/state/nix/profile" >/dev/null

  # Not granted: sibling paths under ~/.local/state stay sealed. This is the scoping
  # boundary — the Nix grants must not open the rest of ~/.local/state.
  HOME="$fake_home" safehouse_denied -- /bin/ls "$other_state"
  HOME="$fake_home" safehouse_denied -- /bin/cat "${other_state}/secret"
}

@test "[EXECUTION] default sandbox can read a same-sandbox process's argv via procargs/procargs2" {
  sft_require_cmd_or_skip python3

  # The target sleeps far longer than the read needs, then gets killed once the
  # read is done. A target that exits first fails the sysctl with EPERM, which is
  # indistinguishable from a policy denial (see procargs_utils.bash), and cold
  # python3 startup inside the sandbox has been measured at over 10s on CI.
  local reader selector
  reader="$(sft_procargs_reader_py)"
  for selector in $KERN_PROCARGS $KERN_PROCARGS2; do
    safehouse_run -- /bin/sh -c '/bin/sleep 60 & c=$!; /bin/sleep 1; python3 -c "$1" "$2" "$c"; s=$?; /bin/kill "$c"; exit $s' _ "$reader" "$selector"
    [ "$status" -eq 0 ]
    sft_assert_contains "$output" "sleep"
  done
}

@test "[EXECUTION] default sandbox keeps general sysctl reads working" {
  local ncpu
  ncpu="$(safehouse_ok -- /usr/sbin/sysctl -n hw.ncpu)"
  [[ "$ncpu" =~ ^[0-9]+$ ]]
}
