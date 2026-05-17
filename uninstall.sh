#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install.sh"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

print_help() {
  cat <<'EOF'
cakessh uninstall

Usage:
  bash uninstall.sh
  bash uninstall.sh client
  sudo bash uninstall.sh vps1
  sudo bash uninstall.sh vps2
  sudo bash uninstall.sh all
EOF
}

main() {
  [[ -f "${INSTALL_SCRIPT}" ]] || fail "install.sh not found next to uninstall.sh"

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    print_help
    exit 0
  fi

  if (($# == 0)); then
    exec bash "${INSTALL_SCRIPT}" remove
  fi

  exec bash "${INSTALL_SCRIPT}" remove "$@"
}

main "$@"
