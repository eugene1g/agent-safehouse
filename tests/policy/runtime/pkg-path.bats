#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] pkg PATH lookup grants only metadata on the global environment symlink" { # issue #197
  local profile pkg_block
  profile="$(safehouse_profile)"
  pkg_block="$(awk '/#safehouse-test-id:pkg-path-metadata#/ { capture=1 } capture { sub(/;;.*/, ""); $1=$1; print } capture && $0 == ")" { exit }' <<<"$profile")"

  [ "$pkg_block" = '(allow file-read-metadata
(literal "/pkg/env/global")
)' ]
}

@test "[EXECUTION] node can spawn by name past the macOS pkg PATH entry" { # issue #197
  local node_bin
  sft_require_cmd_or_skip node
  [ -d /pkg/env/global ] || skip "macOS pkg environment is not present"
  node_bin="$(env HOME="$SAFEHOUSE_HOST_HOME" node -p 'process.execPath')" || return 1

  safehouse_run_env HOME="$SAFEHOUSE_HOST_HOME" -- -- "$node_bin" -e '
    const assert = require("node:assert/strict");
    const {spawn, spawnSync} = require("node:child_process");
    process.env.PATH = "/pkg/env/global/bin:/usr/bin:/bin";
    const result = spawnSync("true");
    assert.ifError(result.error);
    assert.equal(result.status, 0);
    const child = spawn("true");
    child.on("error", error => { throw error; });
    child.on("close", status => assert.equal(status, 0));
  '
  [ "$status" -eq 0 ]
}

@test "[EXECUTION] pkg lookup traverses a populated symlinked environment without opening its contents" { # issue #197
  local node_bin pkg_root profile_path
  sft_require_cmd_or_skip node
  node_bin="$(env HOME="$SAFEHOUSE_HOST_HOME" node -p 'process.execPath')" || return 1
  pkg_root="$(sft_external_dir pkg)"
  profile_path="$(sft_workspace_path pkg.sb)"

  mkdir -p "$pkg_root/env" "$pkg_root/inv/envs/test-env/bin" "$pkg_root/etc"
  ln -s "$pkg_root/inv/envs/test-env" "$pkg_root/env/global"
  printf 'secret\n' >"$pkg_root/inv/envs/test-env/bin/sentinel"
  printf 'secret\n' >"$pkg_root/etc/secret"

  # Exercise the assembled /pkg rules against a writable fixture outside the
  # workspace. Never create files in the host's system-managed /pkg tree.
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_profile | sed "s|\"/pkg|\"${pkg_root}|g" >"$profile_path"
  # Template literals below are JavaScript, not shell expansions.
  # shellcheck disable=SC2016
  run /usr/bin/sandbox-exec -f "$profile_path" "$node_bin" -e '
    const assert = require("node:assert/strict");
    const fs = require("node:fs");
    const {spawnSync} = require("node:child_process");
    const root = process.argv[1];
    process.env.PATH = `${root}/env/global/bin:/usr/bin:/bin`;
    const result = spawnSync("true");
    assert.ifError(result.error);
    assert.equal(result.status, 0);
    assert(fs.lstatSync(`${root}/env/global`).isSymbolicLink());
    const denied = operation => assert.throws(operation, {code: "EPERM"});
    denied(() => fs.lstatSync(root));
    denied(() => fs.lstatSync(`${root}/env`));
    denied(() => fs.readdirSync(root));
    denied(() => fs.statSync(`${root}/etc`));
    denied(() => fs.statSync(`${root}/inv/envs/test-env`));
    denied(() => fs.statSync(`${root}/env/global/bin/sentinel`));
    denied(() => fs.readFileSync(`${root}/etc/secret`));
    denied(() => fs.readFileSync(`${root}/env/global/bin/sentinel`));
    denied(() => fs.writeFileSync(`${root}/planted`, "x"));
    denied(() => fs.writeFileSync(`${root}/env/global/bin/planted`, "x"));
    denied(() => fs.writeFileSync(`${root}/env/global/bin/sentinel`, "changed"));
  ' "$pkg_root"
  [ "$status" -eq 0 ]
  sft_assert_file_content "$pkg_root/inv/envs/test-env/bin/sentinel" "secret"
  sft_assert_path_absent "$pkg_root/planted"
  sft_assert_path_absent "$pkg_root/env/global/bin/planted"
}
