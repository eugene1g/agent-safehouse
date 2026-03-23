# shellcheck shell=bash
# shellcheck disable=SC2154

cli_print_version() {
  printf '%s %s\n' "$safehouse_project_name" "$safehouse_project_version"
}

cli_print_usage() {
  policy_ensure_feature_catalog_initialized || return 1

  cat <<USAGE
${safehouse_project_name} ${safehouse_project_version}

Usage:
  $(basename "$0") update [--head]
  $(basename "$0") [policy options]
  $(basename "$0") [policy options] [--] <command> [args...]

Summary:
  Agent Safehouse is a macOS sandbox toolkit for coding agents and CLIs.
  It composes a deny-by-default sandbox-exec policy with scoped allows.

How to use this CLI:
  1) Policy mode (no command):
     Generates a policy file and prints the filename.
     Use --stdout to print the policy text instead.
     You can pass that file to your own sandbox-exec invocation.
  2) Execute mode (command provided):
     Generates a policy and runs the command inside that policy.

Common examples:
  # Update a standalone safehouse install in place
  $(basename "$0") update

  # Update from the latest main branch dist build
  $(basename "$0") update --head

  # Generate policy file path
  $(basename "$0")

  # Print policy text to stdout
  $(basename "$0") --stdout

  # Generate policy path and run your own sandbox-exec command
  sandbox-exec -f "\$($(basename "$0"))" -- /usr/bin/true

  # Run a command under Safehouse policy
  $(basename "$0") claude --dangerously-skip-permissions
  $(basename "$0") --enable=docker docker ps

  # Pass one-off child env vars to the wrapped command
  $(basename "$0") -- MYVAR=123 printenv MYVAR

Policy scope options:
  --enable FEATURES
  --enable=FEATURES
      Comma-separated optional features to enable
      Supported values: ${policy_supported_enable_features}
      Note: electron implies macos-gui
      Note: chromium-full implies chromium-headless
      Note: playwright-chrome implies chromium-full and chromium-headless
      Note: agent-browser implies chromium-full and chromium-headless
      Note: shell-init enables shell startup file reads
      Note: process-control enables host process enumeration/signalling
      Note: lldb enables LLDB toolchain + task-port access and implies process-control
      Note: xcode enables Xcode developer roots plus scoped build/simulator state
      Note: all-agents loads every 60-agents profile
      Note: all-apps loads every 65-apps profile
      Note: wide-read grants read-only visibility across / (broad; use cautiously)

  --env
      Execute wrapped command with full inherited environment variables

  --env=FILE
      Execute wrapped command with sanitized env allowlist plus vars loaded
      by sourcing FILE (FILE values override sanitized defaults)
      FILE is sourced by /bin/bash (trusted shell input, not dotenv parsing)

  --env-pass NAMES
  --env-pass=NAMES
      Comma-separated env variable names to pass through from host env
      on top of sanitized defaults (repeatable; names are deduplicated)
      Compatible with default mode and --env=FILE; incompatible with --env

  --add-dirs-ro PATHS
  --add-dirs-ro=PATHS
      Colon-separated file/directory paths to grant read-only access

  --add-dirs PATHS
  --add-dirs=PATHS
      Colon-separated file/directory paths to grant read/write access

  --workdir DIR
  --workdir=DIR
      Main directory to grant read/write access
      Empty string disables automatic workdir grants

  --trust-workdir-config
  --trust-workdir-config=BOOL
      Trust and load <workdir>/.safehouse (default: disabled)

  --append-profile PATH
  --append-profile=PATH
      Append an additional sandbox profile file after generated rules
      Repeatable; files are appended in argument order

  --allow-profile-writes
      Skip automatic deny-write rules for appended profile files.
      By default, Safehouse emits a deny file-write* rule for each
      --append-profile path so agents cannot modify loaded policy files.
      Use this flag if you intentionally want the sandboxed process to
      be able to write to appended profile files.

  --output PATH
  --output=PATH
      Write policy to a specific file path

Output options:
  --stdout
      Print policy text to stdout (do not execute command)

  --explain
      Print effective workdir/grants/profile selection summary to stderr

General:
  update [--head]
      Download the latest safehouse.sh release asset and replace this script
      Use --head to download dist/safehouse.sh from the main branch instead
      Standalone installs only; use brew upgrade agent-safehouse for Homebrew

  --version
      Show project version

  -h, --help
      Show this help

Environment:
  SAFEHOUSE_ADD_DIRS_RO
      Colon-separated read-only paths (same format as --add-dirs-ro)

  SAFEHOUSE_ADD_DIRS
      Colon-separated read/write paths (same format as --add-dirs)

  SAFEHOUSE_WORKDIR
      Workdir override (same behavior as --workdir, including empty string)

  SAFEHOUSE_TRUST_WORKDIR_CONFIG
      Trust and load <workdir>/.safehouse (1/0, true/false, yes/no, on/off)

  SAFEHOUSE_ENV_PASS
      Comma-separated env var names to pass through (same format as --env-pass)

  SAFEHOUSE_SELF_UPDATE_URL
      Override update source for the update subcommand
      Advanced use: accepts an asset URL or local file path

Config file:
  <workdir>/.safehouse (optional, loaded only when trusted)
      Supports keys:
        add-dirs-ro=PATHS
        add-dirs=PATHS
USAGE
}
