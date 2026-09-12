#!/usr/bin/env bash
#
# codex-tandem -- install OpenAI Codex and DeepSeek side by side on Ubuntu.
#
# Codex and DeepSeek both come from the same CLI, but each one gets its own
# CODEX_HOME, so their sessions, history, credentials and locks stay separate
# and both can run at the same time.
#
set -euo pipefail

TANDEM_REPO="${TANDEM_REPO:-martingaldeca/codex-tandem}"
TANDEM_REF="${TANDEM_REF:-main}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/assets"
CATALOG_TEMPLATE="$ASSETS_DIR/catalog/deepseek-catalog.template.json"
CATALOG_OVERRIDE="$ASSETS_DIR/models-deepseek.json"
CATALOG_BUILDER="$SCRIPT_DIR/tools/build-deepseek-catalog.py"

# Defaults. Everything can be overridden from the environment or the CLI.
DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-flash}"
DEEPSEEK_EFFORT="${DEEPSEEK_EFFORT:-max}"
DEEPSEEK_BASE_URL="${DEEPSEEK_BASE_URL:-https://api.deepseek.com/}"
CODEX_MODEL="${CODEX_MODEL:-}"
CODEX_EFFORT="${CODEX_EFFORT:-high}"
CODEX_CLI_VERSION="${CODEX_CLI_VERSION:-latest}"
BASE_MODEL="${BASE_MODEL:-}"

MAIN_CODEX_HOME="$HOME/.codex"
DEEPSEEK_CODEX_HOME="$HOME/.codex-deepseek"
DEEPSEEK_KEY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/deepseek/api_key"
BIN_DIR="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
MARKER="codex-tandem parallel setup"

FORCE=0
SKIP_CODEX=0
SKIP_AGENTS=0
SKILLS_SRC=""
DO_LOGIN=0
DRY_RUN=0
FULL_ACCESS=1

if [ -t 1 ]; then
  C_BOLD=$'\033[1m'; C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_OFF=$'\033[0m'
else
  C_BOLD=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_OFF=""
fi

log()  { printf '%s==>%s %s\n' "$C_BLUE$C_BOLD" "$C_OFF" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
skip() { printf '%s  --%s %s\n' "$C_YELLOW" "$C_OFF" "$*"; }
warn() { printf '%s  !!%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%s  xx%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'USAGE'
codex-tandem -- Codex and DeepSeek side by side, each with its own CODEX_HOME.

Usage: ./install.sh [options]

Options:
  -h, --help              Show this help.
      --force             Replace existing config files (keeps a .bak copy).
      --dry-run           Print what would happen, write nothing.
      --skip-codex        Do not install/update the Codex CLI.
      --codex-version X   Version of the Codex CLI to install (default: latest).
      --base-model SLUG   Codex model whose instruction template is reused for the
                          generated DeepSeek catalog (default: the model already
                          configured in ~/.codex/config.toml).
      --skills-from DIR   Copy your own skills from DIR into ~/.codex/skills.
      --no-agents         Do not install the example ~/.codex/AGENTS.md.
      --safe-permissions  Keep Codex's sandbox/approval defaults instead of the
                          author's "no sandbox" setting in the DeepSeek home.
      --login             Run `codex login` at the end.

Environment:
  DEEPSEEK_API_KEY=sk-...        Stored in ~/.config/deepseek/api_key (mode 600).
  DEEPSEEK_MODEL=deepseek-flash  Model exposed by the `deepseek` command.
  DEEPSEEK_BASE_URL=https://api.deepseek.com/
  CODEX_MODEL=...                Default model for the `codex` command.
  CODEX_INSTALL_DIR=~/.local/bin Where the `codex` and `deepseek` binaries go.

Result:
  codex     -> ~/.codex            (your ChatGPT account, its own sessions)
  deepseek  -> ~/.codex-deepseek   (DeepSeek API key, its own sessions)
USAGE
}

fetch_to() {
  local url="$1" out="$2"
  if have curl; then
    curl -fsSL --retry 3 --max-time 300 -o "$out" "$url"
  elif have wget; then
    wget -q -O "$out" "$url"
  else
    die "need curl or wget (apt-get install -y curl ca-certificates)"
  fi
}

bootstrap_if_needed() {
  [ -r "$CATALOG_TEMPLATE" ] && return 0
  printf '%s==>%s %s\n' "$C_BLUE$C_BOLD" "$C_OFF" "No assets/ next to this script: fetching the full installer from GitHub"
  local tmp dir url
  tmp="$(mktemp -d)"
  url="https://codeload.github.com/$TANDEM_REPO/tar.gz/refs/heads/$TANDEM_REF"
  fetch_to "$url" "$tmp/repo.tar.gz"
  tar -xzf "$tmp/repo.tar.gz" -C "$tmp" || die "could not unpack $url"
  dir="$(find "$tmp" -maxdepth 2 -name install.sh -type f | head -n1)"
  [ -n "$dir" ] || die "install.sh not found inside $url"
  exec bash "$dir" "$@"
}

bootstrap_if_needed "$@"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)         usage; exit 0 ;;
    --force)           FORCE=1 ;;
    --dry-run)         DRY_RUN=1 ;;
    --skip-codex)      SKIP_CODEX=1 ;;
    --no-agents)       SKIP_AGENTS=1 ;;
    --safe-permissions) FULL_ACCESS=0 ;;
    --login)           DO_LOGIN=1 ;;
    --codex-version)   shift; [ $# -gt 0 ] || die "--codex-version needs a value"; CODEX_CLI_VERSION="$1" ;;
    --base-model)      shift; [ $# -gt 0 ] || die "--base-model needs a value"; BASE_MODEL="$1" ;;
    --skills-from)     shift; [ $# -gt 0 ] || die "--skills-from needs a directory"; SKILLS_SRC="$1" ;;
    *)                 usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

write_file() {
  local path="$1" mode="${2:-600}"
  if [ "$DRY_RUN" = 1 ]; then
    log "dry-run: would write $path"
    cat >/dev/null
    return 0
  fi
  mkdir -p -- "$(dirname -- "$path")"
  if [ -e "$path" ]; then
    if [ "$FORCE" != 1 ]; then
      warn "keeping existing $path (use --force to replace it)"
      cat >/dev/null
      return 0
    fi
    cp -a -- "$path" "$path.bak.$(date +%Y%m%d-%H%M%S)"
    warn "backed up the previous $path"
  fi
  ( umask 077; cat > "$path" )
  chmod "$mode" -- "$path"
  ok "$path"
}

ensure_path_block() {
  local rc="$1"
  [ -e "$rc" ] || return 0
  if grep -q "$MARKER" "$rc" 2>/dev/null; then
    skip "$rc already on PATH"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    log "dry-run: would add $BIN_DIR to PATH in $rc"
    return 0
  fi
  {
    printf '\n# >>> %s >>>\n' "$MARKER"
    printf 'case ":$PATH:" in\n'
    printf '  *":$HOME/.local/bin:"*) ;;\n'
    printf '  *) export PATH="$HOME/.local/bin:$PATH" ;;\n'
    printf 'esac\n'
    printf '# <<< %s <<<\n' "$MARKER"
  } >> "$rc"
  ok "PATH updated in $rc"
}

link_shared_entries() {
  local link target
  for link in packages skills plugins AGENTS.md; do
    target="$MAIN_CODEX_HOME/$link"
    [ -e "$target" ] || continue
    if [ -L "$DEEPSEEK_CODEX_HOME/$link" ]; then
      skip "link $link already there"
    elif [ -e "$DEEPSEEK_CODEX_HOME/$link" ]; then
      skip "link $link skipped (something else has that name)"
    elif [ "$DRY_RUN" = 1 ]; then
      log "dry-run: would link $DEEPSEEK_CODEX_HOME/$link -> $target"
    else
      ln -s -- "$target" "$DEEPSEEK_CODEX_HOME/$link"
      ok "link $link -> $target"
    fi
  done
}

full_access_line() {
  [ "$FULL_ACCESS" = 1 ] && printf 'default_permissions = ":danger-full-access"'
  return 0
}

step_preflight() {
  log "1/8  Checking the system"
  [ "$(uname -s)" = "Linux" ] || die "this installer targets Linux/Ubuntu"
  [ "$(id -u)" != "0" ] || die "do not run it as root or with sudo: it installs into the user's HOME"
  [ -n "${HOME:-}" ] || die "HOME is not set"
  have tar || die "tar is missing"
  if ! have curl && ! have wget; then
    if have apt-get && have sudo; then
      warn "installing curl and ca-certificates with apt"
      [ "$DRY_RUN" = 1 ] || sudo apt-get update -y
      [ "$DRY_RUN" = 1 ] || sudo apt-get install -y curl ca-certificates
    else
      die "curl or wget is required (sudo apt-get install -y curl ca-certificates)"
    fi
  fi
  if [ ! -r "$CATALOG_OVERRIDE" ]; then
    [ -r "$CATALOG_TEMPLATE" ] || die "missing $CATALOG_TEMPLATE"
    [ -r "$CATALOG_BUILDER" ] || die "missing $CATALOG_BUILDER"
    have python3 || die "python3 is required to build the DeepSeek model catalog"
  fi
  ok "$(uname -sr) / user $(id -un)"
}

step_codex() {
  log "2/8  Installing the Codex CLI"
  if [ "$SKIP_CODEX" = 1 ]; then
    skip "skipped (--skip-codex)"
    return 0
  fi
  local installed="" tmp
  have codex && installed="$(codex --version 2>/dev/null | awk '{print $NF}')"
  if [ -n "$installed" ] && [ "$CODEX_CLI_VERSION" != "latest" ] && [ "$installed" = "$CODEX_CLI_VERSION" ]; then
    ok "Codex CLI $installed already installed at $(command -v codex)"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    log "dry-run: would install Codex CLI $CODEX_CLI_VERSION into $BIN_DIR"
    return 0
  fi
  tmp="$(mktemp)"
  fetch_to "https://chatgpt.com/codex/install.sh" "$tmp"
  if [ "$CODEX_CLI_VERSION" = "latest" ]; then
    CODEX_HOME="$MAIN_CODEX_HOME" CODEX_INSTALL_DIR="$BIN_DIR" sh "$tmp"
  else
    CODEX_HOME="$MAIN_CODEX_HOME" CODEX_INSTALL_DIR="$BIN_DIR" sh "$tmp" --release "$CODEX_CLI_VERSION"
  fi
  rm -f -- "$tmp"
  [ -x "$BIN_DIR/codex" ] || have codex || die "Codex CLI was not installed"
  ok "Codex CLI $("$BIN_DIR/codex" --version 2>/dev/null || codex --version) at $BIN_DIR"
}

step_config_codex() {
  log "3/8  Configuring Codex in ~/.codex"
  mkdir -p -- "$MAIN_CODEX_HOME"
  local model_lines=""
  if [ -n "$CODEX_MODEL" ]; then
    model_lines="model = \"$CODEX_MODEL\"
model_reasoning_effort = \"$CODEX_EFFORT\"
plan_mode_reasoning_effort = \"$CODEX_EFFORT\""
  fi
  if [ "$FULL_ACCESS" = 1 ]; then
    warn "DeepSeek will run with default_permissions = \":danger-full-access\" (use --safe-permissions to change it)"
  fi
  write_file "$MAIN_CODEX_HOME/config.toml" 600 <<EOF
model_verbosity = "low"
personality = "pragmatic"
approvals_reviewer = "user"
approval_policy = "on-request"
$model_lines
$(full_access_line)

[projects."$HOME"]
trust_level = "trusted"
EOF
  if [ "$SKIP_AGENTS" = 1 ]; then
    skip "AGENTS.md skipped (--no-agents)"
  elif [ -r "$ASSETS_DIR/AGENTS.md.example" ]; then
    mkdir -p -- "$MAIN_CODEX_HOME"
    write_file "$MAIN_CODEX_HOME/AGENTS.md" 644 < "$ASSETS_DIR/AGENTS.md.example"
  fi
}

step_deepseek_home() {
  log "4/8  Creating the DeepSeek CODEX_HOME (~/.codex-deepseek)"
  [ "$DRY_RUN" = 1 ] || { mkdir -p -- "$DEEPSEEK_CODEX_HOME"; chmod 700 -- "$DEEPSEEK_CODEX_HOME"; }
  write_file "$DEEPSEEK_CODEX_HOME/config.toml" 600 <<EOF
model = "$DEEPSEEK_MODEL"
model_provider = "deepseek"
preferred_auth_method = "apikey"
forced_login_method = "api"
$(full_access_line)
model_reasoning_effort = "$DEEPSEEK_EFFORT"
web_search = "disabled"
approvals_reviewer = "user"
model_catalog_json = "$DEEPSEEK_CODEX_HOME/models-deepseek.json"

[model_providers.deepseek]
name = "deepseek"
base_url = "$DEEPSEEK_BASE_URL"
wire_api = "responses"
env_key = "DEEPSEEK_API_KEY"

[projects."$HOME"]
trust_level = "trusted"
EOF
  write_model_catalog
  link_shared_entries
}

write_model_catalog() {
  local target="$DEEPSEEK_CODEX_HOME/models-deepseek.json"
  if [ -r "$CATALOG_OVERRIDE" ]; then
    ok "using the bundled catalog $CATALOG_OVERRIDE"
    write_file "$target" 600 < "$CATALOG_OVERRIDE"
  else
    if [ "$DRY_RUN" = 1 ]; then
      log "dry-run: would build $target from $CATALOG_TEMPLATE"
    else
      mkdir -p -- "$DEEPSEEK_CODEX_HOME"
      local args=(--template "$CATALOG_TEMPLATE" --output "$target")
      [ -n "$BASE_MODEL" ] && args+=(--base-model "$BASE_MODEL")
      python3 "$CATALOG_BUILDER" "${args[@]}" || die "could not build the DeepSeek model catalog"
      chmod 600 -- "$target"
      ok "$target"
    fi
  fi
  if [ "$DRY_RUN" != 1 ] && [ -r "$target" ] && [ ! -e "$MAIN_CODEX_HOME/models-deepseek.json" ]; then
    cp -a -- "$target" "$MAIN_CODEX_HOME/models-deepseek.json"
  fi
}

step_wrapper() {
  log "5/8  Installing the 'deepseek' command"
  [ "$DRY_RUN" = 1 ] || mkdir -p -- "$BIN_DIR"
  write_file "$BIN_DIR/deepseek" 755 <<'WRAPPER_EOF'
#!/usr/bin/env bash
# Runs Codex against DeepSeek using its own CODEX_HOME (~/.codex-deepseek), so
# Codex and DeepSeek can run in parallel without sharing sessions or locks.
set -euo pipefail

CODEX_BIN="${CODEX_BIN:-codex}"
DEEPSEEK_CODEX_HOME="${DEEPSEEK_CODEX_HOME:-$HOME/.codex-deepseek}"
DEEPSEEK_KEY_FILE="${DEEPSEEK_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/deepseek/api_key}"
DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-flash}"
DEEPSEEK_CATALOG="${DEEPSEEK_CATALOG:-$DEEPSEEK_CODEX_HOME/models-deepseek.json}"

key_state() {
  if [ -n "${DEEPSEEK_API_KEY:-}" ]; then printf 'DEEPSEEK_API_KEY (environment)'
  elif [ -s "$DEEPSEEK_KEY_FILE" ]; then printf '%s' "$DEEPSEEK_KEY_FILE"
  else printf 'not found'
  fi
}

check() {
  local state="missing"
  printf 'codex     : %s\n' "$(command -v "$CODEX_BIN" 2>/dev/null || printf 'not found on PATH')"
  [ -f "$DEEPSEEK_CODEX_HOME/config.toml" ] && state="ok"
  printf 'CODEX_HOME: %s (%s)\n' "$DEEPSEEK_CODEX_HOME" "$state"
  state="missing"; [ -f "$DEEPSEEK_CATALOG" ] && state="ok"
  printf 'catalog   : %s (%s)\n' "$DEEPSEEK_CATALOG" "$state"
  printf 'model     : %s\n' "$DEEPSEEK_MODEL"
  printf 'api key   : %s\n' "$(key_state)"
  if command -v "$CODEX_BIN" >/dev/null 2>&1; then
    printf 'version   : %s\n' "$("$CODEX_BIN" --version 2>/dev/null | head -n1)"
  fi
}

case "${1:-}" in
  --check|--doctor) check; exit 0 ;;
esac

if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
  printf 'Cannot find the "%s" binary on PATH.\n' "$CODEX_BIN" >&2
  exit 127
fi

deepseek_key=""
if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
  deepseek_key="$DEEPSEEK_API_KEY"
elif [ -s "$DEEPSEEK_KEY_FILE" ]; then
  deepseek_key="$(<"$DEEPSEEK_KEY_FILE")"
elif [ -t 0 ]; then
  printf 'DeepSeek API key (sk-...): '
  IFS= read -r -s deepseek_key
  printf '\n'
  case "$deepseek_key" in
    sk-*) ;;
    *) printf 'The key must start with sk-.\n' >&2; exit 1 ;;
  esac
  mkdir -p -m 700 -- "$(dirname -- "$DEEPSEEK_KEY_FILE")"
  ( umask 077; printf '%s\n' "$deepseek_key" > "$DEEPSEEK_KEY_FILE" )
  printf 'Saved to %s\n' "$DEEPSEEK_KEY_FILE"
else
  printf 'DeepSeek API key not set.\n' >&2
  printf 'Run "deepseek" in an interactive terminal, or export DEEPSEEK_API_KEY.\n' >&2
  exit 1
fi

DEEPSEEK_API_KEY="$deepseek_key" CODEX_HOME="$DEEPSEEK_CODEX_HOME" exec "$CODEX_BIN" \
  -c "model=\"$DEEPSEEK_MODEL\"" \
  -c 'model_provider="deepseek"' \
  -c "model_catalog_json=\"$DEEPSEEK_CATALOG\"" \
  "$@"
WRAPPER_EOF
}

step_api_key() {
  log "6/8  DeepSeek API key"
  if [ -s "$DEEPSEEK_KEY_FILE" ]; then
    ok "already stored at $DEEPSEEK_KEY_FILE"
    return 0
  fi
  local key="${DEEPSEEK_API_KEY:-}"
  if [ -z "$key" ]; then
    if [ ! -t 0 ]; then
      warn "no interactive terminal: export DEEPSEEK_API_KEY or run 'deepseek' later to be asked for it"
      return 0
    fi
    printf 'Paste your DeepSeek API key (sk-..., Enter to skip): '
    IFS= read -r -s key
    printf '\n'
    [ -n "$key" ] || { warn "skipped: you will be asked the first time you run 'deepseek'"; return 0; }
  fi
  case "$key" in
    sk-*) ;;
    *) warn "that key does not start with sk-: not stored"; return 0 ;;
  esac
  if [ "$DRY_RUN" = 1 ]; then
    log "dry-run: would store the API key in $DEEPSEEK_KEY_FILE (mode 600)"
    return 0
  fi
  mkdir -p -m 700 -- "$(dirname -- "$DEEPSEEK_KEY_FILE")"
  ( umask 077; printf '%s\n' "$key" > "$DEEPSEEK_KEY_FILE" )
  chmod 600 -- "$DEEPSEEK_KEY_FILE"
  ok "stored in $DEEPSEEK_KEY_FILE (mode 600)"
}

step_skills() {
  log "7/8  Skills and shell PATH"
  [ -z "$SKILLS_SRC" ] && [ -d "$ASSETS_DIR/skills" ] && SKILLS_SRC="$ASSETS_DIR/skills"
  if [ -n "$SKILLS_SRC" ]; then
    if [ ! -d "$SKILLS_SRC" ]; then
      warn "$SKILLS_SRC is not a directory: skipping skills"
    elif [ -e "$MAIN_CODEX_HOME/skills" ] && [ "$FORCE" != 1 ]; then
      warn "keeping existing $MAIN_CODEX_HOME/skills (use --force to overwrite)"
    elif [ "$DRY_RUN" = 1 ]; then
      log "dry-run: would copy $SKILLS_SRC -> $MAIN_CODEX_HOME/skills"
    else
      mkdir -p -- "$MAIN_CODEX_HOME/skills"
      cp -a -- "$SKILLS_SRC/." "$MAIN_CODEX_HOME/skills/"
      ok "skills copied to $MAIN_CODEX_HOME/skills"
    fi
  else
    skip "no skills to copy (use --skills-from DIR to add your own)"
  fi
  [ "$DRY_RUN" != 1 ] && mkdir -p -- "$MAIN_CODEX_HOME/skills"
  link_shared_entries
  ensure_path_block "$HOME/.bashrc"
  ensure_path_block "$HOME/.zshrc"
}

step_verify() {
  log "8/8  Verifying"
  if [ "$DRY_RUN" = 1 ]; then
    log "dry-run: nothing to verify"
    return 0
  fi
  local codex_bin=""
  if [ -x "$BIN_DIR/codex" ]; then codex_bin="$BIN_DIR/codex"
  elif have codex; then codex_bin="$(command -v codex)"
  fi
  [ -n "$codex_bin" ] || die "cannot find the codex binary"
  ok "codex    : $("$codex_bin" --version)"
  local models
  models="$(CODEX_HOME="$DEEPSEEK_CODEX_HOME" "$codex_bin" debug models 2>/dev/null \
    | grep -o '"slug": *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' | sort -u | tr '\n' ' ' || true)"
  if [ -n "$models" ]; then
    ok "deepseek : models loaded: ${models% }"
  else
    warn "deepseek : could not read the model catalog back"
  fi
  printf '\n%s%sDone.%s\n' "$C_BOLD" "$C_GREEN" "$C_OFF"
  cat <<EOF

Next steps:
  1) Sign in to Codex with your ChatGPT account:  codex login
  2) Check the DeepSeek side:                     deepseek --check
  3) Open two terminals and run both at once:
       terminal 1 ->  codex
       terminal 2 ->  deepseek

  codex     uses ~/.codex            (ChatGPT login, its own sessions)
  deepseek  uses ~/.codex-deepseek   (DeepSeek API key, its own sessions)

  Separate CODEX_HOMEs mean no shared sessions and no shared locks, so both
  commands can work at the same time, in the same repo if you want.
EOF
}

step_login() {
  [ "$DO_LOGIN" = 1 ] || return 0
  if [ "$DRY_RUN" = 1 ]; then
    log "dry-run: would run 'codex login'"
    return 0
  fi
  log "Running 'codex login'"
  "$BIN_DIR/codex" login || codex login
}

printf '%s%scodex-tandem%s -- Codex + DeepSeek, side by side\n\n' "$C_BOLD" "$C_BLUE" "$C_OFF"
step_preflight
step_codex
step_config_codex
step_deepseek_home
step_wrapper
step_api_key
step_skills
step_verify
step_login
