#!/usr/bin/env bash
# Removes the harness from this machine (no args) or from a repo (--repo <path>).
# Prints the plan first and asks before acting; --dry-run only prints.
set -euo pipefail

readonly BLOCK_START='<!-- harness:start -->'
readonly BLOCK_END='<!-- harness:end -->'

# Provides HARNESS_DIR, BACKUP_ROOT and links().
# shellcheck source=install.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/install.sh"

usage() {
  cat <<'USAGE'
Usage:
  uninstall.sh [--dry-run] [--yes]                 remove from this machine
  uninstall.sh --repo <path> [--dry-run] [--yes]   remove from a repo (uses .harness/manifest)
USAGE
}

DRY_RUN=0
ASSUME_YES=0
INTERACTIVE=0
[[ -t 0 ]] && INTERACTIVE=1
ACTIONS=()

plan() { ACTIONS+=("$1"); }

# Prompts read from /dev/tty because they run inside loops that consume stdin.
confirm() {
  local prompt=$1 answer
  [[ $ASSUME_YES -eq 1 ]] && return 0
  [[ $INTERACTIVE -eq 1 ]] || { echo "not a terminal; re-run with --yes to proceed" >&2; return 1; }
  read -r -p "$prompt [y/N] " answer </dev/tty
  [[ "$answer" == y || "$answer" == Y ]]
}

show_plan_and_confirm() {
  if [[ ${#ACTIONS[@]} -eq 0 ]]; then
    echo "Nothing to do."
    exit 0
  fi
  echo "Planned actions:"
  printf '  %s\n' "${ACTIONS[@]}"
  [[ $DRY_RUN -eq 1 ]] && { echo "(dry run: nothing changed)"; exit 0; }
  confirm "Proceed?" || { echo "Aborted."; exit 1; }
}

# ---------------------------------------------------------------- machine

uninstall_machine() {
  local link target backup
  while IFS=$'\t' read -r link target; do
    backup="$BACKUP_ROOT/${link#"$HOME"/}"
    if [[ -L "$link" && "$(readlink "$link")" == "$HARNESS_DIR"/* ]]; then
      plan "remove link ${link/#$HOME/~}"
      [[ -e "$backup" || -L "$backup" ]] && plan "restore ${link/#$HOME/~} from backup"
    elif [[ -e "$link" || -L "$link" ]]; then
      plan "keep ${link/#$HOME/~} (not a harness link)"
    fi
  done < <(links)
  show_plan_and_confirm

  while IFS=$'\t' read -r link target; do
    backup="$BACKUP_ROOT/${link#"$HOME"/}"
    [[ -L "$link" && "$(readlink "$link")" == "$HARNESS_DIR"/* ]] || continue
    rm "$link"
    echo "removed   ${link/#$HOME/~}"
    if [[ -e "$backup" || -L "$backup" ]]; then
      mv "$backup" "$link"
      echo "restored  ${link/#$HOME/~}"
    fi
  done < <(links)
  echo "Done. The harness repo itself is still at $HARNESS_DIR (delete it manually if you want)."
}

# ---------------------------------------------------------------- repo

readonly MANIFEST=.harness/manifest
readonly REPO_BACKUP=.harness/backup

sha_of() { shasum -a 256 "$1" | awk '{ print $1 }'; }

remove_block() {
  local file=$1 tmp
  tmp=$(mktemp)
  S=$BLOCK_START E=$BLOCK_END awk '
    $0 == ENVIRON["S"] { skip = 1; next }
    $0 == ENVIRON["E"] { skip = 0; next }
    !skip { lines[++n] = $0 }
    END {
      while (n > 0 && lines[n] == "") n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

uninstall_repo() {
  local repo=$1 path mode sha current line
  cd "$repo"
  cd "$(git rev-parse --show-toplevel)"
  [[ -f "$MANIFEST" ]] || { echo "No $MANIFEST in $(pwd); nothing to uninstall." >&2; exit 1; }
  command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

  local edited=()
  while IFS=$'\t' read -r path mode sha; do
    [[ -e "$path" ]] || continue
    current=$(sha_of "$path")
    case "$mode" in
      new)
        if [[ "$current" == "$sha" ]]; then
          plan "delete $path"
        else
          plan "ask before deleting $path (edited after install; kept with --yes)"
          edited+=("$path")
        fi
        ;;
      overwritten)
        if [[ -e "$REPO_BACKUP/$path" ]]; then
          plan "restore $path from $REPO_BACKUP/$path${current:+$([[ $current != "$sha" ]] && echo ' (edited after install!)')}"
        else
          plan "cannot restore $path (no local backup): see git log --oneline -- $path"
        fi
        ;;
      block) plan "remove harness section from $path" ;;
    esac
  done < <(jq -r '.files[] | [.path, .mode, .sha] | @tsv' "$MANIFEST")

  while IFS= read -r line; do
    plan "remove '$line' from .gitignore"
  done < <(jq -r '.gitignore_added[]' "$MANIFEST")
  [[ -d "$(git rev-parse --absolute-git-dir)/harness" ]] && plan "delete .git/harness/ (ship baselines)"
  plan "delete .harness/ (manifest, backups, allow-schema)"
  show_plan_and_confirm

  local deps
  deps=$(jq -r '.deps[] | "\(.pm)\t\(.packages | join(" "))"' "$MANIFEST")

  while IFS=$'\t' read -r path mode sha; do
    [[ -e "$path" ]] || continue
    case "$mode" in
      new)
        if [[ "$(sha_of "$path")" != "$sha" ]]; then
          if [[ $ASSUME_YES -eq 1 ]] || ! confirm "$path was edited after install. Delete it?"; then
            echo "kept      $path (edited after install)"
            continue
          fi
        fi
        rm "$path"
        echo "deleted   $path"
        ;;
      overwritten)
        if [[ -e "$REPO_BACKUP/$path" ]]; then
          cp -p "$REPO_BACKUP/$path" "$path"
          echo "restored  $path"
        else
          echo "manual    $path: restore with git (git log --oneline -- $path)"
        fi
        ;;
      block)
        remove_block "$path"
        echo "cleaned   $path"
        ;;
    esac
  done < <(jq -r '.files[] | [.path, .mode, .sha] | @tsv' "$MANIFEST")

  local tmp
  while IFS= read -r line; do
    tmp=$(mktemp)
    grep -vxF -- "$line" .gitignore >"$tmp" || true
    mv "$tmp" .gitignore
  done < <(jq -r '.gitignore_added[]' "$MANIFEST")
  if [[ "$(jq -r '.gitignore_created' "$MANIFEST")" == true && ! -s .gitignore ]]; then
    rm .gitignore
  fi

  rmdir scripts .github/workflows .github 2>/dev/null || true
  rm -rf "$(git rev-parse --absolute-git-dir)/harness" .harness
  echo "deleted   .harness/ and .git/harness/"

  if [[ -n "$deps" ]]; then
    echo
    echo "Dependencies added by /harness-init were NOT removed. To remove them:"
    local pm pkgs
    while IFS=$'\t' read -r pm pkgs; do
      case "$pm" in
        npm) echo "  npm uninstall $pkgs" ;;
        pnpm | yarn | bun) echo "  $pm remove $pkgs" ;;
        uv) echo "  uv remove --dev $pkgs" ;;
        poetry) echo "  poetry remove --group dev $pkgs" ;;
        pip) echo "  pip uninstall $pkgs" ;;
        brew) echo "  brew uninstall $pkgs" ;;
        *) echo "  ($pm) $pkgs" ;;
      esac
    done <<<"$deps"
  fi
  echo
  echo "Done. docs/plans/ was kept. Nothing was committed: review with git status."
}

main() {
  local repo=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo=${2:?--repo needs a path}; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --yes | -y) ASSUME_YES=1; shift ;;
      -h | --help) usage; exit 0 ;;
      *) usage; exit 1 ;;
    esac
  done
  if [[ -n "$repo" ]]; then
    uninstall_repo "$repo"
  else
    uninstall_machine
  fi
}

main "$@"
