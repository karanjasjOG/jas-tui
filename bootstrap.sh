#!/usr/bin/env bash
# bootstrap.sh - install the Vim + tmux dotfiles in this repo.
#
#   ./bootstrap.sh            apply (idempotent), then run --check
#   ./bootstrap.sh --check    verify only; change nothing; exit 1 if anything is wrong
#   ./bootstrap.sh --dry-run  print what apply would do; change nothing
#
# No sudo, no curl | sh. Homebrew is required on macOS but never installed by this script.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BACKUP_ROOT="$HOME/.dotfiles-backup"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=""   # created lazily, only if something needs backing up

# target in $HOME -> source in repo
LINKS=(
  "$HOME/.vimrc|$REPO_DIR/vim/vimrc"
  "$HOME/.vim|$REPO_DIR/vim"
  "$HOME/.tmux.conf|$REPO_DIR/tmux/tmux.conf"
)

MODE="apply"
case "${1:-}" in
  "")         ;;
  --check)    MODE="check" ;;
  --dry-run)  MODE="dry-run" ;;
  -h|--help)  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)          echo "unknown argument: $1 (use --check, --dry-run or --help)" >&2; exit 2 ;;
esac

if [[ -t 1 ]]; then
  C_OK=$'\033[32m' C_WARN=$'\033[33m' C_FAIL=$'\033[31m' C_DIM=$'\033[2m' C_BOLD=$'\033[1m' C_OFF=$'\033[0m'
else
  C_OK="" C_WARN="" C_FAIL="" C_DIM="" C_BOLD="" C_OFF=""
fi

FAILURES=0
step() { printf '\n%s==> %s%s\n' "$C_BOLD" "$1" "$C_OFF"; }
ok()   { printf '  %sok%s    %s\n' "$C_OK" "$C_OFF" "$1"; }
warn() { printf '  %swarn%s  %s\n' "$C_WARN" "$C_OFF" "$1"; }
fail() { printf '  %sFAIL%s  %s\n' "$C_FAIL" "$C_OFF" "$1"; FAILURES=$((FAILURES + 1)); }
info() { printf '  %s%s%s\n' "$C_DIM" "$1" "$C_OFF"; }
would(){ printf '  %swould%s %s\n' "$C_WARN" "$C_OFF" "$1"; }

# Run a command, or only describe it in dry-run mode.
run() {
  if [[ "$MODE" == "dry-run" ]]; then would "run: $*"; else info "run: $*"; "$@"; fi
}

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

# ---------------------------------------------------------------- apply steps

ensure_homebrew() {
  step "Homebrew"
  if command -v brew >/dev/null 2>&1; then
    ok "brew found: $(command -v brew)"
    return 0
  fi
  if ! is_macos; then
    warn "brew not found; on Linux install vim and tmux with your package manager instead (skipping brew bundle)"
    return 1
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    fail "Homebrew is installed but not on PATH. Add this to your shell profile and re-run:"
    info "  eval \"\$(/opt/homebrew/bin/brew shellenv)\""
  else
    fail "Homebrew is not installed. Install it yourself from https://brew.sh, then re-run this script."
  fi
  exit 1
}

brew_bundle() {
  step "brew bundle (Brewfile)"
  if brew bundle check --file="$REPO_DIR/Brewfile" --no-upgrade >/dev/null 2>&1; then
    ok "all Brewfile dependencies already installed"
  else
    run brew bundle install --file="$REPO_DIR/Brewfile" --no-upgrade
  fi
}

submodules() {
  step "Plugin submodules"
  local status
  status="$(git -C "$REPO_DIR" submodule status --recursive)"
  if grep -q '^[-+U]' <<<"$status"; then
    run git -C "$REPO_DIR" submodule update --init --recursive
  else
    ok "submodules initialised at their pinned commits"
  fi
}

backup() {
  local target="$1"
  if [[ -z "$BACKUP_DIR" ]]; then
    BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
    run mkdir -p "$BACKUP_DIR"
  fi
  run mv "$target" "$BACKUP_DIR/"
}

link_all() {
  step "Symlinks"
  local pair target src
  for pair in "${LINKS[@]}"; do
    target="${pair%%|*}"; src="${pair#*|}"
    if [[ -L "$target" && "$(readlink "$target")" == "$src" ]]; then
      ok "$target -> $src (already correct)"
      continue
    fi
    if [[ -e "$target" || -L "$target" ]]; then
      backup "$target"
    fi
    run ln -s "$src" "$target"
  done
  if [[ -n "$BACKUP_DIR" && "$MODE" == "dry-run" ]]; then
    info "previous files would be backed up to: $BACKUP_DIR"
  elif [[ -n "$BACKUP_DIR" ]]; then
    info "previous files backed up to: $BACKUP_DIR"
  fi
}

# ---------------------------------------------------------------- checks

check_binaries() {
  step "Binaries"
  local bin
  for bin in git vim tmux; do
    if command -v "$bin" >/dev/null 2>&1; then
      case "$bin" in
        git)  ok "git  $(git --version | awk '{print $3}')  ($(command -v git))" ;;
        vim)  ok "vim  $(vim --version | head -1 | sed 's/^VIM - Vi IMproved //')  ($(command -v vim))" ;;
        tmux) ok "tmux $(tmux -V | awk '{print $2}')  ($(command -v tmux))" ;;
      esac
    else
      fail "$bin not found on PATH"
    fi
  done
  if command -v vim >/dev/null 2>&1; then
    if vim --version | grep -q '+clipboard'; then
      ok "vim has +clipboard (needed for <leader>y / <leader>p)"
    else
      warn "vim lacks +clipboard; <leader>y / <leader>p system-clipboard mappings will not work"
    fi
  fi
}

check_links() {
  step "Symlinks point into $REPO_DIR"
  local pair target src
  for pair in "${LINKS[@]}"; do
    target="${pair%%|*}"; src="${pair#*|}"
    if [[ -L "$target" && "$(readlink "$target")" == "$src" ]]; then
      ok "$target -> $src"
    elif [[ -L "$target" ]]; then
      fail "$target -> $(readlink "$target") (expected $src)"
    elif [[ -e "$target" ]]; then
      fail "$target is a regular file/dir, not a symlink into the repo"
    else
      fail "$target does not exist"
    fi
  done
}

check_plugins() {
  step "Vim plugins (native packages)"
  local path
  while read -r _ path; do
    if [[ -d "$REPO_DIR/$path" && -n "$(ls -A "$REPO_DIR/$path" 2>/dev/null)" ]]; then
      ok "$path  @ $(git -C "$REPO_DIR/$path" rev-parse --short HEAD)"
    else
      fail "$path is missing or empty (run: git submodule update --init --recursive)"
    fi
  done < <(git -C "$REPO_DIR" config -f .gitmodules --get-regexp '^submodule\..*\.path$')
}

check_vim() {
  step "Vim loads ~/.vimrc cleanly"
  # -i NONE: don't read or write ~/.viminfo. The :messages dump surfaces the
  # actual error text, which -es otherwise swallows.
  local out
  if out="$(vim -Nes -i NONE -u "$HOME/.vimrc" \
              -c 'call writefile(split(execute("messages"), "\n"), "/dev/stdout")' \
              -c 'qa!' 2>&1)"; then
    ok "vim -Nes -i NONE -u ~/.vimrc -c 'qa!' exited 0"
  else
    fail "vim reported errors loading ~/.vimrc:"
    printf '%s\n' "$out" | grep -v '^Messages maintainer' | sed 's/^/        /' || true
  fi
}

check_tmux() {
  step "tmux parses ~/.tmux.conf cleanly"
  # start-server alone exits 0 even when the config is broken, and source-file
  # also exits 0 but prints each error, so treat any output as a failure.
  local socket="bootstrap-check-$$" out
  out="$(tmux -L "$socket" -f /dev/null start-server \; source-file "$HOME/.tmux.conf" 2>&1 || true)"
  tmux -L "$socket" kill-server >/dev/null 2>&1 || true
  if [[ -z "$out" ]]; then
    ok "tmux source-file ~/.tmux.conf on a throwaway server: no errors"
  else
    fail "tmux reported errors in ~/.tmux.conf:"
    printf '%s\n' "$out" | sed 's/^/        /'
  fi
}

run_checks() {
  FAILURES=0
  # Each check records failures via fail(); "|| true" keeps set -e from
  # aborting the remaining checks if a check function's last command is non-zero.
  check_binaries || true
  check_links    || true
  check_plugins  || true
  check_vim      || true
  check_tmux     || true
  printf '\n'
  if [[ "$FAILURES" -eq 0 ]]; then
    printf '%sCHECK PASSED%s\n' "$C_OK" "$C_OFF"
    return 0
  fi
  printf '%sCHECK FAILED: %d problem(s)%s\n' "$C_FAIL" "$FAILURES" "$C_OFF"
  return 1
}

# ---------------------------------------------------------------- main

printf '%sjas-tui bootstrap%s  mode=%s  repo=%s\n' "$C_BOLD" "$C_OFF" "$MODE" "$REPO_DIR"

if [[ "$MODE" == "check" ]]; then
  run_checks
  exit $?
fi

if ensure_homebrew; then
  brew_bundle
fi
submodules
link_all

if [[ "$MODE" == "dry-run" ]]; then
  printf '\n%sDry run complete; nothing was changed.%s\n' "$C_BOLD" "$C_OFF"
  exit 0
fi

run_checks
