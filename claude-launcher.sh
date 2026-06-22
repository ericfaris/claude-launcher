#!/usr/bin/env bash
# Pre-Claude project launcher
# Source this file from ~/.zshrc:
#   source ~/projects/claude-launcher/claude-launcher.sh
#
# Optionally set LC_PROJECTS_DIR to override the default root folder:
#   export LC_PROJECTS_DIR="$HOME/dev"   # defaults to ~/projects
#
# Optionally configure per-project claude flags in ~/.claude-launcher-config:
#   default_flags=--dangerously-skip-permissions   # applied to every project
#   myproject=--model opus                          # per-project override
# (override LC_CONFIG_FILE to point at a different file)
#
# Then run with:  lc
# Or auto-launch by adding to ~/.zshrc:
#   [[ "$(pwd)" == "$LC_PROJECTS_DIR" ]] && lc

_LC_TAB_TITLE=""

_lc_set_title() {
    local title="$1"
    _LC_TAB_TITLE="$title"
    # OSC 0 sets tab/window title; use ST terminator for Windows Terminal compatibility
    printf '\033]0;%s\033\\' "$title"
}

_lc_precmd() {
    [[ -n "$_LC_TAB_TITLE" ]] && printf '\033]0;%s\033\\' "$_LC_TAB_TITLE"
}

# Register precmd hook so the title persists across prompt redraws
# (needed when a zsh framework like oh-my-zsh resets the title on each prompt)
if [[ -n "$ZSH_VERSION" ]] && (( ${precmd_functions[(I)_lc_precmd]:-0} == 0 )); then
    precmd_functions+=(_lc_precmd)
fi

# Read a value from the config file. Prints the value and returns 0 if the key
# exists (even when its value is empty); returns 1 if the key is absent.
# Config format (~/.claude-launcher-config), one key=value per line:
#   default_flags=--dangerously-skip-permissions   # applied to every project
#   <project-name>=<flags>                          # per-project override
# Lines starting with # and blank lines are ignored.
_lc_config_get() {
    local name="$1" cfg="${LC_CONFIG_FILE:-$HOME/.claude-launcher-config}"
    [[ -f "$cfg" ]] || return 1
    local key val
    while IFS='=' read -r key val; do
        [[ "$key" == "#"* || -z "$key" ]] && continue
        # trim surrounding whitespace from the key
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        [[ "$key" == "$name" ]] && { printf '%s' "$val"; return 0; }
    done < "$cfg"
    return 1
}

# Resolve the claude flags for a project name. A per-project override wins
# (even if empty, to disable inherited defaults); otherwise default_flags;
# otherwise nothing.
_lc_flags_for() {
    local name="$1" flags
    if flags="$(_lc_config_get "$name")"; then
        printf '%s' "$flags"
        return 0
    fi
    _lc_config_get default_flags
}

# Set a key=value in the config file, rewriting in place (no sed, so flag
# values with arbitrary characters are safe). Creates the file if needed.
_lc_config_set() {
    local key="$1" val="$2" cfg="${LC_CONFIG_FILE:-$HOME/.claude-launcher-config}"
    local tmp="${cfg}.tmp.$$" found=0 line k
    : > "$tmp"
    if [[ -f "$cfg" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            k="${line%%=*}"
            if [[ "$line" == *"="* && "$k" == "$key" ]]; then
                printf '%s=%s\n' "$key" "$val" >> "$tmp"
                found=1
            else
                printf '%s\n' "$line" >> "$tmp"
            fi
        done < "$cfg"
    fi
    (( found == 0 )) && printf '%s=%s\n' "$key" "$val" >> "$tmp"
    mv "$tmp" "$cfg"
}

# Remove a key entirely from the config file (so a project re-inherits the
# default, as opposed to setting an empty override).
_lc_config_unset() {
    local key="$1" cfg="${LC_CONFIG_FILE:-$HOME/.claude-launcher-config}"
    [[ -f "$cfg" ]] || return 0
    local tmp="${cfg}.tmp.$$" line k
    : > "$tmp"
    while IFS= read -r line || [[ -n "$line" ]]; do
        k="${line%%=*}"
        [[ "$line" == *"="* && "$k" == "$key" ]] && continue
        printf '%s\n' "$line" >> "$tmp"
    done < "$cfg"
    mv "$tmp" "$cfg"
}

# Interactive configuration walkthrough. Loops until the user chooses Done.
_lc_configure() {
    local projects_dir="$1"; shift
    local -a dirs=("$@")
    local cfg="${LC_CONFIG_FILE:-$HOME/.claude-launcher-config}"

    local c_line=$'\e[38;5;240m'
    local c_title=$'\e[38;5;111m'
    local c_num=$'\e[38;5;242m'
    local c_dim=$'\e[38;5;242m'
    local c_val=$'\e[38;5;215m'
    local c_prompt=$'\e[38;5;111m'
    local c_ok=$'\e[38;5;114m'
    local c_reset=$'\e[0m'
    local yolo='--dangerously-skip-permissions'

    while true; do
        local cur_default
        cur_default="$(_lc_config_get default_flags)" || cur_default=""

        echo ""
        printf "  %s──%s %sConfiguration%s %s───────────────%s\n" \
            "$c_line" "$c_reset" "$c_title" "$c_reset" "$c_line" "$c_reset"
        echo ""
        printf "  %sConfig file:%s   %s\n" "$c_dim" "$c_reset" "$cfg"
        printf "  %sDefault flags:%s %s%s%s\n" \
            "$c_dim" "$c_reset" "$c_val" "${cur_default:-<none — plain claude>}" "$c_reset"
        echo ""
        printf "  %s%2s%s  Toggle YOLO default (%s)\n" "$c_num" "1" "$c_reset" "$yolo"
        printf "  %s%2s%s  Set default flags for ALL projects\n" "$c_num" "2" "$c_reset"
        printf "  %s%2s%s  Configure a specific project\n" "$c_num" "3" "$c_reset"
        printf "  %s%2s%s  View raw config file\n" "$c_num" "4" "$c_reset"
        printf "  %s%2s%s  Done\n" "$c_num" "q" "$c_reset"
        echo ""
        printf "  %s›%s " "$c_prompt" "$c_reset"

        local sel
        read -r sel
        echo ""

        case "$sel" in
            1)
                if [[ " $cur_default " == *" $yolo "* ]]; then
                    local new="" tok
                    for tok in ${=cur_default}; do
                        [[ "$tok" == "$yolo" ]] && continue
                        new="${new:+$new }$tok"
                    done
                    _lc_config_set default_flags "$new"
                    printf "  %s✓ YOLO disabled by default.%s\n" "$c_ok" "$c_reset"
                else
                    _lc_config_set default_flags "${cur_default:+$cur_default }$yolo"
                    printf "  %s✓ YOLO enabled by default — all projects skip permission prompts.%s\n" "$c_ok" "$c_reset"
                fi
                ;;
            2)
                printf "  Enter flags applied to ALL projects (blank = none): "
                local nf
                read -r nf
                _lc_config_set default_flags "$nf"
                printf "  %s✓ Default flags set to: %s%s\n" "$c_ok" "${nf:-<none>}" "$c_reset"
                ;;
            3)
                if [[ ${#dirs[@]} -eq 0 ]]; then
                    printf "  %sNo projects found under %s%s\n" "$c_dim" "$projects_dir" "$c_reset"
                    continue
                fi
                local i=1 d
                for d in "${dirs[@]}"; do
                    printf "  %s%2d%s  %s\n" "$c_num" "$i" "$c_reset" "$(basename "$d")"
                    ((i++))
                done
                printf "  Select a project number: "
                local pnum
                read -r pnum
                echo ""
                if ! [[ "$pnum" =~ ^[0-9]+$ ]] || (( pnum < 1 || pnum > ${#dirs[@]} )); then
                    printf "  %sInvalid selection.%s\n" "$c_dim" "$c_reset"
                    continue
                fi
                local pname
                pname="$(basename "${dirs[$pnum]}")"
                local cur_proj have_proj=0
                if cur_proj="$(_lc_config_get "$pname")"; then have_proj=1; fi
                printf "  %s%s%s currently: %s%s%s\n" \
                    "$c_val" "$pname" "$c_reset" "$c_val" \
                    "$( (( have_proj )) && printf '%s' "${cur_proj:-<empty — plain claude>}" || printf '<inherits default>' )" \
                    "$c_reset"
                echo ""
                printf "  %s%2s%s  YOLO (%s)\n" "$c_num" "1" "$c_reset" "$yolo"
                printf "  %s%2s%s  Plain claude (no flags, ignore default)\n" "$c_num" "2" "$c_reset"
                printf "  %s%2s%s  Custom flags\n" "$c_num" "3" "$c_reset"
                printf "  %s%2s%s  Inherit default (remove override)\n" "$c_num" "4" "$c_reset"
                printf "  %s›%s " "$c_prompt" "$c_reset"
                local psel
                read -r psel
                echo ""
                case "$psel" in
                    1) _lc_config_set "$pname" "$yolo"
                       printf "  %s✓ %s → YOLO.%s\n" "$c_ok" "$pname" "$c_reset" ;;
                    2) _lc_config_set "$pname" ""
                       printf "  %s✓ %s → plain claude.%s\n" "$c_ok" "$pname" "$c_reset" ;;
                    3) printf "  Enter flags for %s: " "$pname"
                       local cf
                       read -r cf
                       _lc_config_set "$pname" "$cf"
                       printf "  %s✓ %s → %s%s\n" "$c_ok" "$pname" "${cf:-<none>}" "$c_reset" ;;
                    4) _lc_config_unset "$pname"
                       printf "  %s✓ %s now inherits the default.%s\n" "$c_ok" "$pname" "$c_reset" ;;
                    *) printf "  %sNo change.%s\n" "$c_dim" "$c_reset" ;;
                esac
                ;;
            4)
                if [[ -s "$cfg" ]]; then
                    printf "  %s── %s ──%s\n" "$c_dim" "$cfg" "$c_reset"
                    local line
                    while IFS= read -r line || [[ -n "$line" ]]; do
                        printf "  %s\n" "$line"
                    done < "$cfg"
                else
                    printf "  %s(config file is empty or does not exist)%s\n" "$c_dim" "$c_reset"
                fi
                ;;
            q|Q|"")
                return 0
                ;;
            *)
                printf "  %sUnknown option.%s\n" "$c_dim" "$c_reset"
                ;;
        esac
    done
}

_lc_icon_read() {
    local name="$1" cache="$HOME/.claude-launcher-icons"
    [[ -f "$cache" ]] || return 1
    while IFS='=' read -r key val; do
        [[ "$key" == "#"* || -z "$key" ]] && continue
        [[ "$key" == "$name" ]] && { printf '%s' "$val"; return 0; }
    done < "$cache"
    return 1
}

_lc_icon_write() {
    local name="$1" icon="$2" cache="$HOME/.claude-launcher-icons"
    if [[ -f "$cache" ]] && grep -q "^${name}=" "$cache"; then
        local tmp="${cache}.tmp.$$"
        sed "s|^${name}=.*|${name}=${icon}|" "$cache" > "$tmp" && mv "$tmp" "$cache"
    else
        printf '%s=%s\n' "$name" "$icon" >> "$cache"
    fi
}

_lc_icon_for() {
    local dir="$1"
    local name
    name="$(basename "$dir")"

    # Try cache first
    local cached
    if cached="$(_lc_icon_read "$name")"; then
        printf '%s' "$cached"
        return 0
    fi

    local fallback='󰉋'

    # Don't call Claude API if we're already inside Claude Code
    if [[ -n "$CLAUDECODE" ]]; then
        _lc_icon_write "$name" "$fallback"
        printf '%s' "$fallback"
        return 0
    fi

    # Call Claude to pick an icon
    local files icon
    files="$(ls -1 "$dir" 2>/dev/null | head -20)"
    local prompt="You are helping choose a single Nerd Font icon for a project directory.
Project name: ${name}
Top-level files: ${files}
Reply with ONLY a single Nerd Font icon character. No explanation, no punctuation, no newline."

    icon="$(claude -p "$prompt" 2>/dev/null | tr -d '[:space:]')"

    # Nerd Font icons are 1-3 chars; longer results are error messages
    if [[ -z "$icon" ]] || (( ${#icon} > 4 )); then
        icon="$fallback"
    fi

    _lc_icon_write "$name" "$icon"
    printf '%s' "$icon"
}

_lc_display() {
    local root_dir="$1"
    shift
    local -a dirs=("$@")

    local c_line=$'\e[38;5;240m'
    local c_title=$'\e[38;5;111m'
    local c_num=$'\e[38;5;242m'
    local c_icon=$'\e[38;5;215m'
    local c_prompt=$'\e[38;5;111m'
    local c_reset=$'\e[0m'

    local icon_terminal=$'\uf489'
    local icon_root=$'\uf07b'
    local icon_config=$'\uf013'

    echo ""
    printf "  %s──%s %sClaude Launcher%s %s──────────────%s\n" \
        "$c_line" "$c_reset" "$c_title" "$c_reset" "$c_line" "$c_reset"
    echo ""

    printf "  %s%2d%s  %s%s%s  %s\n" \
        "$c_num" 1 "$c_reset" "$c_icon" "$icon_terminal" "$c_reset" "terminal"
    printf "  %s%2d%s  %s%s%s  %s\n" \
        "$c_num" 2 "$c_reset" "$c_icon" "$icon_root" "$c_reset" "$(basename "$root_dir") (root)"

    if [[ ${#dirs[@]} -gt 0 ]]; then
        echo ""
        local i=3
        local dir name icon
        for dir in "${dirs[@]}"; do
            name="$(basename "$dir")"
            icon="$(_lc_icon_for "$dir")"
            printf "  %s%2d%s  %s%s%s  %s\n" \
                "$c_num" "$i" "$c_reset" "$c_icon" "$icon" "$c_reset" "$name"
            ((i++))
        done
    fi

    echo ""
    printf "  %s%2s%s  %s%s%s  %s\n" \
        "$c_num" "c" "$c_reset" "$c_icon" "$icon_config" "$c_reset" "configure"

    echo ""
    printf "  %s›%s " "$c_prompt" "$c_reset"
}

lc() {
    local projects_dir="${LC_PROJECTS_DIR:-$HOME/projects}"
    local -a dirs

    while IFS= read -r dir; do
        dirs+=("$dir")
    done < <(find "$projects_dir" -maxdepth 1 -mindepth 1 -type d | sort)

    _lc_display "$projects_dir" "${dirs[@]}"
    read -r choice
    echo ""

    local c_confirm=$'\e[38;5;242m'
    local c_reset=$'\e[0m'

    if [[ "$choice" == "c" || "$choice" == "C" ]]; then
        _lc_configure "$projects_dir" "${dirs[@]}"
        # Return to the menu after configuring
        lc
    elif [[ "$choice" == "1" ]]; then
        builtin cd "$projects_dir" || return 1
        _lc_set_title "$(basename "$projects_dir")"
        printf "  %s→ %s%s\n" "$c_confirm" "$(pwd)" "$c_reset"
        echo ""
    elif [[ "$choice" == "2" ]]; then
        builtin cd "$projects_dir" || return 1
        _lc_set_title "$(basename "$projects_dir")"
        printf "  %s→ %s%s\n" "$c_confirm" "$(pwd)" "$c_reset"
        echo ""
        local flags
        flags="$(_lc_flags_for "$(basename "$projects_dir")")"
        claude ${=flags}
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 3 && choice <= ${#dirs[@]} + 2 )); then
        local selected="${dirs[$((choice - 2))]}"
        builtin cd "$selected" || return 1
        _lc_set_title "$(basename "$selected")"
        printf "  %s→ %s%s\n" "$c_confirm" "$(pwd)" "$c_reset"
        echo ""
        local flags
        flags="$(_lc_flags_for "$(basename "$selected")")"
        claude ${=flags}
    else
        echo "  Invalid selection."
        return 1
    fi
}
