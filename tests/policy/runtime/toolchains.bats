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

@test "[EXECUTION] java compiles and runs a class inside the sandbox" { # https://github.com/eugene1g/agent-safehouse/issues/10
  sft_require_cmd_or_skip java
  sft_require_cmd_or_skip javac

  local src out
  src="$(sft_workspace_path "Hello.java")" || return 1
  printf 'public class Hello { public static void main(String[] a) { System.out.println("sandboxed-java"); } }\n' > "$src"

  java -version >/dev/null 2>&1 || skip "java runtime precheck failed outside sandbox"
  javac -version >/dev/null 2>&1 || skip "javac precheck failed outside sandbox"

  safehouse_ok -- /bin/sh -c "cd '$SAFEHOUSE_WORKSPACE' && javac Hello.java && java Hello"
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

@test "[EXECUTION] git initializes a repo and commits inside the sandbox" {
  sft_require_cmd_or_skip git

  safehouse_ok -- /bin/sh -c "cd '$SAFEHOUSE_WORKSPACE' && git init && git config user.email test@test && git config user.name test && printf x > f && git add f && git commit -m init"
}
