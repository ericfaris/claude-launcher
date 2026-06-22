#!/usr/bin/env zsh
# Tests for claude-launcher config + per-project flags.
# Run with:  zsh tests/test-config.zsh
#
# These tests exercise the pure config helpers (_lc_config_get/set/unset,
# _lc_flags_for) and drive the interactive _lc_configure walkthrough by piping
# menu selections to it. No real `claude` binary is invoked.

emulate -L zsh
setopt no_unset 2>/dev/null

SCRIPT_DIR="${0:A:h}"
LAUNCHER="${SCRIPT_DIR}/../claude-launcher.sh"

# Isolate config under a temp dir for the whole run.
TMPDIR_TEST="$(mktemp -d)"
export LC_CONFIG_FILE="${TMPDIR_TEST}/config"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

source "$LAUNCHER"

typeset -i PASS=0 FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        print -r -- "  ✓ $desc"
        (( PASS++ ))
    else
        print -r -- "  ✗ $desc"
        print -r -- "      expected: [$expected]"
        print -r -- "      actual:   [$actual]"
        (( FAIL++ ))
    fi
}

assert_rc() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        print -r -- "  ✓ $desc"
        (( PASS++ ))
    else
        print -r -- "  ✗ $desc (expected rc=$expected got rc=$actual)"
        (( FAIL++ ))
    fi
}

reset_config() { rm -f "$LC_CONFIG_FILE"; }

# ---------------------------------------------------------------------------
print -r -- "_lc_config_get"
reset_config
print -r -- "default_flags=--dangerously-skip-permissions" >> "$LC_CONFIG_FILE"
print -r -- "goose-cli=" >> "$LC_CONFIG_FILE"
print -r -- "# a comment" >> "$LC_CONFIG_FILE"
print -r -- "dev-dashboard=--model opus" >> "$LC_CONFIG_FILE"

assert_eq "reads a present value" "--dangerously-skip-permissions" "$(_lc_config_get default_flags)"
out="$(_lc_config_get goose-cli)"; rc=$?
assert_eq "present-but-empty value yields empty string" "" "$out"
assert_rc "present-but-empty key returns rc 0" 0 "$rc"
_lc_config_get nonexistent >/dev/null; rc=$?
assert_rc "absent key returns rc 1" 1 "$rc"
assert_eq "ignores comment lines" "--model opus" "$(_lc_config_get dev-dashboard)"

reset_config
_lc_config_get default_flags >/dev/null; rc=$?
assert_rc "missing file returns rc 1" 1 "$rc"

# ---------------------------------------------------------------------------
print -r -- ""
print -r -- "_lc_flags_for"
reset_config
print -r -- "default_flags=--dangerously-skip-permissions" >> "$LC_CONFIG_FILE"
print -r -- "goose-cli=" >> "$LC_CONFIG_FILE"
print -r -- "dev-dashboard=--model opus --verbose" >> "$LC_CONFIG_FILE"

assert_eq "unconfigured project inherits default_flags" \
    "--dangerously-skip-permissions" "$(_lc_flags_for some-random-project)"
assert_eq "empty override disables the default (plain claude)" \
    "" "$(_lc_flags_for goose-cli)"
assert_eq "per-project override wins over default" \
    "--model opus --verbose" "$(_lc_flags_for dev-dashboard)"

reset_config
assert_eq "no config file -> no flags" "" "$(_lc_flags_for anything)"

# ---------------------------------------------------------------------------
print -r -- ""
print -r -- "_lc_config_set / _lc_config_unset"
reset_config
_lc_config_set default_flags "--dangerously-skip-permissions"
assert_eq "set creates file + value" \
    "--dangerously-skip-permissions" "$(_lc_config_get default_flags)"

_lc_config_set default_flags "--model opus"
assert_eq "set updates existing key in place" \
    "--model opus" "$(_lc_config_get default_flags)"

_lc_config_set myproj "--foo"
assert_eq "set preserves other keys" "--model opus" "$(_lc_config_get default_flags)"
assert_eq "set adds new key" "--foo" "$(_lc_config_get myproj)"

# value with characters that would break a naive sed
_lc_config_set tricky 'a & b | c'
assert_eq "set handles special characters verbatim" 'a & b | c' "$(_lc_config_get tricky)"

_lc_config_unset myproj
_lc_config_get myproj >/dev/null; rc=$?
assert_rc "unset removes the key" 1 "$rc"
assert_eq "unset preserves other keys" "--model opus" "$(_lc_config_get default_flags)"

# ---------------------------------------------------------------------------
print -r -- ""
print -r -- "_lc_configure (interactive walkthrough)"
PROJECTS_DIR="${TMPDIR_TEST}/projects"
mkdir -p "$PROJECTS_DIR/alpha" "$PROJECTS_DIR/beta"
DIRS=("$PROJECTS_DIR/alpha" "$PROJECTS_DIR/beta")

# Toggle YOLO on (option 1), then Done (q)
reset_config
printf '1\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "toggle enables YOLO default" \
    "--dangerously-skip-permissions" "$(_lc_config_get default_flags)"

# Toggle YOLO off again
printf '1\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "toggle disables YOLO default" "" "$(_lc_config_get default_flags)"

# Set arbitrary default flags (option 2)
reset_config
printf '2\n--model opus\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "set default flags via walkthrough" "--model opus" "$(_lc_config_get default_flags)"

# Configure a specific project: pick #1 (alpha) -> YOLO (sub-option 1)
reset_config
printf '3\n1\n1\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "per-project YOLO via walkthrough" \
    "--dangerously-skip-permissions" "$(_lc_config_get alpha)"

# Configure project alpha -> Plain claude (sub-option 2) = empty override
printf '3\n1\n2\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
out="$(_lc_config_get alpha)"; rc=$?
assert_eq "per-project plain claude sets empty override" "" "$out"
assert_rc "...and the key is present (rc 0)" 0 "$rc"

# Configure project alpha -> Custom flags (sub-option 3)
printf '3\n1\n3\n--continue --model opus\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "per-project custom flags via walkthrough" \
    "--continue --model opus" "$(_lc_config_get alpha)"

# Configure project alpha -> Inherit default (sub-option 4) removes override
printf '3\n1\n4\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
_lc_config_get alpha >/dev/null; rc=$?
assert_rc "per-project inherit-default removes override" 1 "$rc"

# ---------------------------------------------------------------------------
print -r -- ""
print -r -- "──────────────────────────────"
print -r -- "  PASS: $PASS   FAIL: $FAIL"
(( FAIL == 0 )) && exit 0 || exit 1
