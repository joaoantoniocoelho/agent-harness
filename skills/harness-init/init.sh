#!/usr/bin/env bash
# Deterministic half of /harness-init: detects the repo's existing tooling, plans and
# applies the harness files, and keeps .harness/manifest so uninstall can undo it.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
HARNESS_DIR=$(cd "$SCRIPT_DIR/../.." && pwd -P)
readonly SCRIPT_DIR HARNESS_DIR
readonly MANIFEST=.harness/manifest
readonly BACKUP_DIR=.harness/backup
readonly BLOCK_START='<!-- harness:start -->'
readonly BLOCK_END='<!-- harness:end -->'

usage() {
  cat <<'EOF'
Usage (run inside the target repo):
  init.sh detect
  init.sh plan  --stack <node|python|swift>
  init.sh diff  --stack <stack> <target>
  init.sh apply --stack <stack> [--overwrite <target>]... [--skip <target>]...
                [--set KEY=VALUE]... [--install-cmd <cmd>]
  init.sh rehash <target>...
  init.sh record-deps --pm <npm|pnpm|yarn|bun|uv|poetry|pip|brew> <package>...
EOF
}

die() {
  echo "init.sh: $*" >&2
  exit 1
}

sha_of() { shasum -a 256 "$1" | awk '{ print $1 }'; }

# ---------------------------------------------------------------- detection

has_file() {
  local f
  for f in "$@"; do
    [[ -e "$f" ]] && { echo "$f"; return 0; }
  done
  return 1
}

toml_has() { [[ -f pyproject.toml ]] && grep -Eq "$1" pyproject.toml; }

py_dep() {
  local name=$1 f
  for f in pyproject.toml requirements.txt requirements-dev.txt requirements/dev.txt; do
    [[ -f "$f" ]] && grep -Eiq "(^|[^A-Za-z0-9_-])${name}([^A-Za-z0-9_-]|$)" "$f" && return 0
  done
  return 1
}

detect_stacks() {
  [[ -f package.json ]] && echo node
  [[ -f pyproject.toml || -f requirements.txt || -f setup.py ]] && echo python
  if [[ -f Package.swift ]] || [[ -n "$(find . -maxdepth 2 -name '*.xcodeproj' -not -path './.build/*' -print -quit)" ]]; then
    echo swift
  fi
  return 0
}

node_pm() {
  if [[ -f pnpm-lock.yaml ]]; then echo pnpm
  elif [[ -f yarn.lock ]]; then echo yarn
  elif [[ -f bun.lockb || -f bun.lock ]]; then echo bun
  else echo npm
  fi
}

detect_node() {
  local pm deps scripts run exec install lint_tool=none format_tool=none
  pm=$(node_pm)
  deps=$(jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' package.json)
  # npm init's placeholder "test" script is not a real test runner.
  scripts=$(jq -r '.scripts // {} | to_entries[] | select(.value | test("no test specified") | not) | .key' package.json)
  has_dep() { grep -qxF "$1" <<<"$deps"; }
  has_script() { grep -qxF "$1" <<<"$scripts"; }

  case "$pm" in
    npm) run="npm run"; exec="npx"; install=$([[ -f package-lock.json ]] && echo "npm ci" || echo "npm install") ;;
    pnpm) run="pnpm run"; exec="pnpm exec"; install="pnpm install --frozen-lockfile" ;;
    yarn) run="yarn run"; exec="yarn"; install="yarn install --frozen-lockfile" ;;
    bun) run="bun run"; exec="bunx"; install="npm i -g bun && bun install --frozen-lockfile" ;;
  esac

  if has_dep @biomejs/biome || has_file biome.json biome.jsonc >/dev/null; then
    lint_tool=biome; format_tool=biome
  fi
  if has_dep eslint || has_file eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml >/dev/null; then
    lint_tool=eslint
  fi
  if has_dep prettier || has_file .prettierrc .prettierrc.json .prettierrc.js .prettierrc.cjs .prettierrc.yml prettier.config.js prettier.config.mjs >/dev/null; then
    format_tool=prettier
  fi

  echo "node.package_manager: $pm"
  echo "node.lint: $lint_tool"
  echo "node.format: $format_tool"
  echo "node.typescript: $( (has_dep typescript || [[ -f tsconfig.json ]]) && echo yes || echo no)"
  echo "node.next: $(has_dep next && echo yes || echo no)"
  echo "node.test: $(if has_dep vitest; then echo vitest; elif has_dep jest; then echo jest; elif has_script test; then echo "script:test"; else echo none; fi)"
  echo "node.scripts: $(tr '\n' ' ' <<<"$scripts")"
  echo "ci.install: $install"

  local missing=()
  if has_script format:check; then
    echo "set FORMAT_CMD=$run format:check"
  elif [[ $format_tool == prettier ]]; then
    echo "set FORMAT_CMD=$exec prettier --check ."
  elif [[ $format_tool == biome ]]; then
    echo "set FORMAT_CMD="
  else
    echo "set FORMAT_CMD=$exec prettier --check ."
    missing+=("format: prettier")
  fi

  if has_script lint; then
    echo "set LINT_CMD=$run lint"
  elif [[ $lint_tool == eslint ]]; then
    echo "set LINT_CMD=$exec eslint . --max-warnings 0"
  elif [[ $lint_tool == biome ]]; then
    echo "set LINT_CMD=$exec biome check ."
  else
    echo "set LINT_CMD=$exec eslint . --max-warnings 0"
    missing+=("lint: eslint @eslint/js typescript-eslint eslint-config-prettier")
  fi

  if has_script typecheck; then
    echo "set TYPECHECK_CMD=$run typecheck"
  elif has_script type-check; then
    echo "set TYPECHECK_CMD=$run type-check"
  elif has_dep typescript || [[ -f tsconfig.json ]]; then
    echo "set TYPECHECK_CMD=$exec tsc --noEmit"
  else
    echo "set TYPECHECK_CMD=$exec tsc --noEmit"
    missing+=("typecheck: typescript @types/node")
  fi

  if has_dep vitest; then
    echo "set TEST_CMD=$exec vitest run"
  elif has_dep jest; then
    echo "set TEST_CMD=$exec jest"
  elif has_script test; then
    echo "set TEST_CMD=$run test"
  else
    echo "set TEST_CMD=$exec jest --passWithNoTests"
    missing+=("test: jest ts-jest @types/jest")
  fi

  if has_script build; then
    echo "set BUILD_CMD=$run build"
  else
    echo "set BUILD_CMD="
  fi

  local m
  for m in ${missing[@]+"${missing[@]}"}; do
    echo "missing ${m%%:*} ($pm, dev):${m#*:}"
  done
}

python_pm() {
  if [[ -f uv.lock ]] || toml_has '^\[tool\.uv'; then echo uv
  elif [[ -f poetry.lock ]] || toml_has '^\[tool\.poetry'; then echo poetry
  elif [[ -f pyproject.toml ]]; then echo uv
  else echo pip
  fi
}

detect_python() {
  local pm p install missing=()
  pm=$(python_pm)
  case "$pm" in
    uv) p="uv run "; install="uv sync" ;;
    poetry) p="poetry run "; install="pipx install poetry && poetry install" ;;
    pip) p=""; install="pip install -r requirements.txt" ;;
  esac
  echo "python.package_manager: $pm"
  echo "ci.install: $install"

  if py_dep ruff || toml_has '^\[tool\.ruff' || has_file ruff.toml .ruff.toml >/dev/null; then
    echo "set FORMAT_CMD=${p}ruff format --check ."
    echo "set LINT_CMD=${p}ruff check ."
  else
    if py_dep black || toml_has '^\[tool\.black'; then
      echo "set FORMAT_CMD=${p}black --check ."
    else
      echo "set FORMAT_CMD=${p}ruff format --check ."
      missing+=("format: ruff")
    fi
    if py_dep flake8 || has_file .flake8 >/dev/null; then
      echo "set LINT_CMD=${p}flake8"
    else
      echo "set LINT_CMD=${p}ruff check ."
      missing+=("lint: ruff")
    fi
  fi

  if py_dep pyright || toml_has '^\[tool\.pyright' || has_file pyrightconfig.json >/dev/null; then
    echo "set TYPECHECK_CMD=${p}pyright"
  elif py_dep mypy || toml_has '^\[tool\.mypy' || has_file mypy.ini .mypy.ini >/dev/null; then
    echo "set TYPECHECK_CMD=${p}mypy ."
  else
    echo "set TYPECHECK_CMD=${p}pyright"
    missing+=("typecheck: pyright")
  fi

  if py_dep pytest || toml_has '^\[tool\.pytest'; then
    echo "set TEST_CMD=${p}pytest"
  else
    echo "set TEST_CMD=${p}pytest"
    missing+=("test: pytest")
  fi
  echo "set BUILD_CMD="

  local m
  for m in ${missing[@]+"${missing[@]}"}; do
    echo "missing ${m%%:*} ($pm, dev):${m#*:}"
  done
}

detect_swift() {
  local container="" flag="" schemes="" destination
  container=$(find . -maxdepth 2 -name '*.xcworkspace' -not -path '*.xcodeproj/*' -print -quit)
  if [[ -n "$container" ]]; then
    flag="-workspace ${container#./}"
  else
    container=$(find . -maxdepth 2 -name '*.xcodeproj' -print -quit)
    [[ -n "$container" ]] && flag="-project ${container#./}"
  fi
  echo "swift.container: ${container:-none (Swift Package)}"
  echo "ci.install: brew list swiftlint >/dev/null 2>&1 || brew install swiftlint"

  if [[ -f .swiftformat ]]; then
    echo "set FORMAT_CMD=swiftformat --lint ."
  else
    echo "set FORMAT_CMD=swift format lint --recursive --strict ."
  fi
  echo "set LINT_CMD=swiftlint lint --strict --quiet"
  echo "set TYPECHECK_CMD="
  command -v swiftlint >/dev/null || echo "missing lint (brew): swiftlint"

  if [[ -z "$container" ]]; then
    echo "set TEST_CMD=swift test"
    echo "set BUILD_CMD=swift build"
    return
  fi
  # shellcheck disable=SC2086 # flag is "-workspace X" / "-project X"
  schemes=$(xcodebuild -list -json $flag 2>/dev/null | jq -r '(.workspace // .project).schemes // [] | join(" ")' || true)
  local simulator
  simulator=$(xcrun simctl list devices available 2>/dev/null |
    sed -n 's/^ *\(iPhone[^(]*[^ (]\) *(.*/\1/p' | head -n 1)
  destination="platform=iOS Simulator,name=${simulator:-iPhone 17}"
  if grep -rqs 'SDKROOT = macosx' --include=project.pbxproj . 2>/dev/null; then
    destination='platform=macOS'
  fi
  echo "swift.schemes: ${schemes:-unknown}"
  echo "set SCHEME=${schemes%% *}"
  echo "set DESTINATION=$destination"
  echo "set TEST_CMD=xcodebuild $flag build test -scheme \"\$SCHEME\" -destination \"\$DESTINATION\" -quiet"
  echo "set BUILD_CMD="
}

cmd_detect() {
  local stacks
  stacks=$(detect_stacks)
  echo "repo: $(pwd)"
  echo "stacks: $(tr '\n' ' ' <<<"$stacks")"
  local f existing=""
  for f in AGENTS.md CLAUDE.md .github/workflows scripts/check "$MANIFEST"; do
    [[ -e "$f" ]] && existing+="$f "
  done
  echo "existing: ${existing:-none}"
  [[ -f "$MANIFEST" ]] && echo "harness: already installed (re-running updates harness-owned files)"
  local s
  for s in $stacks; do
    echo
    echo "[$s]"
    "detect_$s"
  done
}

# ---------------------------------------------------------------- templates

# Emits "kind<TAB>target<TAB>source" for every file the harness manages.
entries() {
  local stack=$1
  printf 'file\tscripts/check\ttemplates/check/%s.sh\n' "$stack"
  printf 'file\tscripts/guardrails.sh\tbin/guardrails.sh\n'
  printf 'file\tscripts/tests-touched.sh\tbin/tests-touched.sh\n'
  printf 'file\t.github/workflows/check.yml\ttemplates/ci/%s.yml\n' "$stack"
  printf 'block\tAGENTS.md\ttemplates/AGENTS.md\n'
  printf 'block\tCLAUDE.md\ttemplates/CLAUDE.md\n'
  case "$stack" in
    node)
      # Listed before eslint.config.mjs: it is only needed when the harness ESLint config is installed.
      printf 'lint\ttsconfig.eslint.json\ttemplates/lint/node/tsconfig.eslint.json\n'
      printf 'lint\teslint.config.mjs\ttemplates/lint/node/eslint.config.mjs\n'
      printf 'lint\t.prettierrc\ttemplates/lint/node/.prettierrc\n'
      printf 'lint\ttsconfig.json\ttemplates/lint/node/tsconfig.base.json\n'
      ;;
    python)
      printf 'lint\truff.toml\ttemplates/lint/python/ruff.toml\n'
      printf 'lint\tpyrightconfig.json\ttemplates/lint/python/pyrightconfig.json\n'
      ;;
    swift)
      printf 'lint\t.swiftlint.yml\ttemplates/lint/swift/.swiftlint.yml\n'
      printf 'lint\t.swift-format\ttemplates/lint/swift/.swift-format\n'
      ;;
    *) die "unknown stack: $stack" ;;
  esac
}

# Prints the existing config that already covers a lint target, if any.
equivalent_of() {
  case "$1" in
    eslint.config.mjs)
      has_file eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts eslint.config.mts \
        .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml biome.json biome.jsonc && return
      [[ -f package.json ]] && jq -e '.eslintConfig' package.json >/dev/null && echo "package.json#eslintConfig"
      ;;
    .prettierrc)
      has_file .prettierrc .prettierrc.json .prettierrc.js .prettierrc.cjs .prettierrc.mjs .prettierrc.yml .prettierrc.yaml \
        .prettierrc.toml prettier.config.js prettier.config.mjs prettier.config.cjs biome.json biome.jsonc && return
      [[ -f package.json ]] && jq -e '.prettier' package.json >/dev/null && echo "package.json#prettier"
      ;;
    tsconfig.json) has_file tsconfig.json ;;
    tsconfig.eslint.json) has_file tsconfig.eslint.json || equivalent_of eslint.config.mjs ;;
    ruff.toml)
      has_file ruff.toml .ruff.toml .flake8 && return
      toml_has '^\[tool\.(ruff|black|flake8)' && { echo "pyproject.toml"; return; }
      py_dep ruff && { echo "ruff (dependency)"; return; }
      py_dep black && { echo "black (dependency)"; return; }
      py_dep flake8 && echo "flake8 (dependency)"
      ;;
    pyrightconfig.json)
      has_file pyrightconfig.json mypy.ini .mypy.ini && return
      toml_has '^\[tool\.(pyright|mypy)' && { echo "pyproject.toml"; return; }
      py_dep mypy && { echo "mypy (dependency)"; return; }
      py_dep pyright && echo "pyright (dependency)"
      ;;
    .swiftlint.yml) has_file .swiftlint.yml .swiftlint.yaml ;;
    .swift-format) has_file .swift-format .swiftformat ;;
  esac
  return 0
}

shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

SETS=()
INSTALL_CMD=""

# Writes the rendered template for a target into $3.
render() {
  local kind=$1 target=$2 out=$3 source=$4
  if [[ $kind == block ]]; then
    awk -v s="$BLOCK_START" -v e="$BLOCK_END" '$0 == s { on = 1 } on { print } $0 == e { on = 0 }' \
      "$HARNESS_DIR/$source" >"$out"
    if [[ ! -s "$out" ]]; then
      { echo "$BLOCK_START"; cat "$HARNESS_DIR/$source"; echo "$BLOCK_END"; } >"$out"
    fi
    return
  fi
  cp "$HARNESS_DIR/$source" "$out"
  if [[ $target == scripts/check ]]; then
    local kv key value tmp
    for kv in ${SETS[@]+"${SETS[@]}"}; do
      key=${kv%%=*}
      value=${kv#*=}
      tmp=$(mktemp)
      KEY=$key LINE="$key=$(shell_quote "$value")" awk \
        'index($0, ENVIRON["KEY"] "=") == 1 && !done { print ENVIRON["LINE"]; done = 1; next } { print }' \
        "$out" >"$tmp"
      grep -q "^$key=" "$tmp" || die "scripts/check template has no $key variable"
      mv "$tmp" "$out"
    done
  fi
  if [[ $target == .github/workflows/check.yml ]]; then
    local tmp
    tmp=$(mktemp)
    CMD="${INSTALL_CMD:-echo 'set the install command'}" awk \
      '{ i = index($0, "__INSTALL_CMD__"); if (i) $0 = substr($0, 1, i - 1) ENVIRON["CMD"] substr($0, i + 15); print }' \
      "$out" >"$tmp"
    mv "$tmp" "$out"
  fi
}

manifest_sha() {
  [[ -f "$MANIFEST" ]] || return 0
  jq -r --arg p "$1" '.files[] | select(.path == $p) | .sha' "$MANIFEST"
}

has_block() {
  local target=$1
  grep -qxF "$BLOCK_START" "$target" && return 0
  [[ $target == CLAUDE.md ]] && grep -qx '@AGENTS.md' "$target"
}

# Prints "STATUS<TAB>note" for a target given its rendered template.
status_of() {
  local kind=$1 target=$2 rendered=$3 recorded equivalent
  recorded=$(manifest_sha "$target")

  if [[ $kind == block ]]; then
    if [[ ! -e "$target" ]]; then printf 'NEW\t\n'
    elif has_block "$target"; then printf 'PRESENT\tharness section already there\n'
    else printf 'BLOCK\tappend harness section, keep the rest\n'
    fi
    return
  fi

  if [[ ! -e "$target" ]]; then
    if [[ $kind == lint ]]; then
      equivalent=$(equivalent_of "$target")
      if [[ -n "$equivalent" ]]; then
        printf 'SKIP\trepo already uses %s\n' "$equivalent"
        return
      fi
    fi
    printf 'NEW\t\n'
    return
  fi
  if cmp -s "$target" "$rendered"; then
    printf 'SAME\t\n'
  elif [[ -n "$recorded" && "$(sha_of "$target")" == "$recorded" ]]; then
    printf 'UPDATE\tharness-owned, unchanged since install\n'
  elif [[ $kind == lint ]]; then
    printf 'SKIP\trepo already has its own %s\n' "$target"
  else
    printf 'CONFLICT\trepo has its own version (see: init.sh diff)\n'
  fi
}

parse_common() {
  STACK=""
  OVERWRITE=()
  SKIPS=()
  POSITIONAL=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stack) STACK=$2; shift 2 ;;
      --overwrite) OVERWRITE+=("$2"); shift 2 ;;
      --skip) SKIPS+=("$2"); shift 2 ;;
      --set) SETS+=("$2"); shift 2 ;;
      --install-cmd) INSTALL_CMD=$2; shift 2 ;;
      -h | --help) usage; exit 0 ;;
      -*) die "unknown option: $1" ;;
      *) POSITIONAL+=("$1"); shift ;;
    esac
  done
  [[ -n "$STACK" ]] || die "--stack is required"
  load_settings
}

# Settings from a previous apply are the defaults, so re-running never reverts
# the repo's configured commands; flags given now override them.
load_settings() {
  [[ -f "$MANIFEST" ]] || return 0
  local saved=() kv
  while IFS= read -r kv; do
    saved+=("$kv")
  done < <(jq -r '.settings // {} | to_entries[] | select(.key != "INSTALL_CMD") | "\(.key)=\(.value)"' "$MANIFEST")
  SETS=(${saved[@]+"${saved[@]}"} ${SETS[@]+"${SETS[@]}"})
  if [[ -z "$INSTALL_CMD" ]]; then
    INSTALL_CMD=$(jq -r '.settings.INSTALL_CMD // ""' "$MANIFEST")
  fi
}

save_settings() {
  local kv
  for kv in ${SETS[@]+"${SETS[@]}"}; do
    manifest_update --arg k "${kv%%=*}" --arg v "${kv#*=}" '.settings[$k] = $v'
  done
  if [[ -n "$INSTALL_CMD" ]]; then
    manifest_update --arg v "$INSTALL_CMD" '.settings.INSTALL_CMD = $v'
  fi
}

in_list() {
  local needle=$1 item
  shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

cmd_plan() {
  parse_common "$@"
  local kind target source rendered status note
  rendered=$(mktemp)
  while IFS=$'\t' read -r kind target source; do
    render "$kind" "$target" "$rendered" "$source"
    IFS=$'\t' read -r status note <<<"$(status_of "$kind" "$target" "$rendered")"
    printf '%-9s %-28s %s\n' "$status" "$target" "$note"
  done < <(entries "$STACK")
  rm -f "$rendered"
  local line
  while IFS= read -r line; do
    if [[ -f .gitignore ]] && grep -qxF "$line" .gitignore; then
      printf '%-9s %-28s %s\n' PRESENT ".gitignore" "$line"
    else
      printf '%-9s %-28s %s\n' APPEND ".gitignore" "$line"
    fi
  done <"$HARNESS_DIR/templates/gitignore-snippet"
}

cmd_diff() {
  parse_common "$@"
  local wanted=${POSITIONAL[0]:-} kind target source rendered
  [[ -n "$wanted" ]] || die "diff needs a target"
  rendered=$(mktemp)
  while IFS=$'\t' read -r kind target source; do
    [[ $target == "$wanted" ]] || continue
    render "$kind" "$target" "$rendered" "$source"
    diff -u --label "repo/$target" --label "harness/$target" "$target" "$rendered" || true
    rm -f "$rendered"
    return
  done < <(entries "$STACK")
  rm -f "$rendered"
  die "not a harness target: $wanted"
}

manifest_init() {
  mkdir -p .harness
  if [[ ! -f "$MANIFEST" ]]; then
    jq -n --arg stack "$STACK" '{version: 1, stack: $stack, files: [], gitignore_added: [], gitignore_created: false, deps: []}' >"$MANIFEST"
  fi
}

manifest_update() {
  local tmp
  tmp=$(mktemp)
  jq "$@" "$MANIFEST" >"$tmp"
  mv "$tmp" "$MANIFEST"
}

# Keeps the original mode on re-runs so uninstall still restores the first backup.
record_file() {
  local path=$1 mode=$2 sha=$3
  manifest_update --arg p "$path" --arg m "$mode" --arg s "$sha" '
    (.files | map(select(.path == $p)) | .[0].mode // $m) as $mode
    | .files = ([.files[] | select(.path != $p)] + [{path: $p, mode: $mode, sha: $s}])'
}

install_file() {
  local target=$1 rendered=$2
  mkdir -p "$(dirname "$target")"
  cp "$rendered" "$target"
  [[ $target == scripts/* ]] && chmod +x "$target"
  return 0
}

cmd_apply() {
  parse_common "$@"
  manifest_init
  local kind target source rendered status note
  rendered=$(mktemp)
  while IFS=$'\t' read -r kind target source; do
    render "$kind" "$target" "$rendered" "$source"
    IFS=$'\t' read -r status note <<<"$(status_of "$kind" "$target" "$rendered")"
    if in_list "$target" ${SKIPS[@]+"${SKIPS[@]}"}; then
      echo "skipped   $target (--skip)"
      continue
    fi
    case "$status" in
      NEW)
        if [[ $kind == block ]]; then
          install_file "$target" "$HARNESS_DIR/$source"
        else
          install_file "$target" "$rendered"
        fi
        record_file "$target" new "$(sha_of "$target")"
        echo "created   $target"
        ;;
      UPDATE)
        install_file "$target" "$rendered"
        record_file "$target" new "$(sha_of "$target")"
        echo "updated   $target"
        ;;
      CONFLICT)
        if ! in_list "$target" ${OVERWRITE[@]+"${OVERWRITE[@]}"}; then
          echo "kept      $target (repo version; pass --overwrite to replace)"
          continue
        fi
        if [[ ! -e "$BACKUP_DIR/$target" ]]; then
          mkdir -p "$(dirname "$BACKUP_DIR/$target")"
          cp -p "$target" "$BACKUP_DIR/$target"
        fi
        install_file "$target" "$rendered"
        record_file "$target" overwritten "$(sha_of "$target")"
        echo "replaced  $target (backup: $BACKUP_DIR/$target)"
        ;;
      BLOCK)
        { echo; cat "$rendered"; } >>"$target"
        record_file "$target" block "$(sha_of "$target")"
        echo "appended  $target (harness section)"
        ;;
      *)
        echo "unchanged $target ${note:+($note)}"
        ;;
    esac
  done < <(entries "$STACK")
  rm -f "$rendered"
  apply_gitignore
  save_settings
  echo "manifest  $MANIFEST"
}

apply_gitignore() {
  local line
  if [[ ! -f .gitignore ]]; then
    : >.gitignore
    manifest_update '.gitignore_created = true'
  fi
  while IFS= read -r line; do
    grep -qxF "$line" .gitignore && continue
    [[ -s .gitignore && -n "$(tail -c 1 .gitignore)" ]] && echo >>.gitignore
    echo "$line" >>.gitignore
    manifest_update --arg l "$line" '.gitignore_added = ((.gitignore_added + [$l]) | unique)'
    echo "gitignore + $line"
  done <"$HARNESS_DIR/templates/gitignore-snippet"
}

cmd_rehash() {
  [[ -f "$MANIFEST" ]] || die "no $MANIFEST; run apply first"
  local target
  for target in "$@"; do
    [[ -n "$(manifest_sha "$target")" ]] || die "$target is not in the manifest"
    manifest_update --arg p "$target" --arg s "$(sha_of "$target")" \
      '.files |= map(if .path == $p then .sha = $s else . end)'
    echo "rehashed  $target"
  done
}

cmd_record_deps() {
  [[ -f "$MANIFEST" ]] || die "no $MANIFEST; run apply first"
  [[ ${1:-} == --pm ]] || die "usage: record-deps --pm <pm> <package>..."
  local pm=$2
  shift 2
  [[ $# -gt 0 ]] || die "no packages given"
  manifest_update --arg pm "$pm" --argjson pkgs "$(printf '%s\n' "$@" | jq -R . | jq -s .)" \
    '.deps += [{pm: $pm, packages: $pkgs}]'
  echo "recorded deps ($pm): $*"
}

main() {
  local cmd=${1:-}
  [[ -n "$cmd" ]] || { usage; exit 1; }
  shift
  command -v jq >/dev/null || die "jq is required"
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository (run git init first)"
  cd "$root"
  case "$cmd" in
    detect) cmd_detect ;;
    plan) cmd_plan "$@" ;;
    diff) cmd_diff "$@" ;;
    apply) cmd_apply "$@" ;;
    rehash) cmd_rehash "$@" ;;
    record-deps) cmd_record_deps "$@" ;;
    -h | --help) usage ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
