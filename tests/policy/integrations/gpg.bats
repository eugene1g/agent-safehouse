#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[EXECUTION] gpg keyring access is opt-in via enable=gpg" {
  local gpg_bin fake_home gnupg_dir

  gpg_bin="$(sft_command_path_or_skip gpg)" || return 1
  fake_home="$(sft_fake_home)" || return 1
  gnupg_dir="${fake_home}/.gnupg"
  mkdir -m 700 -p "$gnupg_dir"

  HOME="$fake_home" GNUPGHOME="$gnupg_dir" "$gpg_bin" --batch --passphrase "" --pinentry-mode loopback --quick-generate-key sft-gpg-test@example.com default default none
  HOME="$fake_home" GNUPGHOME="$gnupg_dir" "$gpg_bin" --list-keys >/dev/null

  HOME="$fake_home" GNUPGHOME="$gnupg_dir" safehouse_denied -- "$gpg_bin" --list-keys
  HOME="$fake_home" GNUPGHOME="$gnupg_dir" safehouse_ok --enable=gpg -- "$gpg_bin" --list-keys >/dev/null
}

@test "[EXECUTION] git produces a gpg-signed commit inside the sandbox with enable=gpg" {
  local gpg_bin git_bin gpgconf_bin fake_home gnupg_dir keyid

  gpg_bin="$(sft_command_path_or_skip gpg)" || return 1
  git_bin="$(sft_command_path_or_skip git)" || return 1
  gpgconf_bin="$(sft_command_path_or_skip gpgconf)" || return 1
  fake_home="$(sft_fake_home)" || return 1
  gnupg_dir="${fake_home}/.gnupg"
  mkdir -m 700 -p "$gnupg_dir"

  HOME="$fake_home" GNUPGHOME="$gnupg_dir" "$gpg_bin" --batch --passphrase "" --pinentry-mode loopback --quick-generate-key sft-gpg-commit-test@example.com default default none

  keyid="$(HOME="$fake_home" GNUPGHOME="$gnupg_dir" "$gpg_bin" --list-keys --with-colons | awk -F: '/^pub/ { print $5; exit }')"
  if [ -z "$keyid" ]; then
    printf 'could not determine generated gpg key id outside sandbox\n' >&2
    return 1
  fi

  # Documented prerequisite: gpg-agent (and keyboxd on GnuPG >= 2.4) must already
  # be running on the host before entering the sandbox -- a sandboxed gpg cannot
  # cold-start its own agent.
  HOME="$fake_home" GNUPGHOME="$gnupg_dir" "$gpgconf_bin" --launch gpg-agent
  # NOTE: OK if keyboxd fails because it is only present on GnuPG >= 2.4
  HOME="$fake_home" GNUPGHOME="$gnupg_dir" "$gpgconf_bin" --launch keyboxd >/dev/null 2>&1 || true

  "$git_bin" init -q
  "$git_bin" config user.email sft-gpg-commit-test@example.com
  "$git_bin" config user.name "Safehouse GPG Test"
  "$git_bin" config gpg.program "$gpg_bin"
  "$git_bin" config user.signingkey "$keyid"
  printf 'hello\n' > file.txt
  "$git_bin" add file.txt

  HOME="$fake_home" GNUPGHOME="$gnupg_dir" safehouse_ok --enable=gpg -- "$git_bin" commit -S -m "sft gpg commit test" >/dev/null

  HOME="$fake_home" GNUPGHOME="$gnupg_dir" run "$git_bin" log --show-signature -1
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Good signature"
}

@test "[EXECUTION] gpg secret keys remain denied with and without enable=gpg" {
  local gpg_bin fake_home gnupg_dir

  gpg_bin="$(sft_command_path_or_skip gpg)" || return 1
  fake_home="$(sft_fake_home)" || return 1
  gnupg_dir="${fake_home}/.gnupg"
  mkdir -m 700 -p "$gnupg_dir"

  HOME="$fake_home" GNUPGHOME="$gnupg_dir" "$gpg_bin" --batch --passphrase "" --pinentry-mode loopback --quick-generate-key sft-gpg-test@example.com default default none
  if [ ! -d "${gnupg_dir}/private-keys-v1.d" ]; then
    printf 'no private-keys-v1.d produced outside sandbox\n' >&2
    return 1
  fi

  HOME="$fake_home" GNUPGHOME="$gnupg_dir" safehouse_denied -- ls "${gnupg_dir}/private-keys-v1.d"
  HOME="$fake_home" GNUPGHOME="$gnupg_dir" safehouse_denied --enable=gpg -- ls "${gnupg_dir}/private-keys-v1.d"
}

@test "[POLICY-ONLY] default profile does not include the gpg integration marker" {
  local profile
  profile="$(safehouse_profile)"

  sft_assert_omits_source "$profile" "55-integrations-optional/gpg.sb"
}

@test "[POLICY-ONLY] enable=gpg adds the gpg integration marker" {
  local profile
  profile="$(safehouse_profile --enable=gpg)"

  sft_assert_includes_source "$profile" "55-integrations-optional/gpg.sb"
}

@test "[POLICY-ONLY] enable=gpg allows the gpg-agent and keyboxd unix sockets" {
  local profile
  profile="$(safehouse_profile --enable=gpg)"

  sft_assert_contains "$profile" '/.gnupg/S.gpg-agent'
  sft_assert_contains "$profile" '/.gnupg/S.keyboxd'
}

@test "[POLICY-ONLY] enable=gpg keeps private-keys-v1.d denied" {
  local profile
  profile="$(safehouse_profile --enable=gpg)"

  sft_assert_contains "$profile" '/.gnupg/private-keys-v1.d'
}

@test "[EXECUTION] gpg legacy secring.gpg remains denied with and without enable=gpg" {
  local fake_home gnupg_dir secring

  fake_home="$(sft_fake_home)" || return 1
  gnupg_dir="${fake_home}/.gnupg"
  mkdir -m 700 -p "$gnupg_dir"
  secring="${gnupg_dir}/secring.gpg"
  printf 'fake legacy secret keyring\n' > "$secring"

  HOME="$fake_home" GNUPGHOME="$gnupg_dir" safehouse_denied -- cat "$secring"
  HOME="$fake_home" GNUPGHOME="$gnupg_dir" safehouse_denied --enable=gpg -- cat "$secring"
}
