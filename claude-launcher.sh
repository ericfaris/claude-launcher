#!/usr/bin/env bash
# Pre-Claude project launcher
# Source this file from ~/.zshrc:
#   source ~/projects/claude-launcher/claude-launcher.sh
#
# Then run with:  lc
# Or auto-launch by adding to ~/.zshrc:
#   [[ "$(pwd)" == "$HOME/projects" ]] && lc

lc() {
    local projects_dir="$HOME/projects"
    local -a dirs
    local i=1

    # Collect subdirectories, sorted
    printf "  %2d)  %s\n" 0 "terminal"
    printf "  %2d)  %s\n" "$i" "projects (root)"
    ((i++))
    while IFS= read -r dir; do
        dirs+=("$dir")
        printf "  %2d)  %s\n" "$i" "$(basename "$dir")"
        ((i++))
    done < <(find "$projects_dir" -maxdepth 1 -mindepth 1 -type d | sort)

    echo ""
    printf "  Pick a project [0-%d]: " "$((${#dirs[@]} + 1))"
    read -rk 1 choice
    echo ""

    if [[ "$choice" == "0" ]]; then
        builtin cd "$projects_dir" || return 1
        echo "  → $(pwd)"
        echo ""
    elif [[ "$choice" == "1" ]]; then
        builtin cd "$projects_dir" || return 1
        echo "  → $(pwd)"
        echo ""
        claude
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 2 && choice <= ${#dirs[@]} + 1 )); then
        local selected="${dirs[$((choice - 1))]}"
        builtin cd "$selected" || return 1
        echo "  → $(pwd)"
        echo ""
        claude
    else
        echo "  Invalid selection."
        return 1
    fi
}
