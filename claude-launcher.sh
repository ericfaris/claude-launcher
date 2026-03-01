#!/usr/bin/env bash
# Pre-Claude project launcher
# Source this file from ~/.zshrc:
#   source ~/projects/claude-launcher/claude-launcher.sh
#
# Then run with:  lc
# Or auto-launch by adding to ~/.zshrc:
#   [[ "$(pwd)" == "$HOME/projects" ]] && lc

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
    local -a dirs=("$@")

    local c_line=$'\e[38;5;240m'
    local c_title=$'\e[38;5;111m'
    local c_num=$'\e[38;5;242m'
    local c_icon=$'\e[38;5;215m'
    local c_prompt=$'\e[38;5;111m'
    local c_reset=$'\e[0m'

    local icon_terminal=$'\uf489'
    local icon_root=$'\uf07b'

    echo ""
    printf "  %s──%s %sClaude Launcher%s %s──────────────%s\n" \
        "$c_line" "$c_reset" "$c_title" "$c_reset" "$c_line" "$c_reset"
    echo ""

    printf "  %s%2d%s  %s%s%s  %s\n" \
        "$c_num" 1 "$c_reset" "$c_icon" "$icon_terminal" "$c_reset" "terminal"
    printf "  %s%2d%s  %s%s%s  %s\n" \
        "$c_num" 2 "$c_reset" "$c_icon" "$icon_root" "$c_reset" "projects (root)"

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
    printf "  %s›%s " "$c_prompt" "$c_reset"
}

lc() {
    local projects_dir="$HOME/projects"
    local -a dirs

    while IFS= read -r dir; do
        dirs+=("$dir")
    done < <(find "$projects_dir" -maxdepth 1 -mindepth 1 -type d | sort)

    _lc_display "${dirs[@]}"
    read -rk 1 choice
    echo ""

    local c_confirm=$'\e[38;5;242m'
    local c_reset=$'\e[0m'

    if [[ "$choice" == "1" ]]; then
        builtin cd "$projects_dir" || return 1
        printf "  %s→ %s%s\n" "$c_confirm" "$(pwd)" "$c_reset"
        echo ""
    elif [[ "$choice" == "2" ]]; then
        builtin cd "$projects_dir" || return 1
        printf "  %s→ %s%s\n" "$c_confirm" "$(pwd)" "$c_reset"
        echo ""
        claude
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 3 && choice <= ${#dirs[@]} + 2 )); then
        local selected="${dirs[$((choice - 2))]}"
        builtin cd "$selected" || return 1
        printf "  %s→ %s%s\n" "$c_confirm" "$(pwd)" "$c_reset"
        echo ""
        claude
    else
        echo "  Invalid selection."
        return 1
    fi
}
