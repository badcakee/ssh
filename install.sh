#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
HELPER_SOURCE="${SCRIPT_DIR}/cakessh"

ACTION="install"
ROLE=""

VPS1_IPV4=""
VPS1_USER=""
VPS1_SSH_PORT=""
VPS2_USER=""
VPS2_SSH_PORT=""
IDENTITY_FILE=""
PUBLIC_SSH_FORWARD_PORT=""
WINGS_SCHEME=""
WINGS_PUBLIC_PORT=""
WINGS_TARGET_PORT=""
GAME_PORTS_RAW=""
INSTALL_CLIENT_HELPER="yes"
PEER_NAME=""
PEER_USER=""
PEER_SSH_PORT=""
PEER_PUBLIC_SSH_PORT=""
PEER_WINGS_PUBLIC_PORT=""
PEER_WINGS_TARGET_PORT=""

WG_INTERFACE=""
WG_PORT=""
WG_VPS1_ADDRESS=""
WG_VPS2_ADDRESS=""
WG_PEER_ADDRESS=""
WG_VPS1_PUBLIC_KEY=""
WG_VPS2_PUBLIC_KEY=""
WG_PEER_PUBLIC_KEY=""
WG_WATCHDOG_STALE_SECONDS=""
WG_WATCHDOG_RESTART_ON_STALE=""
WG_VPS1_IP=""
WG_VPS2_IP=""
WG_PEER_IP=""
VPS2_HOST=""

CLIENT_INSTALL_USER=""
CLIENT_INSTALL_HOME=""
LOCAL_WG_PRIVATE_KEY=""
LOCAL_WG_PUBLIC_KEY=""
VPS2_SSH_REACHABLE="unknown"

RELAY_NAMES=()
RELAY_LISTEN_PORTS=()
RELAY_TARGET_PORTS=()
RELAY_DESCRIPTIONS=()
FORWARD_RULE_NAMES=()
FORWARD_RULE_LISTEN_SPECS=()
FORWARD_RULE_TARGET_HOSTS=()
FORWARD_RULE_TARGET_SPECS=()
FORWARD_RULE_DESCRIPTIONS=()
FORWARD_LISTEN_PORT_CHECKS=()
GAME_PORT_LIST=()
GAME_PORT_RANGE_LIST=()
GAME_PORTS_CANONICAL=""

DEFAULT_VPS1_USER="root"
DEFAULT_VPS2_USER="root"
DEFAULT_PEER_USER="root"
DEFAULT_VPS1_SSH_PORT="22"
DEFAULT_VPS2_SSH_PORT="22"
DEFAULT_PEER_SSH_PORT="22"
DEFAULT_PUBLIC_SSH_FORWARD_PORT="2222"
DEFAULT_PEER_PUBLIC_SSH_PORT="2223"
DEFAULT_PEER_WINGS_PUBLIC_PORT="8081"
DEFAULT_PEER_WINGS_TARGET_PORT="8080"
DEFAULT_WINGS_SCHEME="http"
DEFAULT_WINGS_HTTP_PORT="8080"
DEFAULT_WINGS_HTTPS_PORT="8443"
DEFAULT_GAME_PORTS_RAW="25565"
DEFAULT_WG_INTERFACE="cakessh-wg"
DEFAULT_WG_PORT="51820"
DEFAULT_WG_VPS1_ADDRESS="172.31.250.1/30"
DEFAULT_WG_VPS2_ADDRESS="172.31.250.2/30"
DEFAULT_WG_PEER_ADDRESS="172.31.250.3/32"
DEFAULT_WG_WATCHDOG_STALE_SECONDS="1800"
DEFAULT_WG_WATCHDOG_RESTART_ON_STALE="no"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

info() {
  printf '%s\n' "$*"
}

progress() {
  printf '[%s/%s] %s\n' "$1" "$2" "$3"
}

stdin_is_tty() {
  [[ -t 0 ]]
}

print_help() {
  cat <<'EOF'
cakessh installer

Usage:
  bash install.sh
  bash install.sh client
  sudo bash install.sh vps1
  sudo bash install.sh vps2
  sudo bash install.sh peer
  sudo bash install.sh vps1-add-peer
  sudo bash install.sh all
  sudo bash install.sh show-key vps1
  sudo bash install.sh show-key vps2
  sudo bash install.sh show-key peer
  sudo bash install.sh remove vps1
  sudo bash install.sh remove peer

Roles:
  client   Install the local `cakessh` helper only.
  vps1     Install WireGuard on VPS1 and, once VPS2's public key is known, install the TCP forwarder.
  vps2     Install WireGuard on VPS2 so it auto-connects back to VPS1.
  peer     Install WireGuard on an extra SSH-only backend VPS, such as VPS3 or VPS4.
  vps1-add-peer
           Add an extra SSH-only backend VPS to VPS1 with its own public SSH port.
  all      Run the VPS1 flow and also install the local `cakessh` helper.

Client extras:
  - creates `cakessh connect` for SSH through VPS1
  - creates `cakessh direct` for SSH through VPS1's forwarded SSH port
  - creates SSH aliases `cakessh-vps2` and `cakessh-vps2-port`

Optional flags:
  --role client|vps1|vps2|peer|vps1-add-peer|all
  --mode install|remove|show-key
  --vps1-ipv4 203.0.113.10
  --vps1-user root
  --vps1-ssh-port 22
  --vps2-user root
  --vps2-ssh-port 22
  --peer-name vps3
  --peer-user root
  --peer-ssh-port 22
  --peer-public-ssh-port 2223
  --peer-wings-public-port 8081
  --peer-wings-target-port 8080
  --identity-file /path/to/key
  --public-ssh-port 2222
  --wings-scheme http|https
  --wings-port 8080
  --wings-public-port 8080
  --wings-target-port 8080
  --game-ports 25565,25566,3000-4000
  --wg-interface cakessh-wg
  --wg-port 51820
  --wg-vps1-address 10.0.0.1/24
  --wg-vps2-address 10.0.0.2/24
  --wg-peer-address 172.31.250.3/32
  --wg-vps1-public-key BASE64KEY
  --wg-vps2-public-key BASE64KEY
  --wg-peer-public-key BASE64KEY
  --wg-watchdog-stale-seconds 1800
  --wg-watchdog-restart-on-stale yes|no
  --no-client-helper
  --help

Uninstall:
  bash uninstall.sh client
  sudo bash uninstall.sh vps1
  sudo bash uninstall.sh vps2
  sudo bash uninstall.sh peer

Show WireGuard public keys:
  sudo bash install.sh show-key vps1
  sudo bash install.sh show-key vps2
  sudo bash install.sh show-key peer
EOF
}

prompt_value() {
  local variable_name="$1"
  local prompt_text="$2"
  local default_value="${3:-}"
  local current_value="${!variable_name:-}"
  local reply=""

  if [[ -n "${current_value}" ]]; then
    return 0
  fi

  if ! stdin_is_tty; then
    if [[ -n "${default_value}" ]]; then
      printf -v "${variable_name}" '%s' "${default_value}"
      return 0
    fi

    fail "Missing required value for ${variable_name}. Pass the matching flag or run the installer interactively."
  fi

  if [[ -n "${default_value}" ]]; then
    read -r -p "${prompt_text} [${default_value}]: " reply
    reply="${reply:-${default_value}}"
  else
    read -r -p "${prompt_text}: " reply
  fi

  printf -v "${variable_name}" '%s' "${reply}"
}

prompt_optional_value() {
  local variable_name="$1"
  local prompt_text="$2"
  local current_value="${!variable_name:-}"
  local reply=""

  if [[ -n "${current_value}" || ! stdin_is_tty ]]; then
    return 0
  fi

  read -r -p "${prompt_text}: " reply
  printf -v "${variable_name}" '%s' "${reply}"
}

prompt_yes_no() {
  local prompt_text="$1"
  local default_answer="${2:-y}"
  local reply=""

  if ! stdin_is_tty; then
    [[ "${default_answer}" == "y" ]]
    return
  fi

  while true; do
    if [[ "${default_answer}" == "y" ]]; then
      read -r -p "${prompt_text} [Y/n]: " reply
      reply="${reply:-y}"
    else
      read -r -p "${prompt_text} [y/N]: " reply
      reply="${reply:-n}"
    fi

    case "${reply}" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
      *) info "Please answer y or n." ;;
    esac
  done
}

detect_primary_ipv4() {
  if command -v ip >/dev/null 2>&1; then
    ip -o -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}'
    return
  fi

  if command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1; exit}'
    return
  fi
}

is_supported_role() {
  case "$1" in
    client|vps1|vps2|peer|vps1-add-peer|all) return 0 ;;
    *) return 1 ;;
  esac
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      show-key)
        ACTION="show-key"
        shift
        ;;
      show-vps1-key)
        ACTION="show-key"
        ROLE="vps1"
        shift
        ;;
      show-vps2-key)
        ACTION="show-key"
        ROLE="vps2"
        shift
        ;;
      show-peer-key)
        ACTION="show-key"
        ROLE="peer"
        shift
        ;;
      client|vps1|vps2|peer|vps1-add-peer|all)
        [[ -z "${ROLE}" ]] || fail "Role already set to ${ROLE}"
        ROLE="$1"
        shift
        ;;
      remove)
        ACTION="remove"
        shift
        ;;
      --role)
        [[ $# -ge 2 ]] || fail "Missing value for --role"
        ROLE="$2"
        shift 2
        ;;
      --mode)
        [[ $# -ge 2 ]] || fail "Missing value for --mode"
        ACTION="$2"
        shift 2
        ;;
      --vps1-ipv4)
        [[ $# -ge 2 ]] || fail "Missing value for --vps1-ipv4"
        VPS1_IPV4="$2"
        shift 2
        ;;
      --vps1-user)
        [[ $# -ge 2 ]] || fail "Missing value for --vps1-user"
        VPS1_USER="$2"
        shift 2
        ;;
      --vps1-ssh-port)
        [[ $# -ge 2 ]] || fail "Missing value for --vps1-ssh-port"
        VPS1_SSH_PORT="$2"
        shift 2
        ;;
      --vps2-user)
        [[ $# -ge 2 ]] || fail "Missing value for --vps2-user"
        VPS2_USER="$2"
        shift 2
        ;;
      --vps2-ssh-port)
        [[ $# -ge 2 ]] || fail "Missing value for --vps2-ssh-port"
        VPS2_SSH_PORT="$2"
        shift 2
        ;;
      --peer-name)
        [[ $# -ge 2 ]] || fail "Missing value for --peer-name"
        PEER_NAME="$2"
        shift 2
        ;;
      --peer-user)
        [[ $# -ge 2 ]] || fail "Missing value for --peer-user"
        PEER_USER="$2"
        shift 2
        ;;
      --peer-ssh-port)
        [[ $# -ge 2 ]] || fail "Missing value for --peer-ssh-port"
        PEER_SSH_PORT="$2"
        shift 2
        ;;
      --peer-public-ssh-port|--public-peer-ssh-port)
        [[ $# -ge 2 ]] || fail "Missing value for --peer-public-ssh-port"
        PEER_PUBLIC_SSH_PORT="$2"
        shift 2
        ;;
      --peer-wings-public-port)
        [[ $# -ge 2 ]] || fail "Missing value for --peer-wings-public-port"
        PEER_WINGS_PUBLIC_PORT="$2"
        shift 2
        ;;
      --peer-wings-target-port)
        [[ $# -ge 2 ]] || fail "Missing value for --peer-wings-target-port"
        PEER_WINGS_TARGET_PORT="$2"
        shift 2
        ;;
      --identity-file)
        [[ $# -ge 2 ]] || fail "Missing value for --identity-file"
        IDENTITY_FILE="$2"
        shift 2
        ;;
      --public-ssh-port)
        [[ $# -ge 2 ]] || fail "Missing value for --public-ssh-port"
        PUBLIC_SSH_FORWARD_PORT="$2"
        shift 2
        ;;
      --wings-scheme)
        [[ $# -ge 2 ]] || fail "Missing value for --wings-scheme"
        WINGS_SCHEME="$2"
        shift 2
        ;;
      --wings-public-port)
        [[ $# -ge 2 ]] || fail "Missing value for --wings-public-port"
        WINGS_PUBLIC_PORT="$2"
        shift 2
        ;;
      --wings-port)
        [[ $# -ge 2 ]] || fail "Missing value for --wings-port"
        WINGS_PUBLIC_PORT="$2"
        WINGS_TARGET_PORT="${WINGS_TARGET_PORT:-$2}"
        shift 2
        ;;
      --wings-target-port)
        [[ $# -ge 2 ]] || fail "Missing value for --wings-target-port"
        WINGS_TARGET_PORT="$2"
        shift 2
        ;;
      --game-ports)
        [[ $# -ge 2 ]] || fail "Missing value for --game-ports"
        GAME_PORTS_RAW="$2"
        shift 2
        ;;
      --wg-interface)
        [[ $# -ge 2 ]] || fail "Missing value for --wg-interface"
        WG_INTERFACE="$2"
        shift 2
        ;;
      --wg-port)
        [[ $# -ge 2 ]] || fail "Missing value for --wg-port"
        WG_PORT="$2"
        shift 2
        ;;
      --wg-vps1-address)
        [[ $# -ge 2 ]] || fail "Missing value for --wg-vps1-address"
        WG_VPS1_ADDRESS="$2"
        shift 2
        ;;
      --wg-vps2-address)
        [[ $# -ge 2 ]] || fail "Missing value for --wg-vps2-address"
        WG_VPS2_ADDRESS="$2"
        shift 2
        ;;
      --wg-peer-address)
        [[ $# -ge 2 ]] || fail "Missing value for --wg-peer-address"
        WG_PEER_ADDRESS="$2"
        shift 2
        ;;
      --wg-vps1-public-key)
        [[ $# -ge 2 ]] || fail "Missing value for --wg-vps1-public-key"
        WG_VPS1_PUBLIC_KEY="$2"
        shift 2
        ;;
      --wg-vps2-public-key)
        [[ $# -ge 2 ]] || fail "Missing value for --wg-vps2-public-key"
        WG_VPS2_PUBLIC_KEY="$2"
        shift 2
        ;;
      --wg-peer-public-key)
        [[ $# -ge 2 ]] || fail "Missing value for --wg-peer-public-key"
        WG_PEER_PUBLIC_KEY="$2"
        shift 2
        ;;
      --wg-watchdog-stale-seconds)
        [[ $# -ge 2 ]] || fail "Missing value for --wg-watchdog-stale-seconds"
        WG_WATCHDOG_STALE_SECONDS="$2"
        shift 2
        ;;
      --wg-watchdog-restart-on-stale)
        [[ $# -ge 2 ]] || fail "Missing value for --wg-watchdog-restart-on-stale"
        WG_WATCHDOG_RESTART_ON_STALE="$2"
        shift 2
        ;;
      --no-client-helper)
        INSTALL_CLIENT_HELPER="no"
        shift
        ;;
      --help|-h)
        print_help
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done

  case "${ACTION}" in
    install|remove|show-key) ;;
    *) fail "Unsupported mode: ${ACTION}" ;;
  esac

  if [[ -n "${ROLE}" ]] && ! is_supported_role "${ROLE}"; then
    fail "Unsupported role: ${ROLE}"
  fi
}

prompt_role_if_needed() {
  if [[ -n "${ROLE}" ]]; then
    return 0
  fi

  if ! stdin_is_tty; then
    case "${ACTION}" in
      remove|show-key) ROLE="vps1" ;;
      *) ROLE="all" ;;
    esac
    return 0
  fi

  local reply=""
  while true; do
    case "${ACTION}" in
      remove)
        read -r -p "What do you want to remove? (client/vps1/vps2/peer/all) [vps1]: " reply
        reply="${reply:-vps1}"
        case "${reply}" in
          client|vps1|vps2|peer|all)
            ROLE="${reply}"
            return 0
            ;;
          *)
            info "Please choose client, vps1, vps2, peer, or all."
            ;;
        esac
        ;;
      show-key)
        read -r -p "Which WireGuard public key do you want to show? (vps1/vps2/peer) [vps1]: " reply
        reply="${reply:-vps1}"
        case "${reply}" in
          vps1|vps2|peer)
            ROLE="${reply}"
            return 0
            ;;
          *)
            info "Please choose vps1, vps2, or peer."
            ;;
        esac
        ;;
      *)
        read -r -p "Which role do you want to install? (client/vps1/vps2/peer/vps1-add-peer/all) [all]: " reply
        reply="${reply:-all}"
        if is_supported_role "${reply}"; then
          ROLE="${reply}"
          return 0
        fi
        info "Please choose client, vps1, vps2, peer, vps1-add-peer, or all."
        ;;
    esac
  done
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "This step must be run as root. Try: sudo bash install.sh ${ROLE}"
}

determine_client_home() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    CLIENT_INSTALL_USER="${SUDO_USER}"
    if command -v getent >/dev/null 2>&1; then
      CLIENT_INSTALL_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
    else
      CLIENT_INSTALL_HOME="$(eval "printf '%s' ~${SUDO_USER}")"
    fi
  else
    CLIENT_INSTALL_USER="${USER:-$(id -un)}"
    CLIENT_INSTALL_HOME="${HOME}"
  fi

  [[ -n "${CLIENT_INSTALL_HOME}" ]] || fail "Could not determine the client home directory."
  [[ "${CLIENT_INSTALL_HOME}" != "~${CLIENT_INSTALL_USER}" ]] || fail "Could not resolve the home directory for ${CLIENT_INSTALL_USER}."
}

validate_port() {
  local port="$1"
  [[ "${port}" =~ ^[0-9]+$ ]] || fail "Port must be numeric: ${port}"
  ((port >= 1 && port <= 65535)) || fail "Port must be between 1 and 65535: ${port}"
}

validate_wings_scheme() {
  case "${WINGS_SCHEME}" in
    http|https) ;;
    *) fail "Wings scheme must be http or https, not ${WINGS_SCHEME}" ;;
  esac
}

validate_yes_no() {
  local value="$1"
  local label="$2"

  case "${value}" in
    yes|no) ;;
    *) fail "${label} must be yes or no, not ${value}" ;;
  esac
}

array_contains() {
  local needle="$1"
  shift || true
  local item=""
  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

append_game_port_range() {
  local range_start="$1"
  local range_end="$2"

  if [[ "${range_start}" == "${range_end}" ]]; then
    GAME_PORT_RANGE_LIST+=("${range_start}")
  else
    GAME_PORT_RANGE_LIST+=("${range_start}-${range_end}")
  fi
}

compress_game_ports() {
  local current_port=""
  local previous_port=""
  local range_start=""
  local sorted_port=""
  local -a sorted_ports=()

  GAME_PORT_RANGE_LIST=()
  GAME_PORTS_CANONICAL=""

  while IFS= read -r sorted_port; do
    [[ -n "${sorted_port}" ]] || continue
    sorted_ports+=("${sorted_port}")
  done < <(printf '%s\n' "${GAME_PORT_LIST[@]}" | sort -n)

  ((${#sorted_ports[@]} > 0)) || return 0

  range_start="${sorted_ports[0]}"
  previous_port="${sorted_ports[0]}"

  for current_port in "${sorted_ports[@]:1}"; do
    if (( current_port == previous_port + 1 )); then
      previous_port="${current_port}"
      continue
    fi

    append_game_port_range "${range_start}" "${previous_port}"
    range_start="${current_port}"
    previous_port="${current_port}"
  done

  append_game_port_range "${range_start}" "${previous_port}"
  GAME_PORTS_CANONICAL="$(join_by_comma "${GAME_PORT_RANGE_LIST[@]}")"
}

normalize_game_ports() {
  local cleaned="${GAME_PORTS_RAW//,/ }"
  local token=""
  local range_start=""
  local range_end=""
  local current_port=""
  GAME_PORT_LIST=()

  for token in ${cleaned}; do
    if [[ "${token}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      range_start="${BASH_REMATCH[1]}"
      range_end="${BASH_REMATCH[2]}"
      validate_port "${range_start}"
      validate_port "${range_end}"
      ((range_start <= range_end)) || fail "Invalid port range: ${token}"

      current_port="${range_start}"
      while ((current_port <= range_end)); do
        if ! array_contains "${current_port}" "${GAME_PORT_LIST[@]:-}"; then
          GAME_PORT_LIST+=("${current_port}")
        fi
        ((current_port++))
      done
      continue
    fi

    validate_port "${token}"
    if ! array_contains "${token}" "${GAME_PORT_LIST[@]:-}"; then
      GAME_PORT_LIST+=("${token}")
    fi
  done

  ((${#GAME_PORT_LIST[@]} > 0)) || fail "At least one game port is required."
  compress_game_ports
}

validate_ipv4_basic() {
  local ip="$1"
  local octet=""

  [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "Invalid IPv4 format: ${ip}"
  IFS='.' read -r -a octets <<< "${ip}"
  for octet in "${octets[@]}"; do
    ((octet >= 0 && octet <= 255)) || fail "Invalid IPv4 octet in ${ip}"
  done
}

validate_ipv4_cidr() {
  local cidr="$1"
  local ip_part="${cidr%%/*}"
  local prefix="${cidr#*/}"

  [[ "${cidr}" == */* ]] || fail "WireGuard address must use CIDR notation: ${cidr}"
  validate_ipv4_basic "${ip_part}"
  [[ "${prefix}" =~ ^[0-9]+$ ]] || fail "Invalid CIDR prefix in ${cidr}"
  ((prefix >= 0 && prefix <= 32)) || fail "CIDR prefix must be between 0 and 32: ${cidr}"
}

validate_wireguard_public_key_if_present() {
  local key="$1"

  if [[ -z "${key}" ]]; then
    return 0
  fi

  [[ "${key}" =~ ^[A-Za-z0-9+/=]+$ ]] || fail "WireGuard public key contains invalid characters."
  ((${#key} >= 40)) || fail "WireGuard public key looks too short."
}

apply_defaults() {
  VPS1_USER="${VPS1_USER:-${DEFAULT_VPS1_USER}}"
  VPS2_USER="${VPS2_USER:-${DEFAULT_VPS2_USER}}"
  PEER_USER="${PEER_USER:-${DEFAULT_PEER_USER}}"
  VPS1_SSH_PORT="${VPS1_SSH_PORT:-${DEFAULT_VPS1_SSH_PORT}}"
  VPS2_SSH_PORT="${VPS2_SSH_PORT:-${DEFAULT_VPS2_SSH_PORT}}"
  PEER_SSH_PORT="${PEER_SSH_PORT:-${DEFAULT_PEER_SSH_PORT}}"
  PUBLIC_SSH_FORWARD_PORT="${PUBLIC_SSH_FORWARD_PORT:-${DEFAULT_PUBLIC_SSH_FORWARD_PORT}}"
  PEER_PUBLIC_SSH_PORT="${PEER_PUBLIC_SSH_PORT:-${DEFAULT_PEER_PUBLIC_SSH_PORT}}"
  WINGS_SCHEME="${WINGS_SCHEME:-${DEFAULT_WINGS_SCHEME}}"
  WINGS_PUBLIC_PORT="${WINGS_PUBLIC_PORT:-$(default_wings_port)}"
  WINGS_TARGET_PORT="${WINGS_TARGET_PORT:-$(default_wings_port)}"
  GAME_PORTS_RAW="${GAME_PORTS_RAW:-${DEFAULT_GAME_PORTS_RAW}}"
  WG_INTERFACE="${WG_INTERFACE:-${DEFAULT_WG_INTERFACE}}"
  WG_PORT="${WG_PORT:-${DEFAULT_WG_PORT}}"
  WG_VPS1_ADDRESS="${WG_VPS1_ADDRESS:-${DEFAULT_WG_VPS1_ADDRESS}}"
  WG_VPS2_ADDRESS="${WG_VPS2_ADDRESS:-${DEFAULT_WG_VPS2_ADDRESS}}"
  WG_PEER_ADDRESS="${WG_PEER_ADDRESS:-${DEFAULT_WG_PEER_ADDRESS}}"
  WG_WATCHDOG_STALE_SECONDS="${WG_WATCHDOG_STALE_SECONDS:-${DEFAULT_WG_WATCHDOG_STALE_SECONDS}}"
  WG_WATCHDOG_RESTART_ON_STALE="${WG_WATCHDOG_RESTART_ON_STALE:-${DEFAULT_WG_WATCHDOG_RESTART_ON_STALE}}"
}

default_wings_port() {
  if [[ "${WINGS_SCHEME:-${DEFAULT_WINGS_SCHEME}}" == "https" ]]; then
    printf '%s' "${DEFAULT_WINGS_HTTPS_PORT}"
  else
    printf '%s' "${DEFAULT_WINGS_HTTP_PORT}"
  fi
}

normalize_wings_settings() {
  apply_defaults
  validate_wings_scheme
  validate_port "${WINGS_PUBLIC_PORT}"
  validate_port "${WINGS_TARGET_PORT}"
}

validate_peer_wings_settings() {
  if [[ -z "${PEER_WINGS_PUBLIC_PORT}" && -z "${PEER_WINGS_TARGET_PORT}" ]]; then
    return 0
  fi

  [[ -n "${PEER_WINGS_PUBLIC_PORT}" ]] || fail "Missing --peer-wings-public-port for peer Wings forwarding."
  [[ -n "${PEER_WINGS_TARGET_PORT}" ]] || fail "Missing --peer-wings-target-port for peer Wings forwarding."
  validate_port "${PEER_WINGS_PUBLIC_PORT}"
  validate_port "${PEER_WINGS_TARGET_PORT}"
}

validate_wireguard_watchdog_settings() {
  apply_defaults
  [[ "${WG_WATCHDOG_STALE_SECONDS}" =~ ^[0-9]+$ ]] || fail "WireGuard watchdog stale seconds must be numeric: ${WG_WATCHDOG_STALE_SECONDS}"
  ((10#${WG_WATCHDOG_STALE_SECONDS} >= 60)) || fail "WireGuard watchdog stale seconds must be at least 60."
  validate_yes_no "${WG_WATCHDOG_RESTART_ON_STALE}" "--wg-watchdog-restart-on-stale"
}

normalize_wireguard_addresses() {
  apply_defaults
  validate_ipv4_cidr "${WG_VPS1_ADDRESS}"
  validate_ipv4_cidr "${WG_VPS2_ADDRESS}"
  validate_ipv4_cidr "${WG_PEER_ADDRESS}"

  WG_VPS1_IP="${WG_VPS1_ADDRESS%%/*}"
  WG_VPS2_IP="${WG_VPS2_ADDRESS%%/*}"
  WG_PEER_IP="${WG_PEER_ADDRESS%%/*}"
  VPS2_HOST="${WG_VPS2_IP}"

  [[ "${WG_VPS1_IP}" != "${WG_VPS2_IP}" ]] || fail "VPS1 and VPS2 WireGuard IPs must be different."
  [[ "${WG_VPS1_IP}" != "${WG_PEER_IP}" ]] || fail "VPS1 and peer WireGuard IPs must be different."
}

validate_peer_name() {
  [[ -n "${PEER_NAME}" ]] || fail "Missing peer name. Use --peer-name vps3"
  [[ "${PEER_NAME}" =~ ^[A-Za-z0-9_-]+$ ]] || fail "Peer name can only contain letters, numbers, underscore, and dash."
}

find_local_ip_conflict_interface() {
  local target_ip="$1"
  local interface_name=""
  local address_cidr=""
  local current_ip=""

  command -v ip >/dev/null 2>&1 || return 1

  while read -r interface_name address_cidr; do
    [[ -n "${interface_name}" && -n "${address_cidr}" ]] || continue
    current_ip="${address_cidr%%/*}"
    [[ "${current_ip}" == "${target_ip}" ]] || continue

    if [[ "${interface_name}" != "${WG_INTERFACE}" ]]; then
      printf '%s\n' "${interface_name}"
      return 0
    fi
  done < <(ip -o -4 addr show | awk '{print $2, $4}')

  return 1
}

ensure_local_wireguard_ip_available() {
  local target_ip="$1"
  local conflict_interface=""

  conflict_interface="$(find_local_ip_conflict_interface "${target_ip}" || true)"
  if [[ -n "${conflict_interface}" ]]; then
    fail "WireGuard IP ${target_ip} is already assigned to interface ${conflict_interface} on this server. Pick a different subnet, for example --wg-vps1-address 172.31.250.1/30 --wg-vps2-address 172.31.250.2/30."
  fi
}

validate_identity_file_if_present() {
  if [[ -n "${IDENTITY_FILE}" && ! -f "${IDENTITY_FILE}" ]]; then
    fail "Identity file not found: ${IDENTITY_FILE}"
  fi
}

ensure_supported_linux() {
  [[ -f /etc/os-release ]] || fail "/etc/os-release not found."

  # shellcheck disable=SC1091
  . /etc/os-release

  case "${ID}" in
    ubuntu)
      case "${VERSION_ID}" in
        22.04|24.04) ;;
        *) fail "Unsupported Ubuntu version: ${VERSION_ID}. Use 22.04 or 24.04." ;;
      esac
      ;;
    debian)
      case "${VERSION_ID}" in
        12|13) ;;
        *) fail "Unsupported Debian version: ${VERSION_ID}. Use 12 or 13." ;;
      esac
      ;;
    *)
      fail "Unsupported distro: ${ID}. Use Ubuntu 22.04/24.04 or Debian 12/13."
      ;;
  esac
}

ensure_systemd() {
  command -v systemctl >/dev/null 2>&1 || fail "systemd is required on this machine."
}

ensure_ssh_client() {
  command -v ssh >/dev/null 2>&1 || fail "OpenSSH client not found. Install ssh first."
}

local_has_ipv4() {
  local target_ip="$1"

  if command -v ip >/dev/null 2>&1; then
    ip -o -4 addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "${target_ip}"
    return
  fi

  if command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | tr ' ' '\n' | grep -Fxq "${target_ip}"
    return
  fi

  return 1
}

ensure_socat_installed() {
  if command -v socat >/dev/null 2>&1; then
    return 0
  fi

  info "Installing socat with apt..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y socat
  command -v socat >/dev/null 2>&1 || fail "socat installation failed."
}

ensure_iptables_installed() {
  if command -v iptables >/dev/null 2>&1; then
    return 0
  fi

  info "Installing iptables with apt..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y iptables
  command -v iptables >/dev/null 2>&1 || fail "iptables installation failed."
}

ensure_wireguard_installed() {
  if command -v wg >/dev/null 2>&1 && command -v wg-quick >/dev/null 2>&1; then
    return 0
  fi

  info "Installing WireGuard with apt..."
  apt-get update

  if ! DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard wireguard-tools; then
    warn "Full WireGuard package install failed, trying wireguard-tools only."
    DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard-tools
  fi

  command -v wg >/dev/null 2>&1 || fail "WireGuard installation failed: wg not found."
  command -v wg-quick >/dev/null 2>&1 || fail "WireGuard installation failed: wg-quick not found."
}

wireguard_state_dir() {
  printf '/etc/cakessh/wireguard'
}

wireguard_config_path() {
  printf '/etc/wireguard/%s.conf' "${WG_INTERFACE}"
}

wireguard_service_name() {
  printf 'wg-quick@%s.service' "${WG_INTERFACE}"
}

wireguard_watchdog_config_path() {
  printf '/etc/cakessh/watchdog.env'
}

wireguard_watchdog_script_path() {
  printf '/usr/local/lib/cakessh/cakessh-wg-watchdog'
}

wireguard_watchdog_service_name() {
  printf 'cakessh-wg-watchdog.service'
}

wireguard_watchdog_timer_name() {
  printf 'cakessh-wg-watchdog.timer'
}

wireguard_private_key_path() {
  local node_role="$1"
  printf '%s/%s.privatekey' "$(wireguard_state_dir)" "${node_role}"
}

wireguard_public_key_path() {
  local node_role="$1"
  printf '%s/%s.publickey' "$(wireguard_state_dir)" "${node_role}"
}

install_state_path() {
  printf '/etc/cakessh/install.env'
}

ssh_peer_state_dir() {
  printf '/etc/cakessh/ssh-peers'
}

ssh_peer_state_path() {
  local peer_name="$1"
  printf '%s/%s.env' "$(ssh_peer_state_dir)" "${peer_name}"
}

forwarder_service_name() {
  printf 'cakessh-forward.service'
}

forwarder_config_path() {
  printf '/etc/cakessh/forwarder.env'
}

generate_local_wireguard_keys() {
  local node_role="$1"
  local state_dir
  local private_key_file
  local public_key_file

  state_dir="$(wireguard_state_dir)"
  private_key_file="$(wireguard_private_key_path "${node_role}")"
  public_key_file="$(wireguard_public_key_path "${node_role}")"

  mkdir -p "${state_dir}" /etc/wireguard
  chmod 0700 "${state_dir}"

  if [[ ! -f "${private_key_file}" || ! -f "${public_key_file}" ]]; then
    umask 077
    wg genkey | tee "${private_key_file}" | wg pubkey > "${public_key_file}"
  fi

  chmod 0600 "${private_key_file}" "${public_key_file}"
  LOCAL_WG_PRIVATE_KEY="$(<"${private_key_file}")"
  LOCAL_WG_PUBLIC_KEY="$(<"${public_key_file}")"
}

write_vps1_wireguard_config() {
  local config_path
  config_path="$(wireguard_config_path)"

  umask 077
  {
    printf '[Interface]\n'
    printf 'Address = %s\n' "${WG_VPS1_ADDRESS}"
    printf 'ListenPort = %s\n' "${WG_PORT}"
    printf 'PrivateKey = %s\n' "${LOCAL_WG_PRIVATE_KEY}"

    if [[ -n "${WG_VPS2_PUBLIC_KEY}" ]]; then
      printf '\n[Peer]\n'
      printf 'PublicKey = %s\n' "${WG_VPS2_PUBLIC_KEY}"
      printf 'AllowedIPs = %s/32\n' "${WG_VPS2_IP}"
    fi

    print_extra_wireguard_peer_blocks
  } > "${config_path}"

  chmod 0600 "${config_path}"
}

write_vps2_wireguard_config() {
  local config_path
  config_path="$(wireguard_config_path)"

  umask 077
  {
    printf '[Interface]\n'
    printf 'Address = %s\n' "${WG_VPS2_ADDRESS}"
    printf 'PrivateKey = %s\n' "${LOCAL_WG_PRIVATE_KEY}"
    printf '\n[Peer]\n'
    printf 'PublicKey = %s\n' "${WG_VPS1_PUBLIC_KEY}"
    printf 'AllowedIPs = %s/32\n' "${WG_VPS1_IP}"
    printf 'Endpoint = %s:%s\n' "${VPS1_IPV4}" "${WG_PORT}"
    printf 'PersistentKeepalive = 25\n'
  } > "${config_path}"

  chmod 0600 "${config_path}"
}

write_peer_wireguard_config() {
  local config_path
  config_path="$(wireguard_config_path)"

  umask 077
  {
    printf '[Interface]\n'
    printf 'Address = %s\n' "${WG_PEER_ADDRESS}"
    printf 'PrivateKey = %s\n' "${LOCAL_WG_PRIVATE_KEY}"
    printf '\n[Peer]\n'
    printf 'PublicKey = %s\n' "${WG_VPS1_PUBLIC_KEY}"
    printf 'AllowedIPs = %s/32\n' "${WG_VPS1_IP}"
    printf 'Endpoint = %s:%s\n' "${VPS1_IPV4}" "${WG_PORT}"
    printf 'PersistentKeepalive = 25\n'
  } > "${config_path}"

  chmod 0600 "${config_path}"
}

print_extra_wireguard_peer_blocks() {
  local peer_file=""
  local SSH_PEER_NAME=""
  local SSH_PEER_WG_IP=""
  local SSH_PEER_PUBLIC_KEY=""

  [[ -d "$(ssh_peer_state_dir)" ]] || return 0

  for peer_file in "$(ssh_peer_state_dir)"/*.env; do
    [[ -f "${peer_file}" ]] || continue
    SSH_PEER_NAME=""
    SSH_PEER_WG_IP=""
    SSH_PEER_PUBLIC_KEY=""
    # shellcheck disable=SC1090
    . "${peer_file}"
    [[ -n "${SSH_PEER_WG_IP}" && -n "${SSH_PEER_PUBLIC_KEY}" ]] || continue
    printf '\n[Peer]\n'
    printf '# %s\n' "${SSH_PEER_NAME:-extra-peer}"
    printf 'PublicKey = %s\n' "${SSH_PEER_PUBLIC_KEY}"
    printf 'AllowedIPs = %s/32\n' "${SSH_PEER_WG_IP}"
  done
}

upsert_wireguard_service() {
  local service_name
  service_name="$(wireguard_service_name)"

  systemctl enable --now "${service_name}"
  systemctl restart "${service_name}"
  systemctl is-active --quiet "${service_name}" || fail "WireGuard service failed to start: ${service_name}"
}

write_wireguard_watchdog_script() {
  mkdir -p /usr/local/lib/cakessh

  cat > "$(wireguard_watchdog_script_path)" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

config_file="/etc/cakessh/watchdog.env"

[[ -f "${config_file}" ]] || exit 0

# shellcheck disable=SC1090
. "${config_file}"

: "${WG_INTERFACE:?WG_INTERFACE is required}"
: "${WG_PEER_PUBLIC_KEY:?WG_PEER_PUBLIC_KEY is required}"
: "${WG_MAX_STALE_SECONDS:?WG_MAX_STALE_SECONDS is required}"
WG_RESTART_ON_STALE="${WG_RESTART_ON_STALE:-no}"

WG_BIN="${WG_BIN:-$(command -v wg || true)}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-$(command -v systemctl || true)}"
DATE_BIN="${DATE_BIN:-$(command -v date || true)}"
LOGGER_BIN="${LOGGER_BIN:-$(command -v logger || true)}"

[[ -n "${WG_BIN}" ]] || exit 0
[[ -n "${SYSTEMCTL_BIN}" ]] || exit 0
[[ -n "${DATE_BIN}" ]] || exit 0

restart_reason=""
if ! "${WG_BIN}" show "${WG_INTERFACE}" >/dev/null 2>&1; then
  restart_reason="interface is down"
elif [[ "${WG_RESTART_ON_STALE}" == "yes" ]]; then
  latest_handshake="$("${WG_BIN}" show "${WG_INTERFACE}" latest-handshakes 2>/dev/null | awk -v peer_key="${WG_PEER_PUBLIC_KEY}" '$1 == peer_key { print $2; exit }')"
  [[ -n "${latest_handshake}" ]] || latest_handshake="0"

  now="$("${DATE_BIN}" +%s)"
  if [[ "${latest_handshake}" == "0" ]]; then
    restart_reason="peer has no handshake"
  elif (( now - latest_handshake > 10#${WG_MAX_STALE_SECONDS} )); then
    restart_reason="latest handshake is stale"
  fi
fi

if [[ -n "${restart_reason}" ]]; then
  if [[ -n "${LOGGER_BIN}" ]]; then
    "${LOGGER_BIN}" -t cakessh-wg-watchdog "Restarting ${WG_INTERFACE}: ${restart_reason}."
  fi
  "${SYSTEMCTL_BIN}" restart "wg-quick@${WG_INTERFACE}.service"
fi
EOF

  chmod 0755 "$(wireguard_watchdog_script_path)"
}

write_wireguard_watchdog_config() {
  local peer_public_key="$1"

  mkdir -p /etc/cakessh

  {
    printf 'WG_INTERFACE=%q\n' "${WG_INTERFACE}"
    printf 'WG_PEER_PUBLIC_KEY=%q\n' "${peer_public_key}"
    printf 'WG_MAX_STALE_SECONDS=%q\n' "${WG_WATCHDOG_STALE_SECONDS}"
    printf 'WG_RESTART_ON_STALE=%q\n' "${WG_WATCHDOG_RESTART_ON_STALE}"
  } > "$(wireguard_watchdog_config_path)"

  chmod 0600 "$(wireguard_watchdog_config_path)"
}

write_wireguard_watchdog_unit() {
  cat > "/etc/systemd/system/$(wireguard_watchdog_service_name)" <<EOF
[Unit]
Description=cakessh WireGuard watchdog
After=$(wireguard_service_name)
Wants=$(wireguard_service_name)

[Service]
Type=oneshot
ExecStart=$(wireguard_watchdog_script_path)
NoNewPrivileges=true
EOF

  cat > "/etc/systemd/system/$(wireguard_watchdog_timer_name)" <<EOF
[Unit]
Description=Run cakessh WireGuard watchdog every minute

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
AccuracySec=15s
Unit=$(wireguard_watchdog_service_name)

[Install]
WantedBy=timers.target
EOF
}

upsert_wireguard_watchdog() {
  systemctl daemon-reload
  systemctl enable --now "$(wireguard_watchdog_timer_name)"
  systemctl restart "$(wireguard_watchdog_timer_name)"
  systemctl is-active --quiet "$(wireguard_watchdog_timer_name)" || fail "WireGuard watchdog timer failed to start: $(wireguard_watchdog_timer_name)"
}

remove_wireguard_watchdog() {
  systemctl disable --now "$(wireguard_watchdog_timer_name)" >/dev/null 2>&1 || true
  systemctl disable --now "$(wireguard_watchdog_service_name)" >/dev/null 2>&1 || true
  rm -f -- "/etc/systemd/system/$(wireguard_watchdog_service_name)"
  rm -f -- "/etc/systemd/system/$(wireguard_watchdog_timer_name)"
  rm -f -- "$(wireguard_watchdog_config_path)"
  rm -f -- "$(wireguard_watchdog_script_path)"
}

remove_wireguard() {
  local service_name

  apply_defaults
  service_name="$(wireguard_service_name)"

  remove_wireguard_watchdog
  systemctl disable --now "${service_name}" >/dev/null 2>&1 || true
  rm -f -- "$(wireguard_config_path)"
  rm -f -- "$(wireguard_private_key_path "vps1")"
  rm -f -- "$(wireguard_public_key_path "vps1")"
  rm -f -- "$(wireguard_private_key_path "vps2")"
  rm -f -- "$(wireguard_public_key_path "vps2")"
  rm -f -- "$(wireguard_private_key_path "peer")"
  rm -f -- "$(wireguard_public_key_path "peer")"
  rm -f -- "$(install_state_path)"
  rmdir "$(wireguard_state_dir)" 2>/dev/null || true
}

load_install_state() {
  local state_path=""

  state_path="$(install_state_path)"
  [[ -r "${state_path}" ]] || return 0

  # shellcheck disable=SC1090
  . "${state_path}"

  VPS1_IPV4="${VPS1_IPV4:-${STATE_VPS1_IPV4:-}}"
  VPS1_USER="${VPS1_USER:-${STATE_VPS1_USER:-}}"
  VPS1_SSH_PORT="${VPS1_SSH_PORT:-${STATE_VPS1_SSH_PORT:-}}"
  VPS2_USER="${VPS2_USER:-${STATE_VPS2_USER:-}}"
  VPS2_SSH_PORT="${VPS2_SSH_PORT:-${STATE_VPS2_SSH_PORT:-}}"
  PUBLIC_SSH_FORWARD_PORT="${PUBLIC_SSH_FORWARD_PORT:-${STATE_PUBLIC_SSH_FORWARD_PORT:-}}"
  WINGS_SCHEME="${WINGS_SCHEME:-${STATE_WINGS_SCHEME:-}}"
  WINGS_PUBLIC_PORT="${WINGS_PUBLIC_PORT:-${STATE_WINGS_PUBLIC_PORT:-}}"
  WINGS_TARGET_PORT="${WINGS_TARGET_PORT:-${STATE_WINGS_TARGET_PORT:-}}"
  GAME_PORTS_RAW="${GAME_PORTS_RAW:-${STATE_GAME_PORTS_RAW:-}}"
  WG_INTERFACE="${WG_INTERFACE:-${STATE_WG_INTERFACE:-}}"
  WG_PORT="${WG_PORT:-${STATE_WG_PORT:-}}"
  WG_VPS1_ADDRESS="${WG_VPS1_ADDRESS:-${STATE_WG_VPS1_ADDRESS:-}}"
  WG_VPS2_ADDRESS="${WG_VPS2_ADDRESS:-${STATE_WG_VPS2_ADDRESS:-}}"
  WG_VPS1_PUBLIC_KEY="${WG_VPS1_PUBLIC_KEY:-${STATE_WG_VPS1_PUBLIC_KEY:-}}"
  WG_VPS2_PUBLIC_KEY="${WG_VPS2_PUBLIC_KEY:-${STATE_WG_VPS2_PUBLIC_KEY:-}}"
  WG_WATCHDOG_STALE_SECONDS="${WG_WATCHDOG_STALE_SECONDS:-${STATE_WG_WATCHDOG_STALE_SECONDS:-}}"
  WG_WATCHDOG_RESTART_ON_STALE="${WG_WATCHDOG_RESTART_ON_STALE:-${STATE_WG_WATCHDOG_RESTART_ON_STALE:-}}"
}

save_install_state() {
  local state_path=""

  state_path="$(install_state_path)"
  mkdir -p /etc/cakessh

  {
    printf 'STATE_VPS1_IPV4=%q\n' "${VPS1_IPV4}"
    printf 'STATE_VPS1_USER=%q\n' "${VPS1_USER}"
    printf 'STATE_VPS1_SSH_PORT=%q\n' "${VPS1_SSH_PORT}"
    printf 'STATE_VPS2_USER=%q\n' "${VPS2_USER}"
    printf 'STATE_VPS2_SSH_PORT=%q\n' "${VPS2_SSH_PORT}"
    printf 'STATE_PUBLIC_SSH_FORWARD_PORT=%q\n' "${PUBLIC_SSH_FORWARD_PORT}"
    printf 'STATE_WINGS_SCHEME=%q\n' "${WINGS_SCHEME}"
    printf 'STATE_WINGS_PUBLIC_PORT=%q\n' "${WINGS_PUBLIC_PORT}"
    printf 'STATE_WINGS_TARGET_PORT=%q\n' "${WINGS_TARGET_PORT}"
    printf 'STATE_GAME_PORTS_RAW=%q\n' "${GAME_PORTS_RAW}"
    printf 'STATE_WG_INTERFACE=%q\n' "${WG_INTERFACE}"
    printf 'STATE_WG_PORT=%q\n' "${WG_PORT}"
    printf 'STATE_WG_VPS1_ADDRESS=%q\n' "${WG_VPS1_ADDRESS}"
    printf 'STATE_WG_VPS2_ADDRESS=%q\n' "${WG_VPS2_ADDRESS}"
    printf 'STATE_WG_VPS1_PUBLIC_KEY=%q\n' "${WG_VPS1_PUBLIC_KEY}"
    printf 'STATE_WG_VPS2_PUBLIC_KEY=%q\n' "${WG_VPS2_PUBLIC_KEY}"
    printf 'STATE_WG_WATCHDOG_STALE_SECONDS=%q\n' "${WG_WATCHDOG_STALE_SECONDS}"
    printf 'STATE_WG_WATCHDOG_RESTART_ON_STALE=%q\n' "${WG_WATCHDOG_RESTART_ON_STALE}"
  } > "${state_path}"

  chmod 0600 "${state_path}"
}

save_ssh_peer_state() {
  local state_path=""

  validate_peer_name
  state_path="$(ssh_peer_state_path "${PEER_NAME}")"
  mkdir -p "$(ssh_peer_state_dir)"

  {
    printf 'SSH_PEER_NAME=%q\n' "${PEER_NAME}"
    printf 'SSH_PEER_USER=%q\n' "${PEER_USER}"
    printf 'SSH_PEER_SSH_PORT=%q\n' "${PEER_SSH_PORT}"
    printf 'SSH_PEER_PUBLIC_SSH_PORT=%q\n' "${PEER_PUBLIC_SSH_PORT}"
    printf 'SSH_PEER_WINGS_PUBLIC_PORT=%q\n' "${PEER_WINGS_PUBLIC_PORT}"
    printf 'SSH_PEER_WINGS_TARGET_PORT=%q\n' "${PEER_WINGS_TARGET_PORT}"
    printf 'SSH_PEER_WG_ADDRESS=%q\n' "${WG_PEER_ADDRESS}"
    printf 'SSH_PEER_WG_IP=%q\n' "${WG_PEER_IP}"
    printf 'SSH_PEER_PUBLIC_KEY=%q\n' "${WG_PEER_PUBLIC_KEY}"
  } > "${state_path}"

  chmod 0600 "${state_path}"
}

wireguard_peer_has_handshake() {
  command -v wg >/dev/null 2>&1 || return 1
  [[ -n "${WG_VPS2_PUBLIC_KEY}" ]] || return 1

  wg show "${WG_INTERFACE}" latest-handshakes 2>/dev/null \
    | awk -v peer_key="${WG_VPS2_PUBLIC_KEY}" '$1 == peer_key && $2 > 0 { found=1 } END { exit found ? 0 : 1 }'
}

ensure_wireguard_backend_reachability() {
  local ping_ok="no"
  local attempt=0
  local max_attempts=30

  VPS2_SSH_REACHABLE="unknown"
  info "Waiting for WireGuard reachability to ${WG_VPS2_IP}..."
  info "This can take around 25 seconds after VPS1 adds the peer."
  info "If this keeps waiting, run this on VPS2 in another terminal:"
  info "  ping -c 2 ${WG_VPS1_IP}"

  while ((attempt < max_attempts)); do
    ping_ok="no"

    if command -v ping >/dev/null 2>&1; then
      if ping -c 1 -W 2 "${WG_VPS2_IP}" >/dev/null 2>&1; then
        ping_ok="yes"
      fi
    fi

    if command -v nc >/dev/null 2>&1; then
      if nc -z -w 2 "${WG_VPS2_IP}" "${VPS2_SSH_PORT}" >/dev/null 2>&1; then
        VPS2_SSH_REACHABLE="yes"
        return 0
      fi

      if [[ "${ping_ok}" == "yes" ]]; then
        VPS2_SSH_REACHABLE="no"
        warn "WireGuard is up, but VPS2 SSH port ${VPS2_SSH_PORT} is unreachable at ${WG_VPS2_IP}. Continuing with VPS1 setup, but direct SSH will not work until sshd is running on VPS2 and port ${VPS2_SSH_PORT} is open there."
        return 0
      fi
    elif [[ "${ping_ok}" == "yes" ]]; then
      VPS2_SSH_REACHABLE="unknown"
      return 0
    fi

    if wireguard_peer_has_handshake; then
      VPS2_SSH_REACHABLE="unknown"
      warn "Detected a WireGuard handshake with VPS2, so continuing with VPS1 setup. If direct SSH still fails later, test: nc -vz ${WG_VPS2_IP} ${VPS2_SSH_PORT}"
      return 0
    fi

    attempt=$((attempt + 1))
    ((attempt < max_attempts)) || break
    info "  WireGuard not ready yet (${attempt}/${max_attempts}). Retrying in 2 seconds..."
    sleep 2
  done

  fail "VPS1 cannot reach ${WG_VPS2_IP} over WireGuard yet. Make sure VPS2 finished install, UDP ${WG_PORT}/udp is open on VPS1, and both sides show a handshake with: sudo wg show"
}

port_is_in_use() {
  local port="$1"
  ss -Hltn "( sport = :${port} )" 2>/dev/null | grep -q .
}

describe_port_usage() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -ltnp "( sport = :${port} )" 2>/dev/null || true
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true
  fi
}

ensure_port_is_free() {
  local port="$1"
  if port_is_in_use "${port}"; then
    printf 'Detected TCP listener on VPS1 for port %s:\n' "${port}" >&2
    describe_port_usage "${port}" >&2 || true
    fail "Port ${port} is already in use on VPS1."
  fi
}

calc_wings_port() {
  apply_defaults
  printf '%s' "${WINGS_PUBLIC_PORT}"
}

join_by_comma() {
  local first="yes"
  local item=""

  for item in "$@"; do
    if [[ "${first}" == "yes" ]]; then
      printf '%s' "${item}"
      first="no"
    else
      printf ',%s' "${item}"
    fi
  done
}

write_client_config() {
  local config_file="$1"
  local wings_port="$2"
  local game_ports_csv="$3"

  mkdir -p "$(dirname "${config_file}")"

  {
    printf 'CAKESSH_VPS1_IPV4=%q\n' "${VPS1_IPV4}"
    printf 'CAKESSH_VPS1_USER=%q\n' "${VPS1_USER}"
    printf 'CAKESSH_VPS1_SSH_PORT=%q\n' "${VPS1_SSH_PORT}"
    printf 'CAKESSH_VPS2_HOST=%q\n' "${VPS2_HOST}"
    printf 'CAKESSH_VPS2_USER=%q\n' "${VPS2_USER}"
    printf 'CAKESSH_VPS2_SSH_PORT=%q\n' "${VPS2_SSH_PORT}"
    printf 'CAKESSH_IDENTITY_FILE=%q\n' "${IDENTITY_FILE}"
    printf 'CAKESSH_PUBLIC_SSH_FORWARD_PORT=%q\n' "${PUBLIC_SSH_FORWARD_PORT}"
    printf 'CAKESSH_WINGS_PUBLIC_PORT=%q\n' "${wings_port}"
    printf 'CAKESSH_GAME_PORTS=%q\n' "${game_ports_csv}"
    printf 'CAKESSH_WG_INTERFACE=%q\n' "${WG_INTERFACE}"
  } > "${config_file}"
}

client_ssh_dir() {
  printf '%s/.ssh' "${CLIENT_INSTALL_HOME}"
}

client_ssh_config_path() {
  printf '%s/config' "$(client_ssh_dir)"
}

client_ssh_config_dropin_dir() {
  printf '%s/config.d' "$(client_ssh_dir)"
}

client_ssh_config_dropin_path() {
  printf '%s/cakessh.conf' "$(client_ssh_config_dropin_dir)"
}

ensure_client_ssh_include() {
  local ssh_dir
  local main_config

  ssh_dir="$(client_ssh_dir)"
  main_config="$(client_ssh_config_path)"

  mkdir -p "${ssh_dir}" "$(client_ssh_config_dropin_dir)"
  chmod 0700 "${ssh_dir}"
  touch "${main_config}"
  chmod 0600 "${main_config}"

  if ! grep -Fqx 'Include ~/.ssh/config.d/*.conf' "${main_config}" 2>/dev/null; then
    printf '\nInclude ~/.ssh/config.d/*.conf\n' >> "${main_config}"
  fi
}

write_client_ssh_alias_config() {
  local alias_config

  alias_config="$(client_ssh_config_dropin_path)"
  mkdir -p "$(dirname "${alias_config}")"

  {
    printf 'Host cakessh-vps2\n'
    printf '  HostName %s\n' "${WG_VPS2_IP}"
    printf '  User %s\n' "${VPS2_USER}"
    printf '  Port %s\n' "${VPS2_SSH_PORT}"
    if ! local_has_ipv4 "${VPS1_IPV4}"; then
      printf '  ProxyJump %s@%s:%s\n' "${VPS1_USER}" "${VPS1_IPV4}" "${VPS1_SSH_PORT}"
    fi
    if [[ -n "${IDENTITY_FILE}" ]]; then
      printf '  IdentityFile %s\n' "${IDENTITY_FILE}"
    fi
    printf '\n'
    printf 'Host cakessh-vps2-port\n'
    printf '  HostName %s\n' "${VPS1_IPV4}"
    printf '  User %s\n' "${VPS2_USER}"
    printf '  Port %s\n' "${PUBLIC_SSH_FORWARD_PORT}"
    if [[ -n "${IDENTITY_FILE}" ]]; then
      printf '  IdentityFile %s\n' "${IDENTITY_FILE}"
    fi
  } > "${alias_config}"

  chmod 0600 "${alias_config}"
}

install_client() {
  local bin_dir
  local config_dir
  local helper_target
  local config_target
  local wings_port
  local game_ports_csv

  progress 1 4 "Preparing client install"
  [[ -f "${HELPER_SOURCE}" ]] || fail "Helper script not found: ${HELPER_SOURCE}"
  ensure_ssh_client
  determine_client_home
  validate_identity_file_if_present
  normalize_wireguard_addresses

  bin_dir="${CLIENT_INSTALL_HOME}/.local/bin"
  config_dir="${CLIENT_INSTALL_HOME}/.config/cakessh"
  helper_target="${bin_dir}/cakessh"
  config_target="${config_dir}/client.env"
  wings_port="$(calc_wings_port)"
  game_ports_csv="$(join_by_comma "${GAME_PORT_LIST[@]}")"

  progress 2 4 "Installing cakessh helper and writing config"
  mkdir -p "${bin_dir}" "${config_dir}"
  install -m 0755 "${HELPER_SOURCE}" "${helper_target}"
  write_client_config "${config_target}" "${wings_port}" "${game_ports_csv}"

  progress 3 4 "Creating SSH aliases"
  ensure_client_ssh_include
  write_client_ssh_alias_config

  if [[ "${EUID}" -eq 0 && "${CLIENT_INSTALL_USER}" != "root" ]]; then
    chown "${CLIENT_INSTALL_USER}" \
      "${CLIENT_INSTALL_HOME}/.local" \
      "${bin_dir}" \
      "${CLIENT_INSTALL_HOME}/.config" \
      "${config_dir}" \
      "$(client_ssh_dir)" \
      "$(client_ssh_config_dropin_dir)" \
      "$(client_ssh_config_path)" \
      "$(client_ssh_config_dropin_path)" \
      "${helper_target}" \
      "${config_target}"
  fi

  progress 4 4 "Client install finished"
  info ""
  info "Client install complete."
  info "Helper: ${helper_target}"
  info "Config:  ${config_target}"
  info "WireGuard target host for VPS2: ${VPS2_HOST}"
  info "SSH aliases:"
  info "  ssh cakessh-vps2"
  info "  ssh cakessh-vps2-port"
  info ""
  info "Commands:"
  info "  cakessh connect"
  info "  cakessh direct"
  if [[ -n "${IDENTITY_FILE}" ]]; then
    info "  cakessh connect -i ${IDENTITY_FILE}"
  fi
  info "  cakessh status"

  case ":${PATH}:" in
    *":${bin_dir}:"*) ;;
    *)
      warn "${bin_dir} is not in PATH for the current shell."
      info "Add it with:"
      info "  export PATH=\"${bin_dir}:\$PATH\""
      ;;
  esac
}

add_relay() {
  local name="$1"
  local listen_port="$2"
  local target_port="$3"
  local description="$4"

  validate_port "${listen_port}"
  validate_port "${target_port}"

  if array_contains "${listen_port}" "${RELAY_LISTEN_PORTS[@]:-}"; then
    fail "Duplicate public listen port requested: ${listen_port}"
  fi

  RELAY_NAMES+=("${name}")
  RELAY_LISTEN_PORTS+=("${listen_port}")
  RELAY_TARGET_PORTS+=("${target_port}")
  RELAY_DESCRIPTIONS+=("${description}")
}

validate_port_spec() {
  local port_spec="$1"
  local range_start=""
  local range_end=""

  if [[ "${port_spec}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    range_start="${BASH_REMATCH[1]}"
    range_end="${BASH_REMATCH[2]}"
    validate_port "${range_start}"
    validate_port "${range_end}"
    ((range_start <= range_end)) || fail "Invalid port range: ${port_spec}"
    return 0
  fi

  validate_port "${port_spec}"
}

expand_port_spec() {
  local port_spec="$1"
  local current_port=""
  local range_start=""
  local range_end=""

  if [[ "${port_spec}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    range_start="${BASH_REMATCH[1]}"
    range_end="${BASH_REMATCH[2]}"
    current_port="${range_start}"
    while ((current_port <= range_end)); do
      printf '%s\n' "${current_port}"
      ((current_port++))
    done
    return 0
  fi

  printf '%s\n' "${port_spec}"
}

iptables_port_spec() {
  local port_spec="$1"
  printf '%s' "${port_spec//-/:}"
}

add_forward_rule() {
  add_forward_rule_to_host "${WG_VPS2_IP}" "$@"
}

add_forward_rule_to_host() {
  local target_host="$1"
  shift
  local name="$1"
  local listen_spec="$2"
  local target_spec="$3"
  local description="$4"
  local port_check=""

  validate_port_spec "${listen_spec}"
  validate_port_spec "${target_spec}"

  if [[ "${listen_spec}" == *-* ]] && [[ "${target_spec}" != "${listen_spec}" ]]; then
    fail "Port range forwarding must use the same listen and target range: ${listen_spec} -> ${target_spec}"
  fi

  while IFS= read -r port_check; do
    [[ -n "${port_check}" ]] || continue
    if array_contains "${port_check}" "${FORWARD_LISTEN_PORT_CHECKS[@]:-}"; then
      fail "Duplicate public listen port requested: ${port_check}"
    fi
    FORWARD_LISTEN_PORT_CHECKS+=("${port_check}")
  done < <(expand_port_spec "${listen_spec}")

  FORWARD_RULE_NAMES+=("${name}")
  FORWARD_RULE_LISTEN_SPECS+=("${listen_spec}")
  FORWARD_RULE_TARGET_HOSTS+=("${target_host}")
  FORWARD_RULE_TARGET_SPECS+=("${target_spec}")
  FORWARD_RULE_DESCRIPTIONS+=("${description}")
}

stop_existing_relays() {
  disable_relay_instances "Stopping existing relay batch" "no"
}

remove_relay_symlinks() {
  find /etc/systemd/system -maxdepth 3 -type l -name 'cakessh-relay@*.service' -delete 2>/dev/null || true
}

collect_relay_instances() {
  local output_file="$1"
  local env_path=""
  local symlink_path=""
  local instance_name=""

  : > "${output_file}"

  if [[ -f /etc/cakessh/instances.list ]]; then
    while IFS= read -r instance_name; do
      [[ -n "${instance_name}" ]] || continue
      printf '%s\n' "${instance_name}" >> "${output_file}"
    done < /etc/cakessh/instances.list
  fi

  if [[ -d /etc/cakessh/relays ]]; then
    for env_path in /etc/cakessh/relays/*.env; do
      [[ -e "${env_path}" ]] || break
      instance_name="${env_path##*/}"
      instance_name="${instance_name%.env}"
      printf '%s\n' "${instance_name}" >> "${output_file}"
    done
  fi

  while IFS= read -r symlink_path; do
    [[ -n "${symlink_path}" ]] || continue
    instance_name="${symlink_path##*/}"
    instance_name="${instance_name#cakessh-relay@}"
    instance_name="${instance_name%.service}"
    printf '%s\n' "${instance_name}" >> "${output_file}"
  done < <(find /etc/systemd/system -maxdepth 3 -type l -name 'cakessh-relay@*.service' 2>/dev/null || true)

  sort -u -o "${output_file}" "${output_file}" 2>/dev/null || true
}

disable_relay_instances() {
  local progress_label="$1"
  local remove_env_files="${2:-no}"
  local relay_file=""
  local instance_name=""
  local batch_start=0
  local batch_size=25
  local current=0
  local total=0
  local -a relay_units=()

  relay_file="$(mktemp)"
  collect_relay_instances "${relay_file}"
  total="$(awk 'NF { count++ } END { print count + 0 }' "${relay_file}")"

  if (( total == 0 )); then
    rm -f -- "${relay_file}"
    remove_relay_symlinks
    info "No cakessh relay services found."
    return 0
  fi

  info "Found ${total} cakessh relay service(s)."

  while IFS= read -r instance_name; do
    [[ -n "${instance_name}" ]] || continue
    relay_units+=("cakessh-relay@${instance_name}.service")
    current=$((current + 1))

    if [[ "${remove_env_files}" == "yes" ]]; then
      rm -f -- "/etc/cakessh/relays/${instance_name}.env"
    fi

    if (( ${#relay_units[@]} >= batch_size || current == total )); then
      batch_start=$((current - ${#relay_units[@]} + 1))
      info "  ${progress_label} ${batch_start}-${current}/${total}"
      systemctl disable --now "${relay_units[@]}" >/dev/null 2>&1 || true
      relay_units=()
    fi
  done < "${relay_file}"

  rm -f -- "${relay_file}"
  remove_relay_symlinks
}

build_socat_target_address() {
  local target_port="$1"
  printf 'TCP4:%s:%s' "${WG_VPS2_IP}" "${target_port}"
}

write_forwarder_runner() {
  mkdir -p /usr/local/lib/cakessh

  cat > /usr/local/lib/cakessh/cakessh-forwarder <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

action="${1:-up}"
config_file="/etc/cakessh/forwarder.env"

[[ -f "${config_file}" ]] || {
  printf 'Missing forwarder config: %s\n' "${config_file}" >&2
  exit 1
}

# shellcheck disable=SC1090
. "${config_file}"

: "${VPS1_IPV4:?VPS1_IPV4 is required}"
: "${WG_INTERFACE:?WG_INTERFACE is required}"
: "${WG_VPS2_IP:?WG_VPS2_IP is required}"
: "${FORWARD_RULE_COUNT:?FORWARD_RULE_COUNT is required}"

IPTABLES_BIN="${IPTABLES_BIN:-$(command -v iptables || true)}"
SYSCTL_BIN="${SYSCTL_BIN:-$(command -v sysctl || true)}"
[[ -n "${IPTABLES_BIN}" ]] || {
  printf 'iptables not found on PATH.\n' >&2
  exit 1
}
[[ -n "${SYSCTL_BIN}" ]] || {
  printf 'sysctl not found on PATH.\n' >&2
  exit 1
}

to_iptables_spec() {
  local port_spec="$1"
  printf '%s' "${port_spec//-/:}"
}

ensure_chain() {
  local table="$1"
  local chain="$2"

  "${IPTABLES_BIN}" -t "${table}" -F "${chain}" 2>/dev/null || "${IPTABLES_BIN}" -t "${table}" -N "${chain}"
}

delete_chain_if_exists() {
  local table="$1"
  local chain="$2"

  "${IPTABLES_BIN}" -t "${table}" -F "${chain}" 2>/dev/null || true
  "${IPTABLES_BIN}" -t "${table}" -X "${chain}" 2>/dev/null || true
}

ensure_jump() {
  local table="$1"
  local parent_chain="$2"
  local child_chain="$3"

  if ! "${IPTABLES_BIN}" -t "${table}" -C "${parent_chain}" -j "${child_chain}" >/dev/null 2>&1; then
    "${IPTABLES_BIN}" -t "${table}" -I "${parent_chain}" 1 -j "${child_chain}"
  fi
}

delete_jump_if_exists() {
  local table="$1"
  local parent_chain="$2"
  local child_chain="$3"

  while "${IPTABLES_BIN}" -t "${table}" -C "${parent_chain}" -j "${child_chain}" >/dev/null 2>&1; do
    "${IPTABLES_BIN}" -t "${table}" -D "${parent_chain}" -j "${child_chain}" >/dev/null 2>&1 || true
  done
}

remove_rules() {
  delete_jump_if_exists filter FORWARD CAKESSH_FORWARD
  delete_jump_if_exists nat POSTROUTING CAKESSH_SNAT
  delete_jump_if_exists nat OUTPUT CAKESSH_DNAT
  delete_jump_if_exists nat PREROUTING CAKESSH_DNAT
  delete_chain_if_exists filter CAKESSH_FORWARD
  delete_chain_if_exists nat CAKESSH_SNAT
  delete_chain_if_exists nat CAKESSH_DNAT
}

install_rules() {
  local index=""
  local rule_var=""
  local rule_value=""
  local name=""
  local listen_spec=""
  local target_host=""
  local target_spec=""
  local description=""
  local maybe_description=""
  local listen_iptables_spec=""
  local target_iptables_spec=""
  local target_destination=""

  "${SYSCTL_BIN}" -w net.ipv4.ip_forward=1 >/dev/null

  ensure_chain nat CAKESSH_DNAT
  ensure_chain nat CAKESSH_SNAT
  ensure_chain filter CAKESSH_FORWARD

  "${IPTABLES_BIN}" -t filter -A CAKESSH_FORWARD -i "${WG_INTERFACE}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  for ((index = 1; index <= FORWARD_RULE_COUNT; index++)); do
    rule_var="FORWARD_RULE_${index}"
    rule_value="${!rule_var:-}"
    [[ -n "${rule_value}" ]] || continue

    IFS='|' read -r name listen_spec target_host target_spec description maybe_description <<< "${rule_value}"
    if [[ -z "${description}" ]]; then
      description="${target_spec}"
      target_spec="${target_host}"
      target_host="${WG_VPS2_IP}"
    fi

    listen_iptables_spec="$(to_iptables_spec "${listen_spec}")"
    target_iptables_spec="$(to_iptables_spec "${target_spec}")"

    if [[ "${target_spec}" == *-* ]]; then
      target_destination="${target_host}"
    else
      target_destination="${target_host}:${target_spec}"
    fi

    "${IPTABLES_BIN}" -t nat -A CAKESSH_SNAT -o "${WG_INTERFACE}" -p tcp -d "${target_host}" -j MASQUERADE
    "${IPTABLES_BIN}" -t nat -A CAKESSH_DNAT -p tcp -d "${VPS1_IPV4}" --dport "${listen_iptables_spec}" -j DNAT --to-destination "${target_destination}"
    "${IPTABLES_BIN}" -t filter -A CAKESSH_FORWARD -o "${WG_INTERFACE}" -p tcp -d "${target_host}" --dport "${target_iptables_spec}" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
  done

  ensure_jump nat OUTPUT CAKESSH_DNAT
  ensure_jump nat PREROUTING CAKESSH_DNAT
  ensure_jump nat POSTROUTING CAKESSH_SNAT
  ensure_jump filter FORWARD CAKESSH_FORWARD
}

case "${action}" in
  up)
    remove_rules || true
    install_rules
    ;;
  down)
    remove_rules
    ;;
  *)
    printf 'Unsupported action: %s\n' "${action}" >&2
    exit 1
    ;;
esac
EOF

  chmod 0755 /usr/local/lib/cakessh/cakessh-forwarder
}

write_forwarder_unit() {
  cat > /etc/systemd/system/$(forwarder_service_name) <<EOF
[Unit]
Description=cakessh TCP forwarder
After=network-online.target $(wireguard_service_name)
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/cakessh/cakessh-forwarder up
ExecReload=/usr/local/lib/cakessh/cakessh-forwarder up
ExecStop=/usr/local/lib/cakessh/cakessh-forwarder down
RemainAfterExit=yes
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
}

write_forwarder_config() {
  local index=""
  local rule_value=""

  mkdir -p /etc/cakessh

  {
    printf 'VPS1_IPV4=%q\n' "${VPS1_IPV4}"
    printf 'WG_INTERFACE=%q\n' "${WG_INTERFACE}"
    printf 'WG_VPS2_IP=%q\n' "${WG_VPS2_IP}"
    printf 'FORWARD_RULE_COUNT=%q\n' "${#FORWARD_RULE_NAMES[@]}"

    for index in "${!FORWARD_RULE_NAMES[@]}"; do
      rule_value="${FORWARD_RULE_NAMES[$index]}|${FORWARD_RULE_LISTEN_SPECS[$index]}|${FORWARD_RULE_TARGET_HOSTS[$index]}|${FORWARD_RULE_TARGET_SPECS[$index]}|${FORWARD_RULE_DESCRIPTIONS[$index]}"
      printf 'FORWARD_RULE_%s=%q\n' "$((index + 1))" "${rule_value}"
    done
  } > "$(forwarder_config_path)"

  chmod 0600 "$(forwarder_config_path)"
}

upsert_forwarder_service() {
  local service_name=""

  service_name="$(forwarder_service_name)"
  systemctl enable --now "${service_name}"
  systemctl restart "${service_name}"
  systemctl is-active --quiet "${service_name}" || fail "Forwarder service failed to start: ${service_name}"
}

write_relay_runner() {
  mkdir -p /usr/local/lib/cakessh

  cat > /usr/local/lib/cakessh/cakessh-relay-runner <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

instance_name="${1:?missing relay instance name}"
env_file="/etc/cakessh/relays/${instance_name}.env"

[[ -f "${env_file}" ]] || {
  printf 'Missing relay config: %s\n' "${env_file}" >&2
  exit 1
}

# shellcheck disable=SC1090
. "${env_file}"

: "${LISTEN_PORT:?LISTEN_PORT is required}"
: "${TARGET_ADDRESS:?TARGET_ADDRESS is required}"

SOCAT_BIN="${SOCAT_BIN:-$(command -v socat || true)}"
[[ -n "${SOCAT_BIN}" ]] || {
  printf 'socat not found on PATH.\n' >&2
  exit 1
}

exec "${SOCAT_BIN}" \
  "TCP4-LISTEN:${LISTEN_PORT},bind=0.0.0.0,reuseaddr,fork" \
  "${TARGET_ADDRESS}"
EOF

  chmod 0755 /usr/local/lib/cakessh/cakessh-relay-runner
}

write_systemd_unit() {
  cat > /etc/systemd/system/cakessh-relay@.service <<EOF
[Unit]
Description=cakessh TCP relay (%i)
After=network-online.target wg-quick@${WG_INTERFACE}.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/lib/cakessh/cakessh-relay-runner %i
Restart=always
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
}

write_relay_envs() {
  local index=""
  local name=""
  local listen_port=""
  local target_port=""
  local description=""
  local target_address=""

  mkdir -p /etc/cakessh/relays
  find /etc/cakessh/relays -mindepth 1 -maxdepth 1 -type f -name '*.env' -delete 2>/dev/null || true
  : > /etc/cakessh/instances.list

  for index in "${!RELAY_NAMES[@]}"; do
    name="${RELAY_NAMES[$index]}"
    listen_port="${RELAY_LISTEN_PORTS[$index]}"
    target_port="${RELAY_TARGET_PORTS[$index]}"
    description="${RELAY_DESCRIPTIONS[$index]}"
    target_address="$(build_socat_target_address "${target_port}")"

    {
      printf 'LISTEN_PORT=%q\n' "${listen_port}"
      printf 'TARGET_ADDRESS=%q\n' "${target_address}"
      printf 'DESCRIPTION=%q\n' "${description}"
    } > "/etc/cakessh/relays/${name}.env"

    printf '%s\n' "${name}" >> /etc/cakessh/instances.list
  done
}

enable_relays() {
  local index=""
  local name=""

  for index in "${!RELAY_NAMES[@]}"; do
    name="${RELAY_NAMES[$index]}"
    systemctl enable --now "cakessh-relay@${name}.service"
  done
}

forwarded_public_port_specs() {
  local peer_file=""
  local SSH_PEER_PUBLIC_SSH_PORT=""
  local SSH_PEER_WINGS_PUBLIC_PORT=""
  local -a port_specs=()

  port_specs+=("${PUBLIC_SSH_FORWARD_PORT}")
  port_specs+=("${WINGS_PUBLIC_PORT}")
  port_specs+=("2022")
  port_specs+=("${GAME_PORT_RANGE_LIST[@]}")

  if [[ -d "$(ssh_peer_state_dir)" ]]; then
    for peer_file in "$(ssh_peer_state_dir)"/*.env; do
      [[ -f "${peer_file}" ]] || continue
      SSH_PEER_PUBLIC_SSH_PORT=""
      SSH_PEER_WINGS_PUBLIC_PORT=""
      # shellcheck disable=SC1090
      . "${peer_file}"
      [[ -n "${SSH_PEER_PUBLIC_SSH_PORT}" ]] && port_specs+=("${SSH_PEER_PUBLIC_SSH_PORT}")
      [[ -n "${SSH_PEER_WINGS_PUBLIC_PORT}" ]] && port_specs+=("${SSH_PEER_WINGS_PUBLIC_PORT}")
    done
  fi

  printf '%s\n' "${port_specs[@]}"
}

forwarded_public_port_specs_csv() {
  local -a port_specs=()
  local port_spec=""

  while IFS= read -r port_spec; do
    [[ -n "${port_spec}" ]] || continue
    port_specs+=("${port_spec}")
  done < <(forwarded_public_port_specs)

  join_by_comma "${port_specs[@]}"
}

configure_ufw() {
  local port_spec=""
  local ufw_port_spec=""
  local public_port_specs_csv=""

  public_port_specs_csv="$(forwarded_public_port_specs_csv)"

  if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw is not installed. Open these TCP ports manually: ${public_port_specs_csv} and ${WG_PORT}/udp"
    return 0
  fi

  if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    warn "ufw is not active. Open these TCP ports manually if another firewall is enabled: ${public_port_specs_csv} and ${WG_PORT}/udp"
    return 0
  fi

  ufw allow "${WG_PORT}/udp" >/dev/null
  while IFS= read -r port_spec; do
    [[ -n "${port_spec}" ]] || continue
    ufw_port_spec="$(iptables_port_spec "${port_spec}")"
    ufw allow "${ufw_port_spec}/tcp" >/dev/null
  done < <(forwarded_public_port_specs)
}

configure_wireguard_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw is not installed. Make sure UDP ${WG_PORT}/udp is open on VPS1 if another firewall is enabled."
    return 0
  fi

  if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    warn "ufw is not active. Make sure UDP ${WG_PORT}/udp is open on VPS1 if another firewall is enabled."
    return 0
  fi

  ufw allow "${WG_PORT}/udp" >/dev/null
}

configure_vps2_tunnel_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw is not installed. Make sure traffic from ${WG_VPS1_IP} is allowed on ${WG_INTERFACE} if another firewall is enabled."
    return 0
  fi

  if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    warn "ufw is not active. Make sure traffic from ${WG_VPS1_IP} is allowed on ${WG_INTERFACE} if another firewall is enabled."
    return 0
  fi

  ufw allow in on "${WG_INTERFACE}" from "${WG_VPS1_IP}" >/dev/null
}

validate_vps1_relay_phase() {
  local listen_port=""

  stop_existing_relays
  for listen_port in "${FORWARD_LISTEN_PORT_CHECKS[@]}"; do
    ensure_port_is_free "${listen_port}"
  done
}

prompt_install_inputs() {
  local detected_vps1_ipv4=""

  if [[ "${ROLE}" == "all" || "${ROLE}" == "vps1" ]]; then
    detected_vps1_ipv4="$(detect_primary_ipv4 || true)"
  fi

  if [[ "${ROLE}" == "client" || "${ROLE}" == "all" || "${ROLE}" == "vps1" || "${ROLE}" == "vps2" || "${ROLE}" == "peer" || "${ROLE}" == "vps1-add-peer" ]]; then
    prompt_value VPS1_IPV4 "VPS1 public IPv4 address" "${detected_vps1_ipv4}"
  fi

  if [[ "${ROLE}" == "client" || "${ROLE}" == "all" ]]; then
    prompt_value VPS1_USER "VPS1 SSH username for the jump host" "${DEFAULT_VPS1_USER}"
    prompt_value VPS1_SSH_PORT "VPS1 SSH port for the jump host" "${DEFAULT_VPS1_SSH_PORT}"
    prompt_value VPS2_USER "VPS2 SSH username" "${DEFAULT_VPS2_USER}"
    prompt_value VPS2_SSH_PORT "VPS2 SSH port" "${DEFAULT_VPS2_SSH_PORT}"
    prompt_value WG_VPS2_ADDRESS "VPS2 WireGuard address" "${DEFAULT_WG_VPS2_ADDRESS}"
    if [[ -z "${IDENTITY_FILE}" ]] && prompt_yes_no "Use an SSH key for cakessh connect?" "n"; then
      prompt_value IDENTITY_FILE "Path to the SSH key file" ""
    fi
  fi

  if [[ "${ROLE}" == "vps1" || "${ROLE}" == "all" ]]; then
    prompt_value VPS2_USER "VPS2 SSH username for direct forwarded SSH" "${DEFAULT_VPS2_USER}"
    prompt_value VPS2_SSH_PORT "VPS2 SSH port for direct forwarded SSH" "${DEFAULT_VPS2_SSH_PORT}"
    prompt_value PUBLIC_SSH_FORWARD_PORT "Public SSH relay port on VPS1" "${DEFAULT_PUBLIC_SSH_FORWARD_PORT}"
    prompt_value WG_INTERFACE "WireGuard interface name" "${DEFAULT_WG_INTERFACE}"
    prompt_value WG_PORT "WireGuard UDP port on VPS1" "${DEFAULT_WG_PORT}"
    prompt_value WG_VPS1_ADDRESS "VPS1 WireGuard address" "${DEFAULT_WG_VPS1_ADDRESS}"
    prompt_value WG_VPS2_ADDRESS "VPS2 WireGuard address" "${DEFAULT_WG_VPS2_ADDRESS}"

    if [[ -z "${WG_VPS2_PUBLIC_KEY}" ]] && prompt_yes_no "Do you already have the VPS2 WireGuard public key?" "n"; then
      prompt_optional_value WG_VPS2_PUBLIC_KEY "Paste the VPS2 WireGuard public key (run: sudo bash install.sh show-key vps2 on VPS2)"
    fi

    if [[ -z "${WINGS_SCHEME}" ]]; then
      if prompt_yes_no "Expose Wings over HTTPS?" "n"; then
        WINGS_SCHEME="https"
      else
        WINGS_SCHEME="http"
      fi
    fi

    prompt_value WINGS_PUBLIC_PORT "Public Wings port on VPS1" "$(default_wings_port)"
    prompt_value WINGS_TARGET_PORT "Wings port on VPS2" "$(default_wings_port)"
    prompt_value GAME_PORTS_RAW "Game TCP ports to forward (comma-separated)" "${DEFAULT_GAME_PORTS_RAW}"
  fi

  if [[ "${ROLE}" == "vps2" ]]; then
    prompt_value WG_INTERFACE "WireGuard interface name" "${DEFAULT_WG_INTERFACE}"
    prompt_value WG_PORT "WireGuard UDP port on VPS1" "${DEFAULT_WG_PORT}"
    prompt_value WG_VPS1_ADDRESS "VPS1 WireGuard address" "${DEFAULT_WG_VPS1_ADDRESS}"
    prompt_value WG_VPS2_ADDRESS "VPS2 WireGuard address" "${DEFAULT_WG_VPS2_ADDRESS}"
    prompt_value WG_VPS1_PUBLIC_KEY "VPS1 WireGuard public key (run: sudo bash install.sh show-key vps1 on VPS1)" ""
  fi

  if [[ "${ROLE}" == "peer" ]]; then
    prompt_value PEER_NAME "Peer name, for example vps3" "vps3"
    prompt_value WG_INTERFACE "WireGuard interface name" "${DEFAULT_WG_INTERFACE}"
    prompt_value WG_PORT "WireGuard UDP port on VPS1" "${DEFAULT_WG_PORT}"
    prompt_value WG_VPS1_ADDRESS "VPS1 WireGuard address" "${DEFAULT_WG_VPS1_ADDRESS}"
    prompt_value WG_PEER_ADDRESS "This peer WireGuard address" "${DEFAULT_WG_PEER_ADDRESS}"
    prompt_value WG_VPS1_PUBLIC_KEY "VPS1 WireGuard public key (run: sudo bash install.sh show-key vps1 on VPS1)" ""
  fi

  if [[ "${ROLE}" == "vps1-add-peer" ]]; then
    prompt_value PEER_NAME "Peer name, for example vps3" "vps3"
    prompt_value PEER_USER "Peer SSH username" "${DEFAULT_PEER_USER}"
    prompt_value PEER_SSH_PORT "Peer SSH port" "${DEFAULT_PEER_SSH_PORT}"
    prompt_value PEER_PUBLIC_SSH_PORT "Public SSH port on VPS1 for this peer" "${DEFAULT_PEER_PUBLIC_SSH_PORT}"
    prompt_value WG_INTERFACE "WireGuard interface name" "${DEFAULT_WG_INTERFACE}"
    prompt_value WG_PORT "WireGuard UDP port on VPS1" "${DEFAULT_WG_PORT}"
    prompt_value WG_VPS1_ADDRESS "VPS1 WireGuard address" "${DEFAULT_WG_VPS1_ADDRESS}"
    prompt_value WG_PEER_ADDRESS "Peer WireGuard address" "${DEFAULT_WG_PEER_ADDRESS}"
    if [[ -z "${PEER_WINGS_PUBLIC_PORT}" && -z "${PEER_WINGS_TARGET_PORT}" ]] && prompt_yes_no "Forward Pterodactyl Wings to this peer?" "n"; then
      prompt_value PEER_WINGS_PUBLIC_PORT "Public Wings port on VPS1 for this peer" "${DEFAULT_PEER_WINGS_PUBLIC_PORT}"
      prompt_value PEER_WINGS_TARGET_PORT "Wings port on this peer" "${DEFAULT_PEER_WINGS_TARGET_PORT}"
    elif [[ -n "${PEER_WINGS_PUBLIC_PORT}" || -n "${PEER_WINGS_TARGET_PORT}" ]]; then
      prompt_value PEER_WINGS_PUBLIC_PORT "Public Wings port on VPS1 for this peer" "${DEFAULT_PEER_WINGS_PUBLIC_PORT}"
      prompt_value PEER_WINGS_TARGET_PORT "Wings port on this peer" "${DEFAULT_PEER_WINGS_TARGET_PORT}"
    fi
    prompt_value WG_PEER_PUBLIC_KEY "Peer WireGuard public key (run: sudo bash install.sh show-key peer on the peer)" ""
  fi
}

prepare_relay_plan() {
  local game_port_spec=""
  local game_rule_name=""

  FORWARD_RULE_NAMES=()
  FORWARD_RULE_LISTEN_SPECS=()
  FORWARD_RULE_TARGET_HOSTS=()
  FORWARD_RULE_TARGET_SPECS=()
  FORWARD_RULE_DESCRIPTIONS=()
  FORWARD_LISTEN_PORT_CHECKS=()
  RELAY_NAMES=()
  RELAY_LISTEN_PORTS=()
  RELAY_TARGET_PORTS=()
  RELAY_DESCRIPTIONS=()

  add_forward_rule "ssh-vps2" "${PUBLIC_SSH_FORWARD_PORT}" "${VPS2_SSH_PORT}" "Direct SSH to VPS2 over WireGuard"
  add_forward_rule "wings" "${WINGS_PUBLIC_PORT}" "${WINGS_TARGET_PORT}" "Pterodactyl Wings over WireGuard"
  add_forward_rule "sftp" "2022" "2022" "Pterodactyl SFTP over WireGuard"

  for game_port_spec in "${GAME_PORT_RANGE_LIST[@]}"; do
    game_rule_name="game-${game_port_spec//[^0-9]/-}"
    add_forward_rule "${game_rule_name}" "${game_port_spec}" "${game_port_spec}" "Minecraft game ports over WireGuard"
  done

  add_extra_ssh_peer_forward_rules
}

add_extra_ssh_peer_forward_rules() {
  local peer_file=""
  local SSH_PEER_NAME=""
  local SSH_PEER_WG_IP=""
  local SSH_PEER_PUBLIC_SSH_PORT=""
  local SSH_PEER_SSH_PORT=""
  local SSH_PEER_WINGS_PUBLIC_PORT=""
  local SSH_PEER_WINGS_TARGET_PORT=""

  [[ -d "$(ssh_peer_state_dir)" ]] || return 0

  for peer_file in "$(ssh_peer_state_dir)"/*.env; do
    [[ -f "${peer_file}" ]] || continue
    SSH_PEER_NAME=""
    SSH_PEER_WG_IP=""
    SSH_PEER_PUBLIC_SSH_PORT=""
    SSH_PEER_SSH_PORT=""
    SSH_PEER_WINGS_PUBLIC_PORT=""
    SSH_PEER_WINGS_TARGET_PORT=""
    # shellcheck disable=SC1090
    . "${peer_file}"
    [[ -n "${SSH_PEER_NAME}" && -n "${SSH_PEER_WG_IP}" && -n "${SSH_PEER_PUBLIC_SSH_PORT}" ]] || continue
    SSH_PEER_SSH_PORT="${SSH_PEER_SSH_PORT:-22}"
    add_forward_rule_to_host "${SSH_PEER_WG_IP}" "ssh-${SSH_PEER_NAME}" "${SSH_PEER_PUBLIC_SSH_PORT}" "${SSH_PEER_SSH_PORT}" "Direct SSH to ${SSH_PEER_NAME} over WireGuard"
    if [[ -n "${SSH_PEER_WINGS_PUBLIC_PORT}" || -n "${SSH_PEER_WINGS_TARGET_PORT}" ]]; then
      [[ -n "${SSH_PEER_WINGS_PUBLIC_PORT}" && -n "${SSH_PEER_WINGS_TARGET_PORT}" ]] || fail "Peer ${SSH_PEER_NAME} has incomplete Wings forwarding state."
      add_forward_rule_to_host "${SSH_PEER_WG_IP}" "wings-${SSH_PEER_NAME}" "${SSH_PEER_WINGS_PUBLIC_PORT}" "${SSH_PEER_WINGS_TARGET_PORT}" "Pterodactyl Wings to ${SSH_PEER_NAME} over WireGuard"
    fi
  done
}

validate_client_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_ipv4_basic "${VPS1_IPV4}"
  validate_port "${VPS1_SSH_PORT}"
  validate_port "${VPS2_SSH_PORT}"
  validate_port "${PUBLIC_SSH_FORWARD_PORT}"
  normalize_wings_settings
  normalize_game_ports
  validate_identity_file_if_present
}

validate_vps1_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_ipv4_basic "${VPS1_IPV4}"
  ensure_local_wireguard_ip_available "${WG_VPS1_IP}"
  validate_port "${VPS2_SSH_PORT}"
  validate_port "${PUBLIC_SSH_FORWARD_PORT}"
  validate_port "${WG_PORT}"
  normalize_wings_settings
  validate_wireguard_watchdog_settings
  normalize_game_ports
  validate_wireguard_public_key_if_present "${WG_VPS2_PUBLIC_KEY}"
}

validate_vps2_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_ipv4_basic "${VPS1_IPV4}"
  ensure_local_wireguard_ip_available "${WG_VPS2_IP}"
  validate_port "${WG_PORT}"
  validate_wireguard_watchdog_settings
  validate_wireguard_public_key_if_present "${WG_VPS1_PUBLIC_KEY}"
  [[ -n "${WG_VPS1_PUBLIC_KEY}" ]] || fail "VPS2 install needs the VPS1 public key. On VPS1 run: sudo bash install.sh show-key vps1"
}

validate_peer_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_peer_name
  validate_ipv4_basic "${VPS1_IPV4}"
  ensure_local_wireguard_ip_available "${WG_PEER_IP}"
  validate_port "${WG_PORT}"
  validate_wireguard_watchdog_settings
  validate_wireguard_public_key_if_present "${WG_VPS1_PUBLIC_KEY}"
  [[ -n "${WG_VPS1_PUBLIC_KEY}" ]] || fail "Peer install needs the VPS1 public key. On VPS1 run: sudo bash install.sh show-key vps1"
}

validate_vps1_add_peer_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_ipv4_basic "${VPS1_IPV4}"
  validate_peer_name
  validate_port "${VPS2_SSH_PORT}"
  validate_port "${PUBLIC_SSH_FORWARD_PORT}"
  validate_port "${PEER_SSH_PORT}"
  validate_port "${PEER_PUBLIC_SSH_PORT}"
  validate_port "${WG_PORT}"
  normalize_wings_settings
  validate_peer_wings_settings
  validate_wireguard_watchdog_settings
  normalize_game_ports
  validate_wireguard_public_key_if_present "${WG_PEER_PUBLIC_KEY}"
  [[ -n "${WG_PEER_PUBLIC_KEY}" ]] || fail "VPS1 add-peer needs the peer public key. On the peer run: sudo bash install.sh show-key peer"
}

print_vps1_bootstrap_summary() {
  info ""
  info "VPS1 WireGuard bootstrap complete."
  info "Autostart enabled: $(wireguard_service_name)"
  info "Watchdog timer: $(wireguard_watchdog_timer_name) (enabled after VPS2 key is added)"
  info ""
  info "Next steps:"
  info "  1. On VPS1, show the key when you need it:"
  info "     sudo bash install.sh show-key vps1"
  info "  2. On VPS2, run:"
  info "     sudo bash install.sh vps2 --vps1-ipv4 ${VPS1_IPV4}"
  info "     Paste the VPS1 key when asked."
  info ""
  info "  3. On VPS2, show its key:"
  info "     sudo bash install.sh show-key vps2"
  info "  4. Back on VPS1, run:"
  info "     sudo bash install.sh vps1"
  info "     Paste the VPS2 key when asked."
  info "     Your saved VPS1 settings will be reused automatically."
  info ""
  info "After that you can use either:"
  info "  cakessh connect"
  info "  ssh -p ${PUBLIC_SSH_FORWARD_PORT} ${VPS2_USER}@${VPS1_IPV4}"
}

print_vps2_summary() {
  info ""
  info "VPS2 WireGuard install complete."
  info "Autostart enabled: $(wireguard_service_name)"
  info "Watchdog timer: $(wireguard_watchdog_timer_name)"
  info ""
  info "Next steps:"
  info "  1. On VPS2, show the key:"
  info "     sudo bash install.sh show-key vps2"
  info "  2. Back on VPS1, run:"
  info "     sudo bash install.sh vps1"
  info "     Paste the VPS2 key when asked."
  info "     Your saved VPS1 settings will be reused automatically."
}

print_peer_summary() {
  info ""
  info "${PEER_NAME} WireGuard install complete."
  info "Autostart enabled: $(wireguard_service_name)"
  info "Watchdog timer: $(wireguard_watchdog_timer_name)"
  info ""
  info "Next steps:"
  info "  1. On ${PEER_NAME}, show the key:"
  info "     sudo bash install.sh show-key peer"
  info "  2. Back on VPS1, run:"
  info "     sudo bash install.sh vps1-add-peer --peer-name ${PEER_NAME} --wg-peer-address ${WG_PEER_ADDRESS}"
  info "     Paste the peer key when asked."
}

install_vps1() {
  local wings_port
  local first_game_port

  progress 1 5 "Preparing VPS1"
  require_root
  validate_vps1_inputs
  ensure_supported_linux
  ensure_systemd

  progress 2 5 "Installing and starting WireGuard on VPS1"
  ensure_wireguard_installed
  generate_local_wireguard_keys "vps1"
  write_vps1_wireguard_config
  upsert_wireguard_service
  if [[ -n "${WG_VPS2_PUBLIC_KEY}" ]]; then
    write_wireguard_watchdog_script
    write_wireguard_watchdog_config "${WG_VPS2_PUBLIC_KEY}"
    write_wireguard_watchdog_unit
    upsert_wireguard_watchdog
  fi
  configure_wireguard_firewall
  save_install_state

  if [[ -z "${WG_VPS2_PUBLIC_KEY}" ]]; then
    progress 3 5 "Waiting for VPS2 public key to finish setup"
    print_vps1_bootstrap_summary
    return 0
  fi

  progress 3 5 "Checking WireGuard connection to VPS2"
  ensure_wireguard_backend_reachability
  prepare_relay_plan
  validate_vps1_relay_phase

  progress 4 5 "Installing TCP forwarder on VPS1"
  ensure_iptables_installed
  write_forwarder_runner
  write_forwarder_unit
  write_forwarder_config
  systemctl daemon-reload
  upsert_forwarder_service
  configure_ufw
  save_install_state

  progress 5 5 "VPS1 setup finished"
  wings_port="$(calc_wings_port)"
  first_game_port="${GAME_PORT_LIST[0]}"

  info ""
  info "VPS1 forwarding install complete."
  info "WireGuard backend: ${WG_VPS2_IP} via ${WG_INTERFACE}"
  info "Autostart enabled: $(wireguard_service_name)"
  info "Watchdog timer: $(wireguard_watchdog_timer_name)"
  info "Forwarder service: $(forwarder_service_name)"
  info "Direct SSH:"
  info "  ssh -p ${PUBLIC_SSH_FORWARD_PORT} ${VPS2_USER}@${VPS1_IPV4}"
  if [[ "${WINGS_SCHEME}" == "https" ]]; then
    info "Wings:"
    info "  curl -k https://${VPS1_IPV4}:${wings_port}"
  else
    info "Wings:"
    info "  curl http://${VPS1_IPV4}:${wings_port}"
  fi
  info "  Forward: VPS1 ${WINGS_PUBLIC_PORT} -> VPS2 ${WG_VPS2_IP}:${WINGS_TARGET_PORT}"
  info "SFTP:"
  info "  sftp -P 2022 ${VPS2_USER}@${VPS1_IPV4}"
  info "Minecraft test:"
  info "  nc -vz ${VPS1_IPV4} ${first_game_port}"
  if [[ "${VPS2_SSH_REACHABLE}" == "no" ]]; then
    warn "VPS2 SSH on ${WG_VPS2_IP}:${VPS2_SSH_PORT} was not reachable during install. Direct SSH through VPS1 may fail until sshd is listening there."
  fi
}

install_vps2() {
  progress 1 4 "Preparing VPS2"
  require_root
  validate_vps2_inputs
  ensure_supported_linux
  ensure_systemd

  progress 2 4 "Installing WireGuard on VPS2"
  ensure_wireguard_installed
  generate_local_wireguard_keys "vps2"
  write_vps2_wireguard_config

  progress 3 4 "Enabling WireGuard autostart on VPS2"
  upsert_wireguard_service
  write_wireguard_watchdog_script
  write_wireguard_watchdog_config "${WG_VPS1_PUBLIC_KEY}"
  write_wireguard_watchdog_unit
  upsert_wireguard_watchdog
  configure_vps2_tunnel_firewall
  save_install_state
  progress 4 4 "VPS2 setup finished"
  print_vps2_summary
}

install_peer() {
  progress 1 4 "Preparing ${PEER_NAME}"
  require_root
  validate_peer_inputs
  ensure_supported_linux
  ensure_systemd

  progress 2 4 "Installing WireGuard on ${PEER_NAME}"
  ensure_wireguard_installed
  generate_local_wireguard_keys "peer"
  write_peer_wireguard_config

  progress 3 4 "Enabling WireGuard autostart on ${PEER_NAME}"
  upsert_wireguard_service
  write_wireguard_watchdog_script
  write_wireguard_watchdog_config "${WG_VPS1_PUBLIC_KEY}"
  write_wireguard_watchdog_unit
  upsert_wireguard_watchdog
  configure_vps2_tunnel_firewall
  save_install_state

  progress 4 4 "${PEER_NAME} setup finished"
  print_peer_summary
}

install_vps1_add_peer() {
  progress 1 4 "Preparing VPS1 peer entry"
  require_root
  validate_vps1_add_peer_inputs
  ensure_supported_linux
  ensure_systemd

  progress 2 4 "Adding ${PEER_NAME} to VPS1 WireGuard"
  ensure_wireguard_installed
  generate_local_wireguard_keys "vps1"
  save_ssh_peer_state
  write_vps1_wireguard_config
  upsert_wireguard_service
  configure_wireguard_firewall

  progress 3 4 "Updating VPS1 TCP forwarder"
  prepare_relay_plan
  validate_vps1_relay_phase
  ensure_iptables_installed
  write_forwarder_runner
  write_forwarder_unit
  write_forwarder_config
  systemctl daemon-reload
  upsert_forwarder_service
  configure_ufw
  save_install_state

  progress 4 4 "VPS1 peer entry finished"
  info ""
  info "Added ${PEER_NAME} to VPS1."
  info "Direct SSH:"
  info "  ssh -p ${PEER_PUBLIC_SSH_PORT} ${PEER_USER}@${VPS1_IPV4}"
  if [[ -n "${PEER_WINGS_PUBLIC_PORT}" ]]; then
    info "Peer Wings forward:"
    info "  Forward: VPS1 ${PEER_WINGS_PUBLIC_PORT} -> ${PEER_NAME} ${WG_PEER_IP}:${PEER_WINGS_TARGET_PORT}"
  fi
}

remove_client() {
  determine_client_home
  local helper_target="${CLIENT_INSTALL_HOME}/.local/bin/cakessh"
  local config_dir="${CLIENT_INSTALL_HOME}/.config/cakessh"
  local config_target="${config_dir}/client.env"
  local ssh_alias_config

  ssh_alias_config="$(client_ssh_config_dropin_path)"

  progress 1 2 "Removing client helper and config"
  rm -f -- "${helper_target}"
  rm -f -- "${config_target}"
  rm -f -- "${ssh_alias_config}"
  rmdir "${config_dir}" 2>/dev/null || true
  rmdir "$(client_ssh_config_dropin_dir)" 2>/dev/null || true

  progress 2 2 "Client uninstall finished"
  info "Removed client helper from ${helper_target}"
  info "Removed SSH aliases from ${ssh_alias_config}"
}

remove_vps1() {
  local forwarder_service=""

  require_root
  forwarder_service="$(forwarder_service_name)"

  progress 1 3 "Stopping VPS1 forwarder and relays"
  systemctl disable --now "${forwarder_service}" >/dev/null 2>&1 || true
  disable_relay_instances "Stopping relay batch" "yes"
  find /etc/cakessh/relays -mindepth 1 -maxdepth 1 -type f -name '*.env' -delete 2>/dev/null || true
  rm -f -- /etc/cakessh/instances.list
  rm -f -- "$(forwarder_config_path)"
  rm -f -- "/etc/systemd/system/${forwarder_service}"
  rm -f -- /usr/local/lib/cakessh/cakessh-forwarder
  rm -f -- /etc/systemd/system/cakessh-relay@.service
  rm -f -- /usr/local/lib/cakessh/cakessh-relay-runner
  rmdir /etc/cakessh/relays 2>/dev/null || true
  rmdir /etc/cakessh 2>/dev/null || true
  rmdir /usr/local/lib/cakessh 2>/dev/null || true
  progress 2 3 "Removing WireGuard from VPS1"
  remove_wireguard
  systemctl daemon-reload

  progress 3 3 "VPS1 uninstall finished"
  info "Removed cakessh forwarder, relay leftovers, and WireGuard from VPS1."
  warn "Firewall allow rules were left in place. Remove them manually if you no longer need them."
}

remove_vps2() {
  require_root
  progress 1 2 "Removing WireGuard from VPS2"
  remove_wireguard
  progress 2 2 "VPS2 uninstall finished"
  info "Removed WireGuard from VPS2."
}

remove_peer() {
  require_root
  progress 1 2 "Removing WireGuard from peer"
  remove_wireguard
  progress 2 2 "Peer uninstall finished"
  info "Removed WireGuard from peer."
}

show_public_key() {
  local key_path=""

  require_root
  case "${ROLE}" in
    vps1|vps2|peer) ;;
    *) fail "show-key only supports vps1, vps2, or peer." ;;
  esac

  apply_defaults
  key_path="$(wireguard_public_key_path "${ROLE}")"
  [[ -f "${key_path}" ]] || fail "No WireGuard public key found for ${ROLE}. Run: sudo bash install.sh ${ROLE}"

  info ""
  info "${ROLE} WireGuard public key:"
  cat "${key_path}"
  info ""
  case "${ROLE}" in
    vps1)
      info "Paste this into the VPS2 or peer install when it asks for the VPS1 key."
      ;;
    vps2)
      info "Paste this into the VPS1 install when it asks for the VPS2 key."
      ;;
    peer)
      info "Paste this into the VPS1 add-peer install when it asks for the peer key."
      ;;
  esac
}

run_remove() {
  case "${ROLE}" in
    client)
      remove_client
      ;;
    vps1)
      remove_vps1
      ;;
    vps2)
      remove_vps2
      ;;
    peer)
      remove_peer
      ;;
    all)
      remove_client
      remove_vps1
      ;;
    *)
      fail "Unsupported role for remove: ${ROLE}"
      ;;
  esac
}

run_install() {
  prompt_install_inputs

  case "${ROLE}" in
    client)
      validate_client_inputs
      [[ "${INSTALL_CLIENT_HELPER}" == "yes" ]] || fail "client role requires the helper to be installed."
      install_client
      ;;
    vps1)
      install_vps1
      ;;
    vps2)
      install_vps2
      ;;
    peer)
      install_peer
      ;;
    vps1-add-peer)
      install_vps1_add_peer
      ;;
    all)
      validate_client_inputs
      install_vps1
      if [[ "${INSTALL_CLIENT_HELPER}" == "yes" ]]; then
        install_client
      fi
      ;;
    *)
      fail "Unsupported role for install: ${ROLE}"
      ;;
  esac
}

main() {
  parse_args "$@"
  prompt_role_if_needed
  load_install_state

  if [[ "${ACTION}" == "remove" ]]; then
    run_remove
    return 0
  fi

  if [[ "${ACTION}" == "show-key" ]]; then
    show_public_key
    return 0
  fi

  run_install
}

main "$@"
