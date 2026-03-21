#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Toolchain smoke tests.
# Verifies that common developer toolchains work inside the default sandbox.
#
load ../../test_helper.bash

@test "[POLICY-ONLY] default profile includes the Java toolchain source" { # https://github.com/eugene1g/agent-safehouse/issues/10
  local profile
  profile="$(safehouse_profile)"

  sft_assert_includes_source "$profile" "30-toolchains/java.sb"
}

@test "[POLICY-ONLY] default profile includes the always-on toolchain catalog" {
  local profile toolchain
  local -a toolchains=(apple-toolchain-core bun deno go java node perl php python ruby runtime-managers rust)

  profile="$(safehouse_profile)"

  for toolchain in "${toolchains[@]}"; do
    sft_assert_includes_source "$profile" "30-toolchains/${toolchain}.sb"
  done
}

@test "[POLICY-ONLY] node toolchain grants fnm multishell metadata traversal" { # issue #13
  local profile
  profile="$(safehouse_profile)"

  sft_assert_contains "$profile" "(home-literal \"/.local/state\")"
  sft_assert_contains "$profile" "(home-subpath \"/.local/state/fnm_multishells\")"
}

@test "[POLICY-ONLY] node toolchain grants the fnm runtime install roots" { # issue #13
  local profile
  profile="$(safehouse_profile)"

  sft_assert_contains "$profile" "(home-subpath \"/.local/share/fnm\")"
  sft_assert_contains "$profile" "(home-subpath \"/Library/Application Support/fnm\")"
}

@test "[POLICY-ONLY] apple toolchain core includes the curated CLT aliases used by common builds" { # https://github.com/eugene1g/agent-safehouse/issues/57
  local profile binary
  local -a binaries=(c++ cc g++ ranlib c++filt gcov lorder nm objdump otool size)

  profile="$(safehouse_profile)"

  for binary in "${binaries[@]}"; do
    sft_assert_contains "$profile" "(literal \"/Library/Developer/CommandLineTools/usr/bin/${binary}\")"
  done
}

@test "[EXECUTION] java compiles and runs a class inside the sandbox" { # https://github.com/eugene1g/agent-safehouse/issues/10
  sft_require_cmd_or_skip java
  sft_require_cmd_or_skip javac

  local src java_bin javac_bin java_home
  src="$(sft_workspace_path "Hello.java")" || return 1
  java_home="${JAVA_HOME:-}"
  if [[ -z "${java_home}" ]]; then
    java_home="$(/usr/libexec/java_home 2>/dev/null || true)"
  fi
  if [[ -n "${java_home}" ]] && [[ -x "${java_home}/bin/java" ]] && [[ -x "${java_home}/bin/javac" ]]; then
    java_bin="${java_home}/bin/java"
    javac_bin="${java_home}/bin/javac"
  else
    java_bin="$(sft_command_path_or_skip java)" || return 1
    javac_bin="$(sft_command_path_or_skip javac)" || return 1
  fi
  printf 'public class Hello { public static void main(String[] a) { System.out.println("sandboxed-java"); } }\n' > "$src"

  run /bin/sh -c 'cd "$1" && "$2" Hello.java && "$3" Hello' _ "$SAFEHOUSE_WORKSPACE" "$javac_bin" "$java_bin"
  if [[ "$status" -ne 0 ]] || [[ "$output" != *"sandboxed-java"* ]]; then
    skip "java toolchain precheck failed outside sandbox"
  fi

  safehouse_ok -- /bin/sh -c 'cd "$1" && "$2" Hello.java && "$3" Hello' _ "$SAFEHOUSE_WORKSPACE" "$javac_bin" "$java_bin"
}

@test "[EXECUTION] make builds a target inside the sandbox" { # https://github.com/eugene1g/agent-safehouse/issues/18
  sft_require_cmd_or_skip make

  local makefile output_file
  makefile="$(sft_workspace_path "Makefile")" || return 1
  output_file="$(sft_workspace_path "result.txt")" || return 1

  printf 'all:\n\t@printf "%%s" "make-ok" > result.txt\n' > "$makefile"

  safehouse_ok -- /bin/sh -c "cd '$SAFEHOUSE_WORKSPACE' && make"
  sft_assert_file_content "$output_file" "make-ok"
}

@test "[EXECUTION] clang compiles and runs a binary inside the sandbox" { # https://github.com/eugene1g/agent-safehouse/issues/26
  sft_require_cmd_or_skip clang

  local src bin
  src="$(sft_workspace_path "hello.c")" || return 1
  bin="$(sft_workspace_path "hello")" || return 1

  printf '#include <stdio.h>\nint main(void) { puts("sandboxed-c"); return 0; }\n' > "$src"

  safehouse_ok -- /bin/sh -c "cd '$SAFEHOUSE_WORKSPACE' && clang -o hello hello.c && ./hello"
}

@test "[EXECUTION] ar can build a static archive inside the sandbox" { # https://github.com/eugene1g/agent-safehouse/issues/57
  sft_require_cmd_or_skip ar
  sft_require_cmd_or_skip clang

  local src obj archive ar_bin clang_bin
  src="$(sft_workspace_path "archive.c")" || return 1
  obj="$(sft_workspace_path "archive.o")" || return 1
  archive="$(sft_workspace_path "libarchive.a")" || return 1
  ar_bin="$(sft_command_path_or_skip ar)" || return 1
  clang_bin="$(sft_command_path_or_skip clang)" || return 1

  printf 'int archive_symbol(void) { return 57; }\n' > "$src"

  run /bin/sh -c 'cd "$1" && "$2" -c archive.c -o archive.o && "$3" rcs libarchive.a archive.o && test -f libarchive.a' _ "$SAFEHOUSE_WORKSPACE" "$clang_bin" "$ar_bin"
  if [[ "$status" -ne 0 ]]; then
    skip "archive toolchain precheck failed outside sandbox"
  fi

  safehouse_ok -- /bin/sh -c 'cd "$1" && "$2" -c archive.c -o archive.o && "$3" rcs libarchive.a archive.o && test -f libarchive.a' _ "$SAFEHOUSE_WORKSPACE" "$clang_bin" "$ar_bin"
  sft_assert_file_exists "$obj"
  sft_assert_file_exists "$archive"
}

@test "[EXECUTION] cargo builds a Rust static library inside the sandbox" { # https://github.com/eugene1g/agent-safehouse/issues/57
  sft_require_cmd_or_skip cargo

  local cargo_toml src_dir lib_rs archive cargo_bin
  cargo_toml="$(sft_workspace_path "Cargo.toml")" || return 1
  src_dir="$(sft_workspace_path "src")" || return 1
  lib_rs="$(sft_workspace_path "src/lib.rs")" || return 1
  archive="$(sft_workspace_path "target/debug/librust_staticlib_smoke.a")" || return 1
  cargo_bin="$(sft_command_path_or_skip cargo)" || return 1

  mkdir -p "$src_dir" || return 1
  printf '[package]\nname = "rust_staticlib_smoke"\nversion = "0.1.0"\nedition = "2021"\n\n[lib]\ncrate-type = ["staticlib"]\n' > "$cargo_toml"
  printf '#[no_mangle]\npub extern "C" fn rust_staticlib_smoke() -> i32 { 57 }\n' > "$lib_rs"

  # rustup-managed cargo resolves toolchains relative to HOME, so use the host
  # home for both the precheck and the sandboxed execution path.
  run env HOME="$SAFEHOUSE_HOST_HOME" /bin/sh -c 'cd "$1" && "$2" build --quiet && test -f target/debug/librust_staticlib_smoke.a' _ "$SAFEHOUSE_WORKSPACE" "$cargo_bin"
  if [[ "$status" -ne 0 ]]; then
    skip "rust toolchain precheck failed outside sandbox"
  fi

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- /bin/sh -c 'cd "$1" && "$2" build --quiet && test -f target/debug/librust_staticlib_smoke.a' _ "$SAFEHOUSE_WORKSPACE" "$cargo_bin"
  sft_assert_file_exists "$archive"
}

@test "[EXECUTION] git initializes a repo and commits inside the sandbox" {
  sft_require_cmd_or_skip git

  safehouse_ok -- /bin/sh -c "cd '$SAFEHOUSE_WORKSPACE' && git init && git config user.email test@test && git config user.name test && printf x > f && git add f && git commit -m init"
}

@test "[EXECUTION] node child processes can resolve npm through fnm multishell PATH entries" { # issue #13
  sft_require_cmd_or_skip node

  local node_bin blocked_parent blocked_root blocked_bin fallback_bin
  node_bin="$(env HOME="$SAFEHOUSE_HOST_HOME" node -p 'process.execPath')" || skip "node precheck failed outside sandbox"
  case "$node_bin" in
    /opt/*|/usr/*|/bin/*|/sbin/*|\
    "${SAFEHOUSE_HOST_HOME}"/.local/share/fnm/*|\
    "${SAFEHOUSE_HOST_HOME}"/.local/share/mise/*|\
    "${SAFEHOUSE_HOST_HOME}"/Library/pnpm/*|\
    "${SAFEHOUSE_HOST_HOME}"/.nvm/*|\
    "${SAFEHOUSE_HOST_HOME}"/.fnm/*|\
    "${SAFEHOUSE_HOST_HOME}"/.asdf/*)
      ;;
    *)
      skip "node path is not in a supported safehouse location: ${node_bin}"
      ;;
  esac
  blocked_parent="${SAFEHOUSE_HOST_HOME}/.local/state/fnm_multishells"
  mkdir -p "$blocked_parent" || return 1
  blocked_root="$(mktemp -d "${blocked_parent}/safehouse-bats-fnm.XXXXXX")" || return 1
  blocked_bin="${blocked_root}/bin"
  fallback_bin="$(sft_workspace_path "fallback-bin")" || return 1
  mkdir -p "$blocked_bin" "$fallback_bin" || return 1

  ln -sf /usr/bin/true "${blocked_bin}/npm" || return 1
  printf '#!/bin/sh\nprintf "fallback-npm\\n"\n' > "${fallback_bin}/npm"
  chmod 755 "${fallback_bin}/npm" || return 1

  run env HOME="$SAFEHOUSE_HOST_HOME" PATH="${blocked_bin}:${fallback_bin}:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$node_bin" -e 'const {spawnSync}=require("node:child_process"); const r=spawnSync("npm", [], {stdio: "ignore"}); if (r.error) { console.error(r.error.code || r.error.message); process.exit(1); } process.exit(r.status ?? 1);'
  if [[ "$status" -ne 0 ]]; then
    rm -rf -- "$blocked_root"
    skip "node precheck failed outside sandbox"
  fi

  run env HOME="$SAFEHOUSE_HOST_HOME" PATH="${blocked_bin}:${fallback_bin}:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$DIST_SAFEHOUSE" -- "$node_bin" -e 'const {spawnSync}=require("node:child_process"); const r=spawnSync("npm", [], {stdio: "ignore"}); if (r.error) { console.error(r.error.code || r.error.message); process.exit(1); } process.exit(r.status ?? 1);'
  rm -rf -- "$blocked_root"
  [ "$status" -eq 0 ]
}

@test "[EXECUTION] node child processes can resolve npm root -g through a real fnm multishell PATH entry" { # issue #13
  sft_require_cmd_or_skip fnm
  sft_require_cmd_or_skip node

  local host_path node_bin npm_path expected_root
  host_path="$PATH"

  run env HOME="$SAFEHOUSE_HOST_HOME" PATH="$host_path" /bin/sh -c 'command -v npm'
  if [[ "$status" -ne 0 ]]; then
    skip "npm is not available in the host environment"
  fi
  npm_path="$output"

  case "$npm_path" in
    "${SAFEHOUSE_HOST_HOME}"/.local/state/fnm_multishells/*/bin/npm)
      ;;
    *)
      skip "npm is not resolving through a real fnm multishell PATH entry"
      ;;
  esac

  node_bin="$(env HOME="$SAFEHOUSE_HOST_HOME" PATH="$host_path" node -p 'process.execPath')" || skip "node precheck failed outside sandbox"

  run env HOME="$SAFEHOUSE_HOST_HOME" PATH="$host_path" \
    "$node_bin" -e 'const {spawnSync}=require("node:child_process"); const r=spawnSync("npm", ["root", "-g"], {encoding: "utf8"}); if (r.error) { console.error(r.error.code || r.error.message); process.exit(1); } process.stdout.write((r.stdout || "").trim()); process.exit(r.status ?? 1);'
  if [[ "$status" -ne 0 ]]; then
    skip "fnm-backed npm root -g precheck failed outside sandbox"
  fi
  expected_root="$output"

  run env HOME="$SAFEHOUSE_HOST_HOME" PATH="$host_path" \
    "$DIST_SAFEHOUSE" -- "$node_bin" -e 'const {spawnSync}=require("node:child_process"); const r=spawnSync("npm", ["root", "-g"], {encoding: "utf8"}); if (r.error) { console.error(r.error.code || r.error.message); process.exit(1); } process.stdout.write((r.stdout || "").trim()); process.exit(r.status ?? 1);'
  [ "$status" -eq 0 ]
  [ "$output" = "$expected_root" ]
}

@test "[EXECUTION] bundler can read the macOS system default gemspec catalog inside the sandbox" {
  sft_require_cmd_or_skip bundle
  sft_require_cmd_or_skip ruby

  run /bin/sh -c 'bundle --version && ruby -e '\''require "bundler"; puts Bundler::VERSION'\'''
  if [[ "$status" -ne 0 ]]; then
    skip "bundler precheck failed outside sandbox"
  fi

  safehouse_ok -- /bin/sh -c 'bundle --version && ruby -e '\''require "bundler"; puts Bundler::VERSION'\'''
}
