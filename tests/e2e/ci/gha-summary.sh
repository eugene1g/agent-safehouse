#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"
AGENT_PROFILES_DIR="${REPO_ROOT}/profiles/60-agents"

TUI_LOG="${1:-}"
LIVE_LOG="${2:-}"

SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-}"
if [[ -z "${SUMMARY_FILE}" ]]; then
	SUMMARY_FILE="/dev/stdout"
fi

append() {
	printf '%s\n' "$*" >>"${SUMMARY_FILE}"
}

list_profiles_to_file() {
	local out_file="$1"

	if command -v fd >/dev/null 2>&1; then
		fd -t f '\.sb$' "${AGENT_PROFILES_DIR}" | sort | while IFS= read -r p; do
			[[ -n "${p}" ]] || continue
			basename "${p}" .sb
		done >"${out_file}"
		return 0
	fi

	find "${AGENT_PROFILES_DIR}" -type f -name '*.sb' | sort | while IFS= read -r p; do
		[[ -n "${p}" ]] || continue
		basename "${p}" .sb
	done >"${out_file}"
}

profiles_file="$(mktemp /tmp/safehouse-e2e-profiles.XXXXXX)"
trap 'rm -f "${profiles_file}"' EXIT
list_profiles_to_file "${profiles_file}"

append "## E2E Report"
append ""

append "### TUI (tmux)"
if [[ -f "${TUI_LOG}" ]]; then
	append ""
	append "Log: \`${TUI_LOG}\`"
	append ""
	perl -e '
use strict;
use warnings;

my ($profiles_path, $log_path) = @ARGV;
my %res;

if (-f $log_path) {
  open my $fh, "<", $log_path or die "open $log_path: $!";
  while (my $line = <$fh>) {
    chomp $line;
    next unless $line =~ /^(PASS|FAIL): \[([^\]]+)\] (.*)$/;
    my ($status, $meta, $msg) = ($1, $2, $3);
    my ($profile, $cmd) = split(/ -> /, $meta, 2);
    next unless defined $profile && length $profile;
    $res{$profile} = { cmd => ($cmd // ""), status => $status, msg => $msg };
  }
  close $fh;
}

open my $pf, "<", $profiles_path or die "open $profiles_path: $!";
my @profiles;
while (my $p = <$pf>) {
  chomp $p;
  next unless length $p;
  push @profiles, $p;
}
close $pf;

my ($pass, $fail, $missing) = (0, 0, 0);
for my $p (@profiles) {
  my $r = $res{$p};
  if (!$r) { $missing++; next; }
  if ($r->{status} eq "PASS") { $pass++; next; }
  if ($r->{status} eq "FAIL") { $fail++; next; }
  $missing++;
}

print "- Total profiles: " . scalar(@profiles) . "\n";
print "- PASS: $pass\n";
print "- FAIL: $fail\n";
print "- MISSING: $missing\n" if $missing;
print "\n";

print "| Profile | Command | Result | Details |\n";
print "| --- | --- | --- | --- |\n";
for my $p (@profiles) {
  my $r = $res{$p} || { cmd => "", status => "MISSING", msg => "No PASS/FAIL line found in log" };
  my $details = ($r->{status} eq "PASS") ? "" : ($r->{msg} // "");
  $details =~ s/\|/\\|/g;
  my $cmd = $r->{cmd} // "";
  $cmd =~ s/\|/\\|/g;
  print "| `$p` | `$cmd` | **$r->{status}** | $details |\n";
}
' "${profiles_file}" "${TUI_LOG}" >>"${SUMMARY_FILE}"
else
	append ""
	append "_No TUI log found._"
fi

append ""
append "### Live LLM"
if [[ -f "${LIVE_LOG}" ]]; then
	append ""
	append "Log: \`${LIVE_LOG}\`"
	append ""
	perl -e '
use strict;
use warnings;

my ($profiles_path, $log_path) = @ARGV;
my %res;
my $runner_summary = "";

if (-f $log_path) {
  open my $fh, "<", $log_path or die "open $log_path: $!";
  while (my $line = <$fh>) {
    chomp $line;
    if ($line =~ /^Live LLM E2E summary: (.*)$/) {
      $runner_summary = $1;
      next;
    }
    next unless $line =~ /^(PASS|FAIL|SKIP): \[([^\]]+)\] (.*)$/;
    my ($status, $profile, $msg) = ($1, $2, $3);
    next unless defined $profile && length $profile;
    $res{$profile} = { status => $status, msg => $msg };
  }
  close $fh;
}

open my $pf, "<", $profiles_path or die "open $profiles_path: $!";
my @profiles;
while (my $p = <$pf>) {
  chomp $p;
  next unless length $p;
  push @profiles, $p;
}
close $pf;

my ($pass, $fail, $skip, $missing) = (0, 0, 0, 0);
for my $p (@profiles) {
  my $r = $res{$p};
  if (!$r) { $missing++; next; }
  if ($r->{status} eq "PASS") { $pass++; next; }
  if ($r->{status} eq "FAIL") { $fail++; next; }
  if ($r->{status} eq "SKIP") { $skip++; next; }
  $missing++;
}

print "- Total profiles: " . scalar(@profiles) . "\n";
print "- PASS: $pass\n";
print "- SKIP: $skip\n";
print "- FAIL: $fail\n";
print "- MISSING: $missing\n" if $missing;
print "- Runner summary: $runner_summary\n" if length $runner_summary;
print "\n";

print "| Profile | Result | Details |\n";
print "| --- | --- | --- |\n";
for my $p (@profiles) {
  my $r = $res{$p} || { status => "MISSING", msg => "No PASS/SKIP/FAIL line found in log" };
  my $details = ($r->{status} eq "PASS") ? "" : ($r->{msg} // "");
  $details =~ s/\|/\\|/g;
  print "| `$p` | **$r->{status}** | $details |\n";
}
' "${profiles_file}" "${LIVE_LOG}" >>"${SUMMARY_FILE}"
else
	append ""
	append "_Live LLM E2E was not run (step skipped or log missing)._"
fi
