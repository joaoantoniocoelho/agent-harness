#!/usr/bin/env bash
# Links the harness into Claude Code and Codex. Idempotent; anything already there is
# moved to .backup/ (restored by uninstall.sh).
set -euo pipefail

HARNESS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
readonly HARNESS_DIR
readonly BACKUP_ROOT="$HARNESS_DIR/.backup"

# Emits "link<TAB>target" pairs, shared with uninstall.sh.
links() {
  local skill
  printf '%s\t%s\n' "$HOME/.claude/CLAUDE.md" "$HARNESS_DIR/global/AGENTS.md"
  printf '%s\t%s\n' "$HOME/.codex/AGENTS.md" "$HARNESS_DIR/global/AGENTS.md"
  for skill in "$HARNESS_DIR"/skills/*/; do
    skill=$(basename "$skill")
    printf '%s\t%s\n' "$HOME/.claude/skills/$skill" "$HARNESS_DIR/skills/$skill"
    printf '%s\t%s\n' "$HOME/.codex/skills/$skill" "$HARNESS_DIR/skills/$skill"
  done
}

link_one() {
  local link=$1 target=$2 backup
  backup="$BACKUP_ROOT/${link#"$HOME"/}"
  if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
    echo "ok        ${link/#$HOME/~}"
    return
  fi
  mkdir -p "$(dirname "$link")"
  if [[ -e "$link" || -L "$link" ]]; then
    [[ -e "$backup" || -L "$backup" ]] && {
      echo "skip      ${link/#$HOME/~}: a backup already exists at $backup; resolve it manually" >&2
      return 1
    }
    mkdir -p "$(dirname "$backup")"
    mv "$link" "$backup"
    echo "backup    ${link/#$HOME/~} -> ${backup/#$HOME/~}"
  fi
  ln -s "$target" "$link"
  echo "linked    ${link/#$HOME/~} -> ${target/#$HOME/~}"
}

main() {
  local link target failed=0
  while IFS=$'\t' read -r link target; do
    link_one "$link" "$target" || failed=1
  done < <(links)
  chmod +x "$HARNESS_DIR"/bin/*.sh "$HARNESS_DIR"/skills/*/*.sh "$HARNESS_DIR"/templates/check/*.sh
  [[ $failed -eq 0 ]] || exit 1
  echo "agent-harness installed. Restart Claude Code / Codex sessions to load it."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
