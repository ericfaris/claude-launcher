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

# Launch-time sanitization: a stray lone q in the config never reaches claude,
# even for a hand-edited config that never round-trips through the matrix.
reset_config
print -r -- "default_flags=--dangerously-skip-permissions q" >> "$LC_CONFIG_FILE"
print -r -- "alpha=q --model opus q" >> "$LC_CONFIG_FILE"
assert_eq "default_flags strips a stray lone q at launch" \
    "--dangerously-skip-permissions" "$(_lc_flags_for some-random-project)"
assert_eq "per-project override strips stray lone q tokens at launch" \
    "--model opus" "$(_lc_flags_for alpha)"

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

# Matrix row numbers: 1=YOLO 2=--continue ... 10=--model 11=--effort
# Flow: main menu '1' opens the default-flags matrix; toggle rows; 'q' exits the
# matrix; 'q' exits config.

# Toggle YOLO on via the matrix (row 1)
reset_config
printf '1\n1\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "matrix toggles YOLO default on" \
    "--dangerously-skip-permissions" "$(_lc_config_get default_flags)"

# Toggle YOLO off again (row 1)
printf '1\n1\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "matrix toggles YOLO default off" "" "$(_lc_config_get default_flags)"

# Set a value flag via the matrix: --model (row 10) -> opus
reset_config
printf '1\n10\nopus\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "matrix sets value flag --model" "--model opus" "$(_lc_config_get default_flags)"

# Cancel a value-flag prompt with 'q' leaves existing value untouched
reset_config
_lc_config_set default_flags "--dangerously-skip-permissions"
printf '1\n10\nq\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "matrix value-flag prompt 'q' cancels (unchanged)" \
    "--dangerously-skip-permissions" "$(_lc_config_get default_flags)"

# Custom/other flags via 'e' are preserved alongside toggled flags
reset_config
printf '1\ne\n--foo\n2\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "matrix preserves custom flags when toggling" \
    "--continue --foo" "$(_lc_config_get default_flags)"

# Per-project: main '2', pick #1 (alpha), then matrix row 1 (YOLO)
reset_config
printf '2\n1\n1\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "per-project YOLO via matrix" \
    "--dangerously-skip-permissions" "$(_lc_config_get alpha)"

# Per-project plain claude via 'x' = empty override
reset_config
printf '2\n1\nx\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
out="$(_lc_config_get alpha)"; rc=$?
assert_eq "per-project 'x' sets empty override" "" "$out"
assert_rc "...and the key is present (rc 0)" 0 "$rc"

# Per-project custom flags via 'e'
printf '2\n1\ne\n--continue --model opus\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "per-project custom flags via matrix 'e'" \
    "--continue --model opus" "$(_lc_config_get alpha)"

# Cancel custom-flags 'e' prompt with 'q' leaves override untouched
printf '2\n1\ne\nq\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "per-project 'e' prompt 'q' cancels (unchanged)" \
    "--continue --model opus" "$(_lc_config_get alpha)"

# Per-project inherit via 'r' removes the override
printf '2\n1\nr\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
_lc_config_get alpha >/dev/null; rc=$?
assert_rc "per-project 'r' inherit removes override" 1 "$rc"

# ---------------------------------------------------------------------------
print -r -- ""
print -r -- "stray 'q' can never be saved as a flag"

# A lone 'q' typed into the custom-flags ('e') prompt must be dropped, not saved.
reset_config
printf '1\ne\n--foo q\n2\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "custom-flags input strips a trailing lone q" \
    "--continue --foo" "$(_lc_config_get default_flags)"

# 'q' interspersed with real flags is also stripped.
reset_config
printf '1\ne\nq --foo q --bar q\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "custom-flags input strips all lone q tokens" \
    "--foo --bar" "$(_lc_config_get default_flags)"

# An already-corrupted config self-heals: the matrix drops the stray q on the
# next save (toggling --continue on here).
reset_config
_lc_config_set default_flags "--dangerously-skip-permissions q"
printf '1\n2\nq\nq\n' | _lc_configure "$PROJECTS_DIR" "${DIRS[@]}" >/dev/null
assert_eq "existing stray q is dropped on next save" \
    "--dangerously-skip-permissions --continue" "$(_lc_config_get default_flags)"

# ---------------------------------------------------------------------------
print -r -- ""
print -r -- "──────────────────────────────"
print -r -- "  PASS: $PASS   FAIL: $FAIL"
(( FAIL == 0 )) && exit 0 || exit 1
