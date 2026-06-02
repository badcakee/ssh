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
  bash uninstall.sh client
  sudo bash uninstall.sh vps1
  sudo bash uninstall.sh vps2
  sudo bash uninstall.sh peer
  sudo bash uninstall.sh all

Aliases:
  vm1 = vps1, vm2 = vps2, vm3 = peer
EOF
}

main() {
  [[ -f "${INSTALL_SCRIPT}" ]] || fail "install.sh not found next to uninstall.sh"

  case "${1:-}" in
    -h|--help)
      print_help
      exit 0
      ;;
  esac

  if (($# == 0)); then
    exec bash "${INSTALL_SCRIPT}" remove vps1
  fi

  exec bash "${INSTALL_SCRIPT}" remove "$@"
}

main "$@"
