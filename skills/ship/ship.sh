#!/usr/bin/env bash
# Backend of /ship. Records a per-task baseline of the working tree and ships only the
# task's own changes (check -> branch -> commit -> push -> draft PR). Never stages,
# resets, stashes or commits changes that were already there before the task.
set -euo pipefail

readonly COMMIT_TYPES='feat|fix|refactor|perf|test|docs|build|ci|chore|style|revert'
readonly EXIT_NEEDS_CONFIRMATION=3

usage() {
  cat <<'EOF'
Usage (run inside the target repo):
  ship.sh baseline <slug> [--reset]
      Record changes already in the working tree before the task starts.
  ship.sh files <slug> [--files-from <file>]
      Show which changes belong to the task. Exit 3 when it needs user confirmation.
  ship.sh run <slug> --type <type> --title <pr title> --message-file <file> --body-file <file>
              [--files-from <file>] [--issue <n>]
      check -> branch (if on the default branch) -> commit task files -> push -> draft PR.

--files-from: newline-separated paths the user explicitly confirmed as the task's changes.
EOF
}

die() {
  echo "ship.sh: $*" >&2
  exit 1
}

needs_confirmation() {
  echo "ship.sh: $*" >&2
  echo "ship.sh: aborting without touching git. Confirm the file list with the user and re-run with --files-from <file>." >&2
  exit "$EXIT_NEEDS_CONFIRMATION"
}

validate_slug() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "invalid slug '$1' (use lowercase, digits, . _ -)"
}

# One dirty path per line (tracked changes, staged changes, untracked; both sides of renames).
dirty_paths() {
  local entry xy orig
  git -c core.quotepath=off status --porcelain=v1 -z --untracked-files=all | while IFS= read -r -d '' entry; do
    xy=${entry:0:2}
    printf '%s\n' "${entry:3}"
    case "$xy" in
      R* | C* | ?R | ?C)
        IFS= read -r -d '' orig
        printf '%s\n' "$orig"
        ;;
    esac
  done
}

# Fingerprint of a path's working-tree and index state.
fingerprint() {
  local path=$1 worktree=deleted index
  if [[ -f "$path" || -L "$path" ]]; then
    worktree=$(git hash-object --no-filters -- "$path")
  fi
  index=$(git ls-files -s -- "$path" | awk 'NR == 1 { print $2 }')
  echo "${worktree}:${index:-none}"
}

baseline_file() { echo "$GIT_DIR_ABS/harness/baseline-$1"; }

cmd_baseline() {
  local slug=${1:-} reset=${2:-}
  [[ -n "$slug" ]] || die "baseline needs a slug"
  validate_slug "$slug"
  local file path count=0
  file=$(baseline_file "$slug")
  if [[ -f "$file" && "$reset" != --reset ]]; then
    echo "baseline for '$slug' already exists (kept). Use --reset to record it again."
    return
  fi
  mkdir -p "$(dirname "$file")"
  : >"$file"
  while IFS= read -r path; do
    printf '%s\t%s\n' "$path" "$(fingerprint "$path")" >>"$file"
    count=$((count + 1))
  done < <(dirty_paths | sort -u)
  echo "baseline for '$slug' recorded: $count pre-existing change(s)"
}

# Fills TASK, PREEXISTING and CONFLICTS (files with one path per line).
classify() {
  local slug=$1 files_from=$2 base path recorded
  base=$(baseline_file "$slug")
  : >"$TASK"
  : >"$PREEXISTING"
  : >"$CONFLICTS"

  if [[ -n "$files_from" ]]; then
    [[ -f "$files_from" ]] || die "--files-from file not found: $files_from"
    local dirty
    dirty=$(dirty_paths | sort -u)
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      grep -qxF -- "$path" <<<"$dirty" || die "'$path' (from --files-from) has no changes"
      echo "$path" >>"$TASK"
    done <"$files_from"
    grep -vxF -f "$TASK" <<<"$dirty" >"$PREEXISTING" || true
    return
  fi

  if [[ ! -f "$base" ]]; then
    if [[ -n "$(dirty_paths)" ]]; then
      echo "no baseline for '$slug'; cannot tell task changes from pre-existing ones:" >&2
      dirty_paths | sort -u | sed 's/^/  /' >&2
      needs_confirmation "missing baseline"
    fi
    return
  fi

  while IFS= read -r path; do
    recorded=$(awk -F'\t' -v p="$path" '$1 == p { print "found\t" $2; exit }' "$base")
    if [[ -z "$recorded" ]]; then
      echo "$path" >>"$TASK"
    elif [[ "${recorded#*$'\t'}" == "$(fingerprint "$path")" ]]; then
      echo "$path" >>"$PREEXISTING"
    else
      echo "$path" >>"$CONFLICTS"
    fi
  done < <(dirty_paths | sort -u)
}

print_classification() {
  echo "Task changes (will be committed):"
  if [[ -s "$TASK" ]]; then sed 's/^/  + /' "$TASK"; else echo "  (none)"; fi
  if [[ -s "$PREEXISTING" ]]; then
    echo "Pre-existing changes (left untouched):"
    sed 's/^/  = /' "$PREEXISTING"
  fi
  if [[ -s "$CONFLICTS" ]]; then
    echo "Pre-existing files changed again during the task (ambiguous):"
    sed 's/^/  ! /' "$CONFLICTS"
  fi
}

default_branch() {
  local ref
  ref=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [[ -n "$ref" ]]; then
    echo "${ref#origin/}"
    return
  fi
  gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main
}

cmd_files() {
  local slug=${1:-} files_from=""
  [[ -n "$slug" ]] || die "files needs a slug"
  shift
  [[ ${1:-} == --files-from ]] && files_from=${2:-}
  validate_slug "$slug"
  classify "$slug" "$files_from"
  print_classification
  [[ -s "$CONFLICTS" ]] && needs_confirmation "some pre-existing files were changed again"
  return 0
}

cmd_run() {
  local slug=${1:-} type="" title="" message_file="" body_file="" files_from="" issue=""
  [[ -n "$slug" ]] || die "run needs a slug"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) type=$2; shift 2 ;;
      --title) title=$2; shift 2 ;;
      --message-file) message_file=$2; shift 2 ;;
      --body-file) body_file=$2; shift 2 ;;
      --files-from) files_from=$2; shift 2 ;;
      --issue) issue=${2#\#}; shift 2 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  validate_slug "$slug"
  [[ "$type" =~ ^($COMMIT_TYPES)$ ]] || die "--type must be one of: ${COMMIT_TYPES//|/, }"
  [[ -n "$title" ]] || die "--title is required"
  [[ -s "$message_file" ]] || die "--message-file is required and must not be empty"
  [[ -s "$body_file" ]] || die "--body-file is required and must not be empty"
  [[ -x scripts/check ]] || die "scripts/check not found; run /harness-init first"
  command -v gh >/dev/null || die "gh CLI is required"

  echo "==> classifying changes"
  classify "$slug" "$files_from"
  print_classification
  [[ -s "$CONFLICTS" ]] && needs_confirmation "some pre-existing files were changed again"
  [[ -s "$TASK" ]] || die "no task changes to ship"

  local before after
  before=$(dirty_paths | sort -u)
  echo "==> scripts/check"
  scripts/check || die "check failed; nothing was committed"
  after=$(dirty_paths | sort -u)
  if [[ "$before" != "$after" ]]; then
    echo "scripts/check changed the working tree (missing .gitignore entries or a formatter writing files?):" >&2
    diff <(echo "$before") <(echo "$after") | sed -n 's/^[<>] /  /p' >&2 || true
    die "aborting so generated files are never committed"
  fi

  local current default branch
  current=$(git symbolic-ref --quiet --short HEAD) || die "detached HEAD; checkout a branch first"
  default=$(default_branch)
  branch=$current
  if [[ "$current" == "$default" || "$current" == main || "$current" == master ]]; then
    branch="$type/$slug"
    git show-ref --verify --quiet "refs/heads/$branch" && die "branch $branch already exists"
    echo "==> creating branch $branch (working tree is kept)"
    git switch -c "$branch"
  fi

  local files=()
  while IFS= read -r path; do files+=("$path"); done <"$TASK"

  echo "==> committing ${#files[@]} file(s)"
  git add -- "${files[@]}"
  # --only (implied by pathspec) commits just these paths even if other changes are staged.
  git commit --file "$message_file" -- "${files[@]}"

  echo "==> pushing"
  git push -u origin "$branch"

  local existing body
  existing=$(gh pr view "$branch" --json url -q .url 2>/dev/null || true)
  if [[ -n "$existing" ]]; then
    echo "PR already open, updated with the new commit: $existing"
    return
  fi
  body=$(mktemp)
  cp "$body_file" "$body"
  if [[ -n "$issue" ]] && ! grep -qiE "(closes|fixes|resolves) #$issue([^0-9]|$)" "$body"; then
    printf '\nCloses #%s\n' "$issue" >>"$body"
  fi
  echo "==> opening draft PR"
  gh pr create --draft --base "$default" --head "$branch" --title "$title" --body-file "$body"
  rm -f "$body"
}

main() {
  local cmd=${1:-}
  [[ -n "$cmd" ]] || { usage; exit 1; }
  shift
  [[ $cmd == -h || $cmd == --help ]] && { usage; exit 0; }
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
  cd "$root"
  GIT_DIR_ABS=$(git rev-parse --absolute-git-dir)
  TASK=$(mktemp)
  PREEXISTING=$(mktemp)
  CONFLICTS=$(mktemp)
  trap 'rm -f "$TASK" "$PREEXISTING" "$CONFLICTS"' EXIT
  case "$cmd" in
    baseline) cmd_baseline "$@" ;;
    files) cmd_files "$@" ;;
    run) cmd_run "$@" ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
