# Debugging Sandbox Denials

Use `/usr/bin/log` (not shell-shadowed `log`) for denial analysis.

## Live Stream Denials

```bash
/usr/bin/log stream --style compact --predicate 'eventMessage CONTAINS "Sandbox:" AND eventMessage CONTAINS "deny("'
```

## Filter by Specific Agent/PID Pattern

```bash
/usr/bin/log stream --style compact --predicate 'eventMessage CONTAINS "Sandbox: 2.1.34(" AND eventMessage CONTAINS "deny("'
```

## Kernel-Level Denials

```bash
/usr/bin/log stream --style compact --info --debug --predicate '(processID == 0) AND (senderImagePath CONTAINS "/Sandbox")'
```

## Recent History

```bash
/usr/bin/log show --last 2m --style compact --predicate 'process == "sandboxd"'
```

## Filter Common Noise

```bash
/usr/bin/log stream --style compact \
  --predicate 'eventMessage CONTAINS "Sandbox:" AND eventMessage CONTAINS "deny(" AND NOT eventMessage CONTAINS "duplicate report" AND NOT eventMessage CONTAINS "/dev/dtracehelper" AND NOT eventMessage CONTAINS "apple.shm.notification_center" AND NOT eventMessage CONTAINS "com.apple.diagnosticd" AND NOT eventMessage CONTAINS "com.apple.analyticsd"'
```

Suppress dtracehelper source noise:

```bash
DYLD_USE_DTRACE=0 sandbox-exec ...
```

Correlate denials with filesystem activity:

```bash
sudo fs_usage -w -f filesystem <pid> | grep -iE "open|create|write|rename"
```

## Converting Deny Logs to Allow Rules

Deny line format:

`deny(<pid>) <operation> <path-or-name>`

| Deny type | Allow rule pattern |
|-----------|--------------------|
| file ops | `(allow <operation> (literal "<path>"))` |
| sysctl | `(allow sysctl-read (sysctl-name "<name>"))` |
| mach | `(allow mach-lookup (global-name "<name>"))` |
| network | `(allow network-<op> (local ip "localhost:*"))` |

## Building a Profile from Scratch

1. Start with `(version 1)` and `(deny default)`.
2. Run with log stream active in another terminal.
3. Map each `deny(...)` event to the minimum allow rule.
4. Repeat until required startup/workflows pass.

Exercise full toolchain workflows (`git`, `npm`, `cargo`, etc.) since child processes inherit sandbox policy.
