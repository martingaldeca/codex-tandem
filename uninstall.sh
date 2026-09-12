#!/usr/bin/env bash
#
# codex-tandem -- uninstaller. Removes the DeepSeek side and, optionally, the
# Codex CLI state. Nothing outside your HOME is touched.
#
set -euo pipefail

MARKER="codex-tandem parallel setup"
MAIN_CODEX_HOME="$HOME/.codex"
DEEPSEEK_CODEX_HOME="$HOME/.codex-deepseek"
DEEPSEEK_KEY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/deepseek/api_key"
BIN_DIR="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
WRAPPER="$BIN_DIR/deepseek"

DRY_RUN=0
ASSUME_YES=0
PURGE_KEY=0
REMOVE_CODEX=0

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

usage() {
  cat <<'USAGE'
codex-tandem uninstaller

Usage: ./uninstall.sh [options]

By default it removes:
  ~/.local/bin/deepseek       the DeepSeek wrapper
  ~/.codex-deepseek           the separate CODEX_HOME
  the marked PATH block in ~/.bashrc and ~/.zshrc

It keeps by default:
  ~/.codex                    (the Codex CLI itself and its login)
  the DeepSeek API key in ~/.config/deepseek/api_key

Options:
  -h, --help     Show this help.
      --dry-run  Show what would be removed, delete nothing.
  -y, --yes      Do not ask for confirmation.
      --purge-key  Also delete the stored DeepSeek API key.
      --all        Also delete ~/.codex (Codex CLI state and login).
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   usage; exit 0 ;;
    --dry-run)   DRY_RUN=1 ;;
    -y|--yes)    ASSUME_YES=1 ;;
    --purge-key) PURGE_KEY=1 ;;
    --all)       PURGE_KEY=1; REMOVE_CODEX=1 ;;
    *)           usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

[ -n "${HOME:-}" ] || die "HOME is not set"

remove_path() {
  local path="$1"
  case "$path" in
    "$HOME"/*) ;;
    *) die "refusing to remove anything outside HOME: $path" ;;
  esac
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    skip "$path (not there)"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    log "dry-run: would remove $path"
    return 0
  fi
  rm -rf -- "$path"
  ok "removed $path"
}

strip_block() {
  local rc="$1"
  [ -e "$rc" ] || return 0
  grep -q "$MARKER" "$rc" 2>/dev/null || { skip "$rc (no codex-tandem block)"; return 0; }
  if [ "$DRY_RUN" = 1 ]; then
    log "dry-run: would remove the codex-tandem PATH block from $rc"
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  sed "/# >>> $MARKER >>>/,/# <<< $MARKER <<</d" "$rc" > "$tmp"
  cat "$tmp" > "$rc"
  rm -f -- "$tmp"
  ok "cleaned $rc"
}

printf '%s%scodex-tandem uninstaller%s\n\n' "$C_BOLD" "$C_BLUE" "$C_OFF"
log "This will remove:"
printf '    %s\n' "$WRAPPER" "$DEEPSEEK_CODEX_HOME"
[ "$PURGE_KEY" = 1 ] && printf '    %s\n' "$DEEPSEEK_KEY_FILE"
[ "$REMOVE_CODEX" = 1 ] && printf '    %s\n' "$MAIN_CODEX_HOME"
printf '    PATH block in ~/.bashrc and ~/.zshrc\n\n'

if [ "$DRY_RUN" != 1 ] && [ "$ASSUME_YES" != 1 ]; then
  if [ ! -t 0 ]; then
    die "not an interactive terminal: re-run with --yes to confirm"
  fi
  printf 'Continue? [y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) die "aborted, nothing was removed" ;;
  esac
fi

remove_path "$WRAPPER"
remove_path "$DEEPSEEK_CODEX_HOME"
if [ "$PURGE_KEY" = 1 ]; then
  remove_path "$DEEPSEEK_KEY_FILE"
  key_dir="$(dirname -- "$DEEPSEEK_KEY_FILE")"
  if [ "$(basename -- "$key_dir")" = "deepseek" ]; then
    remove_path "$key_dir"
  else
    skip "$key_dir (not a 'deepseek' directory: left alone)"
  fi
fi
if [ "$REMOVE_CODEX" = 1 ]; then
  remove_path "$MAIN_CODEX_HOME"
fi
strip_block "$HOME/.bashrc"
strip_block "$HOME/.zshrc"

if [ "$DRY_RUN" = 1 ]; then
  printf '\n%sDry run: nothing was deleted.%s\n' "$C_BOLD" "$C_OFF"
else
  printf '\n%s%sDone.%s\n' "$C_BOLD" "$C_GREEN" "$C_OFF"
  printf 'Open a new shell (or source your rc file) so PATH is refreshed.\n'
fi
