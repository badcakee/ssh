#!/usr/bin/env bash
set -euo pipefail

APP_NAME="cakessh"
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
SFTP_PUBLIC_PORT=""
SFTP_TARGET_PORT=""
GAME_PORTS_RAW=""
INSTALL_CLIENT_HELPER="yes"

PEER_NAME=""
PEER_USER=""
PEER_SSH_PORT=""
PEER_PUBLIC_SSH_PORT=""
PEER_WINGS_PUBLIC_PORT=""
PEER_WINGS_TARGET_PORT=""
PEER_SFTP_PUBLIC_PORT=""
PEER_SFTP_TARGET_PORT=""
PEER_GAME_PORTS_RAW=""

WG_INTERFACE=""
WG_PORT=""
WG_VPS1_ADDRESS=""
WG_VPS2_ADDRESS=""
WG_PEER_ADDRESS=""
WG_VPS1_PUBLIC_KEY=""
WG_VPS2_PUBLIC_KEY=""
WG_PEER_PUBLIC_KEY=""
WG_KEEPALIVE_SECONDS=""
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

FORWARD_RULE_NAMES=()
FORWARD_RULE_LISTEN_SPECS=()
FORWARD_RULE_TARGET_HOSTS=()
FORWARD_RULE_TARGET_SPECS=()
FORWARD_RULE_PROTOCOLS=()
FORWARD_RULE_DESCRIPTIONS=()
FORWARD_LISTEN_CHECKS=()
GAME_PORT_LIST=()
GAME_PORT_RANGE_LIST=()
GAME_PORTS_CANONICAL=""
USED_PUBLIC_PROTOCOL_PORTS=()

DEFAULT_VPS1_USER="root"
DEFAULT_VPS2_USER="root"
DEFAULT_PEER_USER="root"
DEFAULT_VPS1_SSH_PORT="22"
DEFAULT_VPS2_SSH_PORT="22"
DEFAULT_PEER_SSH_PORT="22"
DEFAULT_PUBLIC_SSH_FORWARD_PORT="2222"
DEFAULT_PEER_PUBLIC_SSH_PORT="2223"
DEFAULT_WINGS_SCHEME="http"
DEFAULT_WINGS_HTTP_PORT="8080"
DEFAULT_WINGS_HTTPS_PORT="8443"
DEFAULT_PEER_WINGS_PUBLIC_PORT="8081"
DEFAULT_PEER_WINGS_TARGET_PORT="8080"
DEFAULT_SFTP_PUBLIC_PORT="2022"
DEFAULT_SFTP_TARGET_PORT="2022"
DEFAULT_PEER_SFTP_PUBLIC_PORT="2023"
DEFAULT_PEER_SFTP_TARGET_PORT="2022"
DEFAULT_GAME_PORTS_RAW="4000-4999"
DEFAULT_WG_INTERFACE="cakessh-wg"
DEFAULT_WG_PORT="51820"
DEFAULT_WG_VPS1_ADDRESS="172.31.250.1/24"
DEFAULT_WG_VPS2_ADDRESS="172.31.250.2/32"
DEFAULT_WG_PEER_ADDRESS="172.31.250.3/32"
DEFAULT_WG_KEEPALIVE_SECONDS="25"
DEFAULT_WG_WATCHDOG_STALE_SECONDS="300"
DEFAULT_WG_WATCHDOG_RESTART_ON_STALE="yes"
DEFAULT_WINGS_PUBLIC_PORT_CANDIDATES="8080 8081 8082 8083 8443 8444"
DEFAULT_PEER_WINGS_PUBLIC_PORT_CANDIDATES="8081 8080 8082 8083 8444 8443"
DEFAULT_SFTP_PUBLIC_PORT_CANDIDATES="2022 2023 2024 2025"
DEFAULT_PEER_SFTP_PUBLIC_PORT_CANDIDATES="2023 2022 2024 2025"
DEFAULT_ALLOCATION_RANGE_START="4000"
DEFAULT_ALLOCATION_RANGE_END="64999"
DEFAULT_ALLOCATION_RANGE_SIZE="1000"

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

VM layout:
  VM1/VPS1 has the public IPv4 address.
  VM2/VPS2 and VM3/VPS3 can be private WireGuard peers with no public IPv4.

Usage:
  bash install.sh client
  sudo bash install.sh vps1
  sudo bash install.sh vps2
  sudo bash install.sh peer --peer-name vps3
  sudo bash install.sh vps1-add-peer --peer-name vps3
  sudo bash install.sh show-key vps1
  sudo bash install.sh show-key vps2
  sudo bash install.sh show-key peer
  sudo bash install.sh remove vps1

Aliases:
  vm1 = vps1, vm2 = vps2, vm3 = peer, vm1-add-peer = vps1-add-peer

Roles:
  client         Install the local cakessh helper and SSH aliases.
  vps1/vm1      Install WireGuard and the public TCP/UDP forwarder.
  vps2/vm2      Install WireGuard on the first private backend.
  peer/vm3      Install WireGuard on an extra private backend.
  vps1-add-peer Add an extra backend to VM1/VPS1 and refresh forwards.
  all           Install VM1/VPS1 and the local helper.

Common flags:
  --vps1-ipv4 203.0.113.10
  --vps1-user root
  --vps1-ssh-port 22
  --vps2-user root
  --vps2-ssh-port 22
  --public-ssh-port 2222
  --wings-public-port 8080
  --wings-target-port 8080
  --sftp-public-port 2022
  --sftp-target-port 2022
  --game-ports 4000-4999,6000-6999
  --peer-name vps3
  --peer-public-ssh-port 2223
  --peer-wings-public-port 8081
  --peer-wings-target-port 8080
  --peer-sftp-public-port 2023
  --peer-sftp-target-port 2022
  --peer-game-ports 6000-6999
  --wg-interface cakessh-wg
  --wg-port 51820
  --wg-vps1-address 172.31.250.1/24
  --wg-vps2-address 172.31.250.2/32
  --wg-peer-address 172.31.250.3/32
  --wg-vps1-public-key BASE64KEY
  --wg-vps2-public-key BASE64KEY
  --wg-peer-public-key BASE64KEY
  --wg-keepalive-seconds 25
  --wg-watchdog-stale-seconds 300
  --wg-watchdog-restart-on-stale yes|no
  --identity-file /path/to/key
  --no-client-helper
  --help

Notes:
  - SSH, Wings HTTP(S), and Wings SFTP are TCP.
  - Game/allocation ranges are forwarded as TCP and UDP.
  - The installer lists 1000-port allocation blocks only when every TCP and
    UDP port inside the block is free on VM1/VPS1.
EOF
}

canonical_role() {
  case "$1" in
    vm1) printf 'vps1' ;;
    vm2) printf 'vps2' ;;
    vm3) printf 'peer' ;;
    vm1-add-peer) printf 'vps1-add-peer' ;;
    *) printf '%s' "$1" ;;
  esac
}

is_supported_role() {
  case "$(canonical_role "$1")" in
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
      show-vps1-key|show-vm1-key)
        ACTION="show-key"
        ROLE="vps1"
        shift
        ;;
      show-vps2-key|show-vm2-key)
        ACTION="show-key"
        ROLE="vps2"
        shift
        ;;
      show-peer-key|show-vm3-key)
        ACTION="show-key"
        ROLE="peer"
        shift
        ;;
      client|vps1|vps2|peer|vps1-add-peer|all|vm1|vm2|vm3|vm1-add-peer)
        [[ -z "${ROLE}" ]] || fail "Role already set to ${ROLE}"
        ROLE="$(canonical_role "$1")"
        shift
        ;;
      remove)
        ACTION="remove"
        shift
        ;;
      --role)
        [[ $# -ge 2 ]] || fail "Missing value for --role"
        ROLE="$(canonical_role "$2")"
        shift 2
        ;;
      --mode)
        [[ $# -ge 2 ]] || fail "Missing value for --mode"
        ACTION="$2"
        shift 2
        ;;
      --vps1-ipv4|--vm1-ipv4)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        VPS1_IPV4="$2"
        shift 2
        ;;
      --vps1-user|--vm1-user)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        VPS1_USER="$2"
        shift 2
        ;;
      --vps1-ssh-port|--vm1-ssh-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        VPS1_SSH_PORT="$2"
        shift 2
        ;;
      --vps2-user|--vm2-user)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        VPS2_USER="$2"
        shift 2
        ;;
      --vps2-ssh-port|--vm2-ssh-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        VPS2_SSH_PORT="$2"
        shift 2
        ;;
      --peer-name|--vm3-name)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        PEER_NAME="$2"
        shift 2
        ;;
      --peer-user|--vm3-user)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        PEER_USER="$2"
        shift 2
        ;;
      --peer-ssh-port|--vm3-ssh-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        PEER_SSH_PORT="$2"
        shift 2
        ;;
      --peer-public-ssh-port|--public-peer-ssh-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        PEER_PUBLIC_SSH_PORT="$2"
        shift 2
        ;;
      --peer-wings-public-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        PEER_WINGS_PUBLIC_PORT="$2"
        shift 2
        ;;
      --peer-wings-target-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        PEER_WINGS_TARGET_PORT="$2"
        shift 2
        ;;
      --peer-sftp-public-port|--peer-wings-sftp-public-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        PEER_SFTP_PUBLIC_PORT="$2"
        shift 2
        ;;
      --peer-sftp-target-port|--peer-wings-sftp-target-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        PEER_SFTP_TARGET_PORT="$2"
        shift 2
        ;;
      --peer-game-ports|--peer-allocation-ports)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        PEER_GAME_PORTS_RAW="$2"
        shift 2
        ;;
      --identity-file)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        IDENTITY_FILE="$2"
        shift 2
        ;;
      --public-ssh-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        PUBLIC_SSH_FORWARD_PORT="$2"
        shift 2
        ;;
      --wings-scheme)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WINGS_SCHEME="$2"
        shift 2
        ;;
      --wings-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WINGS_PUBLIC_PORT="$2"
        WINGS_TARGET_PORT="${WINGS_TARGET_PORT:-$2}"
        shift 2
        ;;
      --wings-public-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WINGS_PUBLIC_PORT="$2"
        shift 2
        ;;
      --wings-target-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WINGS_TARGET_PORT="$2"
        shift 2
        ;;
      --sftp-public-port|--wings-sftp-public-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        SFTP_PUBLIC_PORT="$2"
        shift 2
        ;;
      --sftp-target-port|--wings-sftp-target-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        SFTP_TARGET_PORT="$2"
        shift 2
        ;;
      --game-ports|--allocation-ports)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        GAME_PORTS_RAW="$2"
        shift 2
        ;;
      --wg-interface)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WG_INTERFACE="$2"
        shift 2
        ;;
      --wg-port)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WG_PORT="$2"
        shift 2
        ;;
      --wg-vps1-address|--wg-vm1-address)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WG_VPS1_ADDRESS="$2"
        shift 2
        ;;
      --wg-vps2-address|--wg-vm2-address)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WG_VPS2_ADDRESS="$2"
        shift 2
        ;;
      --wg-peer-address|--wg-vm3-address)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WG_PEER_ADDRESS="$2"
        shift 2
        ;;
      --wg-vps1-public-key|--wg-vm1-public-key)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WG_VPS1_PUBLIC_KEY="$2"
        shift 2
        ;;
      --wg-vps2-public-key|--wg-vm2-public-key)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WG_VPS2_PUBLIC_KEY="$2"
        shift 2
        ;;
      --wg-peer-public-key|--wg-vm3-public-key)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WG_PEER_PUBLIC_KEY="$2"
        shift 2
        ;;
      --wg-keepalive-seconds)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WG_KEEPALIVE_SECONDS="$2"
        shift 2
        ;;
      --wg-watchdog-stale-seconds)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
        WG_WATCHDOG_STALE_SECONDS="$2"
        shift 2
        ;;
      --wg-watchdog-restart-on-stale)
        [[ $# -ge 2 ]] || fail "Missing value for $1"
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
  local reply=""

  [[ -n "${ROLE}" ]] && return 0

  if ! stdin_is_tty; then
    case "${ACTION}" in
      remove|show-key) ROLE="vps1" ;;
      *) ROLE="all" ;;
    esac
    return 0
  fi

  while true; do
    case "${ACTION}" in
      remove)
        read -r -p "What do you want to remove? (client/vps1/vps2/peer/all) [vps1]: " reply
        reply="${reply:-vps1}"
        ;;
      show-key)
        read -r -p "Which WireGuard public key? (vps1/vps2/peer) [vps1]: " reply
        reply="${reply:-vps1}"
        ;;
      *)
        read -r -p "Which role do you want to install? (client/vps1/vps2/peer/vps1-add-peer/all) [all]: " reply
        reply="${reply:-all}"
        ;;
    esac

    reply="$(canonical_role "${reply}")"
    if is_supported_role "${reply}"; then
      ROLE="${reply}"
      return 0
    fi
    info "Please choose a supported role."
  done
}

prompt_value() {
  local variable_name="$1"
  local prompt_text="$2"
  local default_value="${3:-}"
  local current_value="${!variable_name:-}"
  local reply=""

  [[ -n "${current_value}" ]] && return 0

  if ! stdin_is_tty; then
    [[ -n "${default_value}" ]] || fail "Missing required value for ${variable_name}."
    printf -v "${variable_name}" '%s' "${default_value}"
    return 0
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

  [[ -n "${current_value}" || ! stdin_is_tty ]] && return 0
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

array_contains() {
  local needle="$1"
  shift || true
  local item=""

  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

validate_port() {
  local port="$1"
  [[ "${port}" =~ ^[0-9]+$ ]] || fail "Port must be numeric: ${port}"
  ((10#${port} >= 1 && 10#${port} <= 65535)) || fail "Port must be between 1 and 65535: ${port}"
}

validate_yes_no() {
  local value="$1"
  local label="$2"

  case "${value}" in
    yes|no) ;;
    *) fail "${label} must be yes or no, not ${value}" ;;
  esac
}

validate_ipv4_basic() {
  local ip="$1"
  local octet=""
  local -a octets=()

  [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "Invalid IPv4 format: ${ip}"
  IFS='.' read -r -a octets <<< "${ip}"
  for octet in "${octets[@]}"; do
    ((10#${octet} >= 0 && 10#${octet} <= 255)) || fail "Invalid IPv4 octet in ${ip}"
  done
}

validate_ipv4_cidr() {
  local cidr="$1"
  local ip_part="${cidr%%/*}"
  local prefix="${cidr#*/}"

  [[ "${cidr}" == */* ]] || fail "WireGuard address must use CIDR notation: ${cidr}"
  validate_ipv4_basic "${ip_part}"
  [[ "${prefix}" =~ ^[0-9]+$ ]] || fail "Invalid CIDR prefix in ${cidr}"
  ((10#${prefix} >= 0 && 10#${prefix} <= 32)) || fail "CIDR prefix must be between 0 and 32: ${cidr}"
}

validate_wireguard_public_key_if_present() {
  local key="$1"

  [[ -z "${key}" ]] && return 0
  [[ "${key}" =~ ^[A-Za-z0-9+/=]+$ ]] || fail "WireGuard public key contains invalid characters."
  ((${#key} >= 40)) || fail "WireGuard public key looks too short."
}

validate_wings_scheme() {
  case "${WINGS_SCHEME}" in
    http|https) ;;
    *) fail "Wings scheme must be http or https, not ${WINGS_SCHEME}" ;;
  esac
}

validate_peer_name() {
  [[ -n "${PEER_NAME}" ]] || fail "Missing peer name. Use --peer-name vps3"
  [[ "${PEER_NAME}" =~ ^[A-Za-z0-9_-]+$ ]] || fail "Peer name can only contain letters, numbers, underscore, and dash."
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
    ((10#${range_start} <= 10#${range_end})) || fail "Invalid port range: ${port_spec}"
    return 0
  fi

  validate_port "${port_spec}"
}

expand_port_spec() {
  local port_spec="$1"
  local range_start=""
  local range_end=""
  local current_port=""

  if [[ "${port_spec}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    range_start="${BASH_REMATCH[1]}"
    range_end="${BASH_REMATCH[2]}"
    current_port="${range_start}"
    while ((current_port <= range_end)); do
      printf '%s\n' "${current_port}"
      current_port=$((current_port + 1))
    done
    return 0
  fi

  printf '%s\n' "${port_spec}"
}

iptables_port_spec() {
  local port_spec="$1"
  printf '%s' "${port_spec//-/:}"
}

normalize_protocols() {
  local raw="${1:-tcp}"
  local cleaned="${raw//,/ }"
  local token=""
  local -a protocols=()

  for token in ${cleaned}; do
    case "${token}" in
      all)
        array_contains "tcp" "${protocols[@]:-}" || protocols+=("tcp")
        array_contains "udp" "${protocols[@]:-}" || protocols+=("udp")
        ;;
      tcp|udp)
        array_contains "${token}" "${protocols[@]:-}" || protocols+=("${token}")
        ;;
      *)
        fail "Protocol must be tcp, udp, tcp,udp, or all, not ${token}"
        ;;
    esac
  done

  ((${#protocols[@]} > 0)) || fail "At least one protocol is required."
  join_by_comma "${protocols[@]}"
}

protocol_items() {
  local protocols="$1"
  local token=""

  for token in ${protocols//,/ }; do
    [[ -n "${token}" ]] || continue
    printf '%s\n' "${token}"
  done
}

default_wings_port() {
  if [[ "${WINGS_SCHEME:-${DEFAULT_WINGS_SCHEME}}" == "https" ]]; then
    printf '%s' "${DEFAULT_WINGS_HTTPS_PORT}"
  else
    printf '%s' "${DEFAULT_WINGS_HTTP_PORT}"
  fi
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
  SFTP_PUBLIC_PORT="${SFTP_PUBLIC_PORT:-${DEFAULT_SFTP_PUBLIC_PORT}}"
  SFTP_TARGET_PORT="${SFTP_TARGET_PORT:-${DEFAULT_SFTP_TARGET_PORT}}"
  GAME_PORTS_RAW="${GAME_PORTS_RAW:-${DEFAULT_GAME_PORTS_RAW}}"
  WG_INTERFACE="${WG_INTERFACE:-${DEFAULT_WG_INTERFACE}}"
  WG_PORT="${WG_PORT:-${DEFAULT_WG_PORT}}"
  WG_VPS1_ADDRESS="${WG_VPS1_ADDRESS:-${DEFAULT_WG_VPS1_ADDRESS}}"
  WG_VPS2_ADDRESS="${WG_VPS2_ADDRESS:-${DEFAULT_WG_VPS2_ADDRESS}}"
  WG_PEER_ADDRESS="${WG_PEER_ADDRESS:-${DEFAULT_WG_PEER_ADDRESS}}"
  WG_KEEPALIVE_SECONDS="${WG_KEEPALIVE_SECONDS:-${DEFAULT_WG_KEEPALIVE_SECONDS}}"
  WG_WATCHDOG_STALE_SECONDS="${WG_WATCHDOG_STALE_SECONDS:-${DEFAULT_WG_WATCHDOG_STALE_SECONDS}}"
  WG_WATCHDOG_RESTART_ON_STALE="${WG_WATCHDOG_RESTART_ON_STALE:-${DEFAULT_WG_WATCHDOG_RESTART_ON_STALE}}"
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

  [[ "${WG_VPS1_IP}" != "${WG_VPS2_IP}" ]] || fail "VM1 and VM2 WireGuard IPs must be different."
  [[ "${WG_VPS1_IP}" != "${WG_PEER_IP}" ]] || fail "VM1 and peer WireGuard IPs must be different."
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
  local sorted_port=""
  local current_port=""
  local previous_port=""
  local range_start=""
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
    if ((current_port == previous_port + 1)); then
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
    [[ -n "${token}" ]] || continue
    if [[ "${token}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      range_start="${BASH_REMATCH[1]}"
      range_end="${BASH_REMATCH[2]}"
      validate_port "${range_start}"
      validate_port "${range_end}"
      ((10#${range_start} <= 10#${range_end})) || fail "Invalid port range: ${token}"
      current_port="${range_start}"
      while ((current_port <= range_end)); do
        array_contains "${current_port}" "${GAME_PORT_LIST[@]:-}" || GAME_PORT_LIST+=("${current_port}")
        current_port=$((current_port + 1))
      done
    else
      validate_port "${token}"
      array_contains "${token}" "${GAME_PORT_LIST[@]:-}" || GAME_PORT_LIST+=("${token}")
    fi
  done

  ((${#GAME_PORT_LIST[@]} > 0)) || fail "At least one game/allocation port is required."
  compress_game_ports
}

split_peer_game_port_token() {
  local token="$1"
  local listen_var="$2"
  local target_var="$3"
  local listen_spec=""
  local target_spec=""

  if [[ "${token}" =~ ^([^:]+):([^:]+)$ ]]; then
    listen_spec="${BASH_REMATCH[1]}"
    target_spec="${BASH_REMATCH[2]}"
  elif [[ "${token}" == *:* ]]; then
    fail "Invalid peer game port mapping: ${token}"
  else
    listen_spec="${token}"
    target_spec="${token}"
  fi

  printf -v "${listen_var}" '%s' "${listen_spec}"
  printf -v "${target_var}" '%s' "${target_spec}"
}

validate_peer_game_ports() {
  local cleaned="${PEER_GAME_PORTS_RAW//,/ }"
  local token=""
  local listen_spec=""
  local target_spec=""

  [[ -n "${PEER_GAME_PORTS_RAW}" ]] || return 0
  for token in ${cleaned}; do
    [[ -n "${token}" ]] || continue
    split_peer_game_port_token "${token}" listen_spec target_spec
    validate_port_spec "${listen_spec}"
    validate_port_spec "${target_spec}"
    if [[ "${listen_spec}" == *-* && "${target_spec}" != "${listen_spec}" ]]; then
      fail "Peer port ranges must use the same public and target range: ${listen_spec}:${target_spec}"
    fi
  done
}

validate_peer_wings_settings() {
  if [[ -z "${PEER_WINGS_PUBLIC_PORT}" && -z "${PEER_WINGS_TARGET_PORT}" ]]; then
    return 0
  fi
  [[ -n "${PEER_WINGS_PUBLIC_PORT}" ]] || fail "Missing --peer-wings-public-port."
  [[ -n "${PEER_WINGS_TARGET_PORT}" ]] || fail "Missing --peer-wings-target-port."
  validate_port "${PEER_WINGS_PUBLIC_PORT}"
  validate_port "${PEER_WINGS_TARGET_PORT}"
}

validate_peer_sftp_settings() {
  if [[ -z "${PEER_SFTP_PUBLIC_PORT}" && -z "${PEER_SFTP_TARGET_PORT}" ]]; then
    return 0
  fi
  [[ -n "${PEER_SFTP_PUBLIC_PORT}" ]] || fail "Missing --peer-sftp-public-port."
  [[ -n "${PEER_SFTP_TARGET_PORT}" ]] || fail "Missing --peer-sftp-target-port."
  validate_port "${PEER_SFTP_PUBLIC_PORT}"
  validate_port "${PEER_SFTP_TARGET_PORT}"
}

validate_watchdog_settings() {
  apply_defaults
  validate_port "${WG_PORT}"
  [[ "${WG_KEEPALIVE_SECONDS}" =~ ^[0-9]+$ ]] || fail "--wg-keepalive-seconds must be numeric."
  ((10#${WG_KEEPALIVE_SECONDS} >= 0 && 10#${WG_KEEPALIVE_SECONDS} <= 65535)) || fail "--wg-keepalive-seconds must be between 0 and 65535."
  [[ "${WG_WATCHDOG_STALE_SECONDS}" =~ ^[0-9]+$ ]] || fail "--wg-watchdog-stale-seconds must be numeric."
  ((10#${WG_WATCHDOG_STALE_SECONDS} >= 60)) || fail "--wg-watchdog-stale-seconds must be at least 60."
  validate_yes_no "${WG_WATCHDOG_RESTART_ON_STALE}" "--wg-watchdog-restart-on-stale"
}

determine_client_home() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    CLIENT_INSTALL_USER="${SUDO_USER}"
    if command -v getent >/dev/null 2>&1; then
      CLIENT_INSTALL_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
    else
      CLIENT_INSTALL_HOME="${HOME}"
    fi
  else
    CLIENT_INSTALL_USER="${USER:-$(id -un)}"
    CLIENT_INSTALL_HOME="${HOME}"
  fi

  [[ -n "${CLIENT_INSTALL_HOME}" ]] || fail "Could not determine the client home directory."
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "This step must be run as root. Try: sudo bash install.sh ${ROLE}"
}

detect_primary_ipv4() {
  if command -v ip >/dev/null 2>&1; then
    ip -o -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}'
    return
  fi
  if command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1; exit}'
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
  command -v systemctl >/dev/null 2>&1 || fail "systemd is required."
}

ensure_ssh_client() {
  command -v ssh >/dev/null 2>&1 || fail "OpenSSH client not found."
}

ensure_packages() {
  local missing="no"
  local pkg=""
  local -a packages=("$@")

  for pkg in "${packages[@]}"; do
    case "${pkg}" in
      wireguard-tools)
        command -v wg >/dev/null 2>&1 && command -v wg-quick >/dev/null 2>&1 || missing="yes"
        ;;
      iptables)
        command -v iptables >/dev/null 2>&1 || missing="yes"
        ;;
      iproute2)
        command -v ip >/dev/null 2>&1 && command -v ss >/dev/null 2>&1 || missing="yes"
        ;;
      iputils-ping)
        command -v ping >/dev/null 2>&1 || missing="yes"
        ;;
      *)
        ;;
    esac
  done

  [[ "${missing}" == "no" ]] && return 0
  info "Installing required packages with apt..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

wireguard_state_dir() { printf '/etc/cakessh/wireguard'; }
wireguard_config_path() { printf '/etc/wireguard/%s.conf' "${WG_INTERFACE}"; }
wireguard_service_name() { printf 'wg-quick@%s.service' "${WG_INTERFACE}"; }
watchdog_script_path() { printf '/usr/local/lib/cakessh/cakessh-wg-watchdog'; }
watchdog_config_path() { printf '/etc/cakessh/watchdog.env'; }
watchdog_service_name() { printf 'cakessh-wg-watchdog.service'; }
watchdog_timer_name() { printf 'cakessh-wg-watchdog.timer'; }
forwarder_script_path() { printf '/usr/local/lib/cakessh/cakessh-forwarder'; }
forwarder_config_path() { printf '/etc/cakessh/forwarder.env'; }
forwarder_service_name() { printf 'cakessh-forward.service'; }
install_state_path() { printf '/etc/cakessh/install.env'; }
ssh_peer_state_dir() { printf '/etc/cakessh/ssh-peers'; }
ssh_peer_state_path() { printf '%s/%s.env' "$(ssh_peer_state_dir)" "$1"; }

wireguard_private_key_path() {
  printf '%s/%s.privatekey' "$(wireguard_state_dir)" "$1"
}

wireguard_public_key_path() {
  printf '%s/%s.publickey' "$(wireguard_state_dir)" "$1"
}

generate_wireguard_keys() {
  local node_role="$1"
  local state_dir=""
  local private_key_file=""
  local public_key_file=""

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
    printf '# %s\n' "${SSH_PEER_NAME:-peer}"
    printf 'PublicKey = %s\n' "${SSH_PEER_PUBLIC_KEY}"
    printf 'AllowedIPs = %s/32\n' "${SSH_PEER_WG_IP}"
    printf 'PersistentKeepalive = %s\n' "${WG_KEEPALIVE_SECONDS}"
  done
}

write_vps1_wireguard_config() {
  local config_path=""
  config_path="$(wireguard_config_path)"

  umask 077
  {
    printf '[Interface]\n'
    printf 'Address = %s\n' "${WG_VPS1_ADDRESS}"
    printf 'ListenPort = %s\n' "${WG_PORT}"
    printf 'PrivateKey = %s\n' "${LOCAL_WG_PRIVATE_KEY}"

    if [[ -n "${WG_VPS2_PUBLIC_KEY}" ]]; then
      printf '\n[Peer]\n'
      printf '# vps2\n'
      printf 'PublicKey = %s\n' "${WG_VPS2_PUBLIC_KEY}"
      printf 'AllowedIPs = %s/32\n' "${WG_VPS2_IP}"
      printf 'PersistentKeepalive = %s\n' "${WG_KEEPALIVE_SECONDS}"
    fi

    print_extra_wireguard_peer_blocks
  } > "${config_path}"
  chmod 0600 "${config_path}"
}

write_vps2_wireguard_config() {
  local config_path=""
  config_path="$(wireguard_config_path)"

  umask 077
  {
    printf '[Interface]\n'
    printf 'Address = %s\n' "${WG_VPS2_ADDRESS}"
    printf 'PrivateKey = %s\n' "${LOCAL_WG_PRIVATE_KEY}"
    printf '\n[Peer]\n'
    printf '# vps1\n'
    printf 'PublicKey = %s\n' "${WG_VPS1_PUBLIC_KEY}"
    printf 'AllowedIPs = %s/32\n' "${WG_VPS1_IP}"
    printf 'Endpoint = %s:%s\n' "${VPS1_IPV4}" "${WG_PORT}"
    printf 'PersistentKeepalive = %s\n' "${WG_KEEPALIVE_SECONDS}"
  } > "${config_path}"
  chmod 0600 "${config_path}"
}

write_peer_wireguard_config() {
  local config_path=""
  config_path="$(wireguard_config_path)"

  umask 077
  {
    printf '[Interface]\n'
    printf 'Address = %s\n' "${WG_PEER_ADDRESS}"
    printf 'PrivateKey = %s\n' "${LOCAL_WG_PRIVATE_KEY}"
    printf '\n[Peer]\n'
    printf '# vps1\n'
    printf 'PublicKey = %s\n' "${WG_VPS1_PUBLIC_KEY}"
    printf 'AllowedIPs = %s/32\n' "${WG_VPS1_IP}"
    printf 'Endpoint = %s:%s\n' "${VPS1_IPV4}" "${WG_PORT}"
    printf 'PersistentKeepalive = %s\n' "${WG_KEEPALIVE_SECONDS}"
  } > "${config_path}"
  chmod 0600 "${config_path}"
}

upsert_wireguard_service() {
  local service_name=""
  service_name="$(wireguard_service_name)"

  systemctl enable --now "${service_name}"
  systemctl restart "${service_name}"
  systemctl is-active --quiet "${service_name}" || fail "WireGuard service failed to start: ${service_name}"
}

collect_watchdog_peer_ips() {
  local peer_file=""
  local SSH_PEER_WG_IP=""
  local -a peer_ips=()

  if [[ -n "${WG_VPS2_PUBLIC_KEY}" ]]; then
    peer_ips+=("${WG_VPS2_IP}")
  fi

  if [[ -d "$(ssh_peer_state_dir)" ]]; then
    for peer_file in "$(ssh_peer_state_dir)"/*.env; do
      [[ -f "${peer_file}" ]] || continue
      SSH_PEER_WG_IP=""
      # shellcheck disable=SC1090
      . "${peer_file}"
      [[ -n "${SSH_PEER_WG_IP}" ]] && peer_ips+=("${SSH_PEER_WG_IP}")
    done
  fi

  printf '%s' "${peer_ips[*]:-}"
}

write_watchdog_script() {
  mkdir -p /usr/local/lib/cakessh
  cat > "$(watchdog_script_path)" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

config_file="/etc/cakessh/watchdog.env"
[[ -f "${config_file}" ]] || exit 0

# shellcheck disable=SC1090
. "${config_file}"

: "${WG_INTERFACE:?WG_INTERFACE is required}"
WG_PEER_IPS="${WG_PEER_IPS:-}"
WG_MAX_STALE_SECONDS="${WG_MAX_STALE_SECONDS:-300}"
WG_RESTART_ON_STALE="${WG_RESTART_ON_STALE:-yes}"

WG_BIN="${WG_BIN:-$(command -v wg || true)}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-$(command -v systemctl || true)}"
DATE_BIN="${DATE_BIN:-$(command -v date || true)}"
PING_BIN="${PING_BIN:-$(command -v ping || true)}"
LOGGER_BIN="${LOGGER_BIN:-$(command -v logger || true)}"

[[ -n "${WG_BIN}" && -n "${SYSTEMCTL_BIN}" && -n "${DATE_BIN}" ]] || exit 0

log_msg() {
  if [[ -n "${LOGGER_BIN}" ]]; then
    "${LOGGER_BIN}" -t cakessh-wg-watchdog "$*"
  fi
}

restart_wg() {
  local reason="$1"
  log_msg "Restarting ${WG_INTERFACE}: ${reason}."
  "${SYSTEMCTL_BIN}" restart "wg-quick@${WG_INTERFACE}.service"
}

if ! "${WG_BIN}" show "${WG_INTERFACE}" >/dev/null 2>&1; then
  restart_wg "interface is down"
  exit 0
fi

# This keeps otherwise idle tunnels warm. It is deliberately best-effort:
# firewall policy on the peer might block ICMP, but the packet still nudges
# WireGuard and refreshes endpoint state when the peer is reachable.
if [[ -n "${PING_BIN}" && -n "${WG_PEER_IPS}" ]]; then
  for peer_ip in ${WG_PEER_IPS}; do
    "${PING_BIN}" -c 1 -W 2 -I "${WG_INTERFACE}" "${peer_ip}" >/dev/null 2>&1 || true
  done
fi

[[ "${WG_RESTART_ON_STALE}" == "yes" ]] || exit 0

latest_handshake="$("${WG_BIN}" show "${WG_INTERFACE}" latest-handshakes 2>/dev/null | awk '$2 > latest { latest = $2 } END { print latest + 0 }')"
now="$("${DATE_BIN}" +%s)"

if [[ "${latest_handshake}" == "0" ]]; then
  restart_wg "no peer handshake has been recorded"
elif (( now - latest_handshake > 10#${WG_MAX_STALE_SECONDS} )); then
  restart_wg "latest handshake is stale"
fi
EOF
  chmod 0755 "$(watchdog_script_path)"
}

write_watchdog_config() {
  local peer_ips="$1"

  mkdir -p /etc/cakessh
  {
    printf 'WG_INTERFACE=%q\n' "${WG_INTERFACE}"
    printf 'WG_PEER_IPS=%q\n' "${peer_ips}"
    printf 'WG_MAX_STALE_SECONDS=%q\n' "${WG_WATCHDOG_STALE_SECONDS}"
    printf 'WG_RESTART_ON_STALE=%q\n' "${WG_WATCHDOG_RESTART_ON_STALE}"
  } > "$(watchdog_config_path)"
  chmod 0600 "$(watchdog_config_path)"
}

write_watchdog_units() {
  cat > "/etc/systemd/system/$(watchdog_service_name)" <<EOF
[Unit]
Description=cakessh WireGuard keepalive watchdog
After=$(wireguard_service_name)
Wants=$(wireguard_service_name)

[Service]
Type=oneshot
ExecStart=$(watchdog_script_path)
NoNewPrivileges=true
EOF

  cat > "/etc/systemd/system/$(watchdog_timer_name)" <<EOF
[Unit]
Description=Run cakessh WireGuard keepalive watchdog

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=10s
Unit=$(watchdog_service_name)

[Install]
WantedBy=timers.target
EOF
}

upsert_watchdog() {
  local peer_ips="$1"
  [[ -n "${peer_ips}" ]] || return 0

  write_watchdog_script
  write_watchdog_config "${peer_ips}"
  write_watchdog_units
  systemctl daemon-reload
  systemctl enable --now "$(watchdog_timer_name)"
  systemctl restart "$(watchdog_timer_name)"
  systemctl is-active --quiet "$(watchdog_timer_name)" || fail "Watchdog timer failed to start."
}

remove_watchdog() {
  systemctl disable --now "$(watchdog_timer_name)" >/dev/null 2>&1 || true
  systemctl disable --now "$(watchdog_service_name)" >/dev/null 2>&1 || true
  rm -f -- "/etc/systemd/system/$(watchdog_service_name)"
  rm -f -- "/etc/systemd/system/$(watchdog_timer_name)"
  rm -f -- "$(watchdog_config_path)"
  rm -f -- "$(watchdog_script_path)"
}

remove_wireguard() {
  local service_name=""
  apply_defaults
  service_name="$(wireguard_service_name)"

  remove_watchdog
  systemctl disable --now "${service_name}" >/dev/null 2>&1 || true
  rm -f -- "$(wireguard_config_path)"
  rm -f -- "$(wireguard_private_key_path "vps1")" "$(wireguard_public_key_path "vps1")"
  rm -f -- "$(wireguard_private_key_path "vps2")" "$(wireguard_public_key_path "vps2")"
  rm -f -- "$(wireguard_private_key_path "peer")" "$(wireguard_public_key_path "peer")"
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
  SFTP_PUBLIC_PORT="${SFTP_PUBLIC_PORT:-${STATE_SFTP_PUBLIC_PORT:-}}"
  SFTP_TARGET_PORT="${SFTP_TARGET_PORT:-${STATE_SFTP_TARGET_PORT:-}}"
  GAME_PORTS_RAW="${GAME_PORTS_RAW:-${STATE_GAME_PORTS_RAW:-}}"
  WG_INTERFACE="${WG_INTERFACE:-${STATE_WG_INTERFACE:-}}"
  WG_PORT="${WG_PORT:-${STATE_WG_PORT:-}}"
  WG_VPS1_ADDRESS="${WG_VPS1_ADDRESS:-${STATE_WG_VPS1_ADDRESS:-}}"
  WG_VPS2_ADDRESS="${WG_VPS2_ADDRESS:-${STATE_WG_VPS2_ADDRESS:-}}"
  WG_VPS1_PUBLIC_KEY="${WG_VPS1_PUBLIC_KEY:-${STATE_WG_VPS1_PUBLIC_KEY:-}}"
  WG_VPS2_PUBLIC_KEY="${WG_VPS2_PUBLIC_KEY:-${STATE_WG_VPS2_PUBLIC_KEY:-}}"
  WG_KEEPALIVE_SECONDS="${WG_KEEPALIVE_SECONDS:-${STATE_WG_KEEPALIVE_SECONDS:-}}"
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
    printf 'STATE_SFTP_PUBLIC_PORT=%q\n' "${SFTP_PUBLIC_PORT}"
    printf 'STATE_SFTP_TARGET_PORT=%q\n' "${SFTP_TARGET_PORT}"
    printf 'STATE_GAME_PORTS_RAW=%q\n' "${GAME_PORTS_RAW}"
    printf 'STATE_WG_INTERFACE=%q\n' "${WG_INTERFACE}"
    printf 'STATE_WG_PORT=%q\n' "${WG_PORT}"
    printf 'STATE_WG_VPS1_ADDRESS=%q\n' "${WG_VPS1_ADDRESS}"
    printf 'STATE_WG_VPS2_ADDRESS=%q\n' "${WG_VPS2_ADDRESS}"
    printf 'STATE_WG_VPS1_PUBLIC_KEY=%q\n' "${WG_VPS1_PUBLIC_KEY}"
    printf 'STATE_WG_VPS2_PUBLIC_KEY=%q\n' "${WG_VPS2_PUBLIC_KEY}"
    printf 'STATE_WG_KEEPALIVE_SECONDS=%q\n' "${WG_KEEPALIVE_SECONDS}"
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
    printf 'SSH_PEER_SFTP_PUBLIC_PORT=%q\n' "${PEER_SFTP_PUBLIC_PORT}"
    printf 'SSH_PEER_SFTP_TARGET_PORT=%q\n' "${PEER_SFTP_TARGET_PORT}"
    printf 'SSH_PEER_GAME_PORTS_RAW=%q\n' "${PEER_GAME_PORTS_RAW}"
    printf 'SSH_PEER_WG_ADDRESS=%q\n' "${WG_PEER_ADDRESS}"
    printf 'SSH_PEER_WG_IP=%q\n' "${WG_PEER_IP}"
    printf 'SSH_PEER_PUBLIC_KEY=%q\n' "${WG_PEER_PUBLIC_KEY}"
  } > "${state_path}"
  chmod 0600 "${state_path}"
}

parse_forward_rule_value() {
  local rule_value="$1"
  local name_var="$2"
  local listen_var="$3"
  local host_var="$4"
  local target_var="$5"
  local protocols_var="$6"
  local description_var="$7"
  local name=""
  local listen_spec=""
  local field3=""
  local field4=""
  local field5=""
  local field6=""
  local field7=""
  local target_host=""
  local target_spec=""
  local protocols="tcp"
  local description=""

  IFS='|' read -r name listen_spec field3 field4 field5 field6 field7 <<< "${rule_value}"
  if [[ -n "${field6}" || "${field5}" == "tcp" || "${field5}" == "udp" || "${field5}" == "tcp,udp" || "${field5}" == "udp,tcp" || "${field5}" == "all" ]]; then
    target_host="${field3}"
    target_spec="${field4}"
    protocols="$(normalize_protocols "${field5:-tcp}")"
    description="${field6}"
  else
    target_host="${field3}"
    target_spec="${field4}"
    description="${field5}"
    if [[ -z "${description}" ]]; then
      description="${field4}"
      target_spec="${field3}"
      target_host="${WG_VPS2_IP}"
    fi
  fi

  printf -v "${name_var}" '%s' "${name}"
  printf -v "${listen_var}" '%s' "${listen_spec}"
  printf -v "${host_var}" '%s' "${target_host}"
  printf -v "${target_var}" '%s' "${target_spec}"
  printf -v "${protocols_var}" '%s' "${protocols}"
  printf -v "${description_var}" '%s' "${description}"
}

list_listening_protocol_ports() {
  command -v ss >/dev/null 2>&1 || return 0
  ss -H -lntu 2>/dev/null | awk '
    {
      protocol = $1
      local_address = $5
      port = local_address
      sub(/^.*:/, "", port)
      if (port ~ /^[0-9]+$/ && (protocol == "tcp" || protocol == "udp")) {
        print protocol ":" port
      }
    }
  '
}

list_cakessh_forwarded_protocol_ports() {
  local config_path=""
  local rule_count=""
  local index=""
  local rule_var=""
  local rule_value=""
  local name=""
  local listen_spec=""
  local target_host=""
  local target_spec=""
  local protocols=""
  local description=""
  local protocol=""
  local port=""
  local VPS1_IPV4=""
  local WG_INTERFACE=""
  local WG_VPS2_IP=""
  local FORWARD_RULE_COUNT=""

  config_path="$(forwarder_config_path)"
  [[ -r "${config_path}" ]] || return 0
  # shellcheck disable=SC1090
  . "${config_path}"
  rule_count="${FORWARD_RULE_COUNT:-0}"

  for ((index = 1; index <= rule_count; index++)); do
    rule_var="FORWARD_RULE_${index}"
    rule_value="${!rule_var:-}"
    [[ -n "${rule_value}" ]] || continue
    parse_forward_rule_value "${rule_value}" name listen_spec target_host target_spec protocols description
    while IFS= read -r protocol; do
      while IFS= read -r port; do
        [[ -n "${port}" ]] && printf '%s:%s\n' "${protocol}" "${port}"
      done < <(expand_port_spec "${listen_spec}")
    done < <(protocol_items "${protocols}")
  done
}

refresh_used_public_ports() {
  local entry=""
  USED_PUBLIC_PROTOCOL_PORTS=()
  while IFS= read -r entry; do
    [[ -n "${entry}" ]] || continue
    array_contains "${entry}" "${USED_PUBLIC_PROTOCOL_PORTS[@]:-}" || USED_PUBLIC_PROTOCOL_PORTS+=("${entry}")
  done < <({ list_listening_protocol_ports; list_cakessh_forwarded_protocol_ports; } | sort -u)
}

refresh_listening_public_ports() {
  local entry=""
  USED_PUBLIC_PROTOCOL_PORTS=()
  while IFS= read -r entry; do
    [[ -n "${entry}" ]] || continue
    array_contains "${entry}" "${USED_PUBLIC_PROTOCOL_PORTS[@]:-}" || USED_PUBLIC_PROTOCOL_PORTS+=("${entry}")
  done < <(list_listening_protocol_ports | sort -u)
}

reserve_used_protocol_port() {
  local protocol="$1"
  local port="$2"
  local key=""

  [[ -n "${protocol}" && -n "${port}" ]] || return 0
  [[ "${port}" =~ ^[0-9]+$ ]] || return 0
  key="${protocol}:${port}"
  array_contains "${key}" "${USED_PUBLIC_PROTOCOL_PORTS[@]:-}" || USED_PUBLIC_PROTOCOL_PORTS+=("${key}")
}

protocols_include() {
  local protocols="$1"
  local wanted="$2"
  local protocol=""

  while IFS= read -r protocol; do
    [[ "${protocol}" == "${wanted}" ]] && return 0
  done < <(protocol_items "${protocols}")
  return 1
}

port_is_available_for_protocols() {
  local port="$1"
  local protocols="$2"
  local protocol=""

  while IFS= read -r protocol; do
    array_contains "${protocol}:${port}" "${USED_PUBLIC_PROTOCOL_PORTS[@]:-}" && return 1
  done < <(protocol_items "${protocols}")
  return 0
}

range_is_available_for_protocols() {
  local range_start="$1"
  local range_end="$2"
  local protocols="$3"
  local entry=""
  local protocol=""
  local port=""

  for entry in "${USED_PUBLIC_PROTOCOL_PORTS[@]:-}"; do
    protocol="${entry%%:*}"
    port="${entry#*:}"
    [[ "${port}" =~ ^[0-9]+$ ]] || continue
    protocols_include "${protocols}" "${protocol}" || continue
    ((10#${port} >= 10#${range_start} && 10#${port} <= 10#${range_end})) && return 1
  done
  return 0
}

first_available_public_port() {
  local protocols="$1"
  shift
  local candidate=""

  for candidate in "$@"; do
    [[ -n "${candidate}" ]] || continue
    if port_is_available_for_protocols "${candidate}" "${protocols}"; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

print_available_public_ports() {
  local label="$1"
  local protocols="$2"
  shift 2
  local candidate=""
  local first="yes"

  printf '%s: ' "${label}"
  for candidate in "$@"; do
    if port_is_available_for_protocols "${candidate}" "${protocols}"; then
      [[ "${first}" == "yes" ]] || printf ', '
      printf '%s' "${candidate}"
      first="no"
    fi
  done
  [[ "${first}" == "no" ]] || printf 'none of the common choices are free'
  printf '\n'
}

first_available_allocation_range() {
  local protocols="$1"
  local range_start="${DEFAULT_ALLOCATION_RANGE_START}"
  local range_end=""

  while ((range_start <= DEFAULT_ALLOCATION_RANGE_END)); do
    range_end=$((range_start + DEFAULT_ALLOCATION_RANGE_SIZE - 1))
    ((range_end <= DEFAULT_ALLOCATION_RANGE_END)) || break
    if range_is_available_for_protocols "${range_start}" "${range_end}" "${protocols}"; then
      printf '%s-%s' "${range_start}" "${range_end}"
      return 0
    fi
    range_start=$((range_start + DEFAULT_ALLOCATION_RANGE_SIZE))
  done
  return 1
}

print_available_allocation_ranges() {
  local protocols="$1"
  local range_start="${DEFAULT_ALLOCATION_RANGE_START}"
  local range_end=""
  local printed="no"

  info "Available ${DEFAULT_ALLOCATION_RANGE_SIZE}-port allocation ranges on VM1/VPS1 (${protocols}; every port is free):"
  while ((range_start <= DEFAULT_ALLOCATION_RANGE_END)); do
    range_end=$((range_start + DEFAULT_ALLOCATION_RANGE_SIZE - 1))
    ((range_end <= DEFAULT_ALLOCATION_RANGE_END)) || break
    if range_is_available_for_protocols "${range_start}" "${range_end}" "${protocols}"; then
      info "  ${range_start}-${range_end}"
      printed="yes"
    fi
    range_start=$((range_start + DEFAULT_ALLOCATION_RANGE_SIZE))
  done
  [[ "${printed}" == "yes" ]] || warn "No fully free ${DEFAULT_ALLOCATION_RANGE_SIZE}-port allocation range was found."
}

protocol_port_is_listening() {
  local protocol="$1"
  local port="$2"

  case "${protocol}" in
    tcp) ss -Hltn "( sport = :${port} )" 2>/dev/null | grep -q . ;;
    udp) ss -Hlun "( sport = :${port} )" 2>/dev/null | grep -q . ;;
    *) fail "Unsupported protocol: ${protocol}" ;;
  esac
}

describe_port_usage() {
  local protocol="$1"
  local port="$2"

  case "${protocol}" in
    tcp) ss -ltnp "( sport = :${port} )" 2>/dev/null || true ;;
    udp) ss -lunp "( sport = :${port} )" 2>/dev/null || true ;;
  esac
  if command -v lsof >/dev/null 2>&1; then
    case "${protocol}" in
      tcp) lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true ;;
      udp) lsof -nP -iUDP:"${port}" 2>/dev/null || true ;;
    esac
  fi
}

ensure_protocol_port_is_free() {
  local protocol="$1"
  local port="$2"
  local protocol_label=""

  if protocol_port_is_listening "${protocol}" "${port}"; then
    protocol_label="$(printf '%s' "${protocol}" | tr '[:lower:]' '[:upper:]')"
    printf 'Detected %s listener on VM1/VPS1 port %s:\n' "${protocol_label}" "${port}" >&2
    describe_port_usage "${protocol}" "${port}" >&2 || true
    fail "Port ${port}/${protocol} is already in use."
  fi
}

add_forward_rule_to_host() {
  local target_host="$1"
  shift
  local name="$1"
  local listen_spec="$2"
  local target_spec="$3"
  local description="$4"
  local protocols="${5:-tcp}"
  local port=""
  local protocol=""
  local check_key=""

  validate_port_spec "${listen_spec}"
  validate_port_spec "${target_spec}"
  protocols="$(normalize_protocols "${protocols}")"

  if [[ "${listen_spec}" == *-* && "${target_spec}" != "${listen_spec}" ]]; then
    fail "Port range forwarding must use the same public and target range: ${listen_spec}:${target_spec}"
  fi

  while IFS= read -r port; do
    while IFS= read -r protocol; do
      check_key="${protocol}:${port}"
      if array_contains "${check_key}" "${FORWARD_LISTEN_CHECKS[@]:-}"; then
        fail "Duplicate public listen port requested: ${port}/${protocol}"
      fi
      FORWARD_LISTEN_CHECKS+=("${check_key}")
    done < <(protocol_items "${protocols}")
  done < <(expand_port_spec "${listen_spec}")

  FORWARD_RULE_NAMES+=("${name}")
  FORWARD_RULE_LISTEN_SPECS+=("${listen_spec}")
  FORWARD_RULE_TARGET_HOSTS+=("${target_host}")
  FORWARD_RULE_TARGET_SPECS+=("${target_spec}")
  FORWARD_RULE_PROTOCOLS+=("${protocols}")
  FORWARD_RULE_DESCRIPTIONS+=("${description}")
}

add_forward_rule() {
  add_forward_rule_to_host "${WG_VPS2_IP}" "$@"
}

prepare_forward_plan() {
  local game_port_spec=""
  local game_rule_name=""

  FORWARD_RULE_NAMES=()
  FORWARD_RULE_LISTEN_SPECS=()
  FORWARD_RULE_TARGET_HOSTS=()
  FORWARD_RULE_TARGET_SPECS=()
  FORWARD_RULE_PROTOCOLS=()
  FORWARD_RULE_DESCRIPTIONS=()
  FORWARD_LISTEN_CHECKS=()

  add_forward_rule "ssh-vps2" "${PUBLIC_SSH_FORWARD_PORT}" "${VPS2_SSH_PORT}" "Direct SSH to VM2/VPS2" "tcp"
  add_forward_rule "wings-vps2" "${WINGS_PUBLIC_PORT}" "${WINGS_TARGET_PORT}" "Pterodactyl Wings to VM2/VPS2" "tcp"
  add_forward_rule "sftp-vps2" "${SFTP_PUBLIC_PORT}" "${SFTP_TARGET_PORT}" "Pterodactyl SFTP to VM2/VPS2" "tcp"

  for game_port_spec in "${GAME_PORT_RANGE_LIST[@]}"; do
    game_rule_name="game-vps2-${game_port_spec//[^0-9]/-}"
    add_forward_rule "${game_rule_name}" "${game_port_spec}" "${game_port_spec}" "Game/allocation range to VM2/VPS2" "tcp,udp"
  done

  add_extra_peer_forward_rules
}

add_extra_peer_forward_rules() {
  local peer_file=""
  local SSH_PEER_NAME=""
  local SSH_PEER_WG_IP=""
  local SSH_PEER_PUBLIC_SSH_PORT=""
  local SSH_PEER_SSH_PORT=""
  local SSH_PEER_WINGS_PUBLIC_PORT=""
  local SSH_PEER_WINGS_TARGET_PORT=""
  local SSH_PEER_SFTP_PUBLIC_PORT=""
  local SSH_PEER_SFTP_TARGET_PORT=""
  local SSH_PEER_GAME_PORTS_RAW=""
  local token=""
  local listen_spec=""
  local target_spec=""
  local rule_name=""

  [[ -d "$(ssh_peer_state_dir)" ]] || return 0

  for peer_file in "$(ssh_peer_state_dir)"/*.env; do
    [[ -f "${peer_file}" ]] || continue
    SSH_PEER_NAME=""
    SSH_PEER_WG_IP=""
    SSH_PEER_PUBLIC_SSH_PORT=""
    SSH_PEER_SSH_PORT=""
    SSH_PEER_WINGS_PUBLIC_PORT=""
    SSH_PEER_WINGS_TARGET_PORT=""
    SSH_PEER_SFTP_PUBLIC_PORT=""
    SSH_PEER_SFTP_TARGET_PORT=""
    SSH_PEER_GAME_PORTS_RAW=""
    # shellcheck disable=SC1090
    . "${peer_file}"
    [[ -n "${SSH_PEER_NAME}" && -n "${SSH_PEER_WG_IP}" && -n "${SSH_PEER_PUBLIC_SSH_PORT}" ]] || continue
    SSH_PEER_SSH_PORT="${SSH_PEER_SSH_PORT:-22}"

    add_forward_rule_to_host "${SSH_PEER_WG_IP}" "ssh-${SSH_PEER_NAME}" "${SSH_PEER_PUBLIC_SSH_PORT}" "${SSH_PEER_SSH_PORT}" "Direct SSH to ${SSH_PEER_NAME}" "tcp"

    if [[ -n "${SSH_PEER_WINGS_PUBLIC_PORT}" || -n "${SSH_PEER_WINGS_TARGET_PORT}" ]]; then
      [[ -n "${SSH_PEER_WINGS_PUBLIC_PORT}" && -n "${SSH_PEER_WINGS_TARGET_PORT}" ]] || fail "Peer ${SSH_PEER_NAME} has incomplete Wings settings."
      add_forward_rule_to_host "${SSH_PEER_WG_IP}" "wings-${SSH_PEER_NAME}" "${SSH_PEER_WINGS_PUBLIC_PORT}" "${SSH_PEER_WINGS_TARGET_PORT}" "Pterodactyl Wings to ${SSH_PEER_NAME}" "tcp"
    fi

    if [[ -n "${SSH_PEER_SFTP_PUBLIC_PORT}" || -n "${SSH_PEER_SFTP_TARGET_PORT}" ]]; then
      [[ -n "${SSH_PEER_SFTP_PUBLIC_PORT}" && -n "${SSH_PEER_SFTP_TARGET_PORT}" ]] || fail "Peer ${SSH_PEER_NAME} has incomplete SFTP settings."
      add_forward_rule_to_host "${SSH_PEER_WG_IP}" "sftp-${SSH_PEER_NAME}" "${SSH_PEER_SFTP_PUBLIC_PORT}" "${SSH_PEER_SFTP_TARGET_PORT}" "Pterodactyl SFTP to ${SSH_PEER_NAME}" "tcp"
    fi

    for token in ${SSH_PEER_GAME_PORTS_RAW//,/ }; do
      [[ -n "${token}" ]] || continue
      split_peer_game_port_token "${token}" listen_spec target_spec
      rule_name="game-${SSH_PEER_NAME}-${listen_spec//[^0-9]/-}"
      add_forward_rule_to_host "${SSH_PEER_WG_IP}" "${rule_name}" "${listen_spec}" "${target_spec}" "Game/allocation range to ${SSH_PEER_NAME}" "tcp,udp"
    done
  done
}

write_forwarder_script() {
  mkdir -p /usr/local/lib/cakessh
  cat > "$(forwarder_script_path)" <<'EOF'
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

normalize_protocols() {
  local raw="${1:-tcp}"
  local cleaned="${raw//,/ }"
  local token=""
  local output=""

  for token in ${cleaned}; do
    case "${token}" in
      all)
        case ",${output}," in *",tcp,"*) ;; *) output="${output:+${output},}tcp" ;; esac
        case ",${output}," in *",udp,"*) ;; *) output="${output:+${output},}udp" ;; esac
        ;;
      tcp|udp)
        case ",${output}," in *",${token},"*) ;; *) output="${output:+${output},}${token}" ;; esac
        ;;
      *)
        printf 'Unsupported protocol: %s\n' "${token}" >&2
        exit 1
        ;;
    esac
  done

  [[ -n "${output}" ]] || {
    printf 'At least one protocol is required.\n' >&2
    exit 1
  }
  printf '%s' "${output}"
}

protocol_items() {
  local protocols="$1"
  local token=""

  for token in ${protocols//,/ }; do
    [[ -n "${token}" ]] || continue
    printf '%s\n' "${token}"
  done
}

parse_forward_rule_value() {
  local rule_value="$1"
  local field3=""
  local field4=""
  local field5=""
  local field6=""
  local field7=""

  IFS='|' read -r PARSED_NAME PARSED_LISTEN_SPEC field3 field4 field5 field6 field7 <<< "${rule_value}"
  if [[ -n "${field6}" || "${field5}" == "tcp" || "${field5}" == "udp" || "${field5}" == "tcp,udp" || "${field5}" == "udp,tcp" || "${field5}" == "all" ]]; then
    PARSED_TARGET_HOST="${field3}"
    PARSED_TARGET_SPEC="${field4}"
    PARSED_PROTOCOLS="$(normalize_protocols "${field5:-tcp}")"
    PARSED_DESCRIPTION="${field6}"
  else
    PARSED_TARGET_HOST="${field3}"
    PARSED_TARGET_SPEC="${field4}"
    PARSED_PROTOCOLS="tcp"
    PARSED_DESCRIPTION="${field5}"
  fi
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
  local protocol=""
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

    parse_forward_rule_value "${rule_value}"
    listen_iptables_spec="$(to_iptables_spec "${PARSED_LISTEN_SPEC}")"
    target_iptables_spec="$(to_iptables_spec "${PARSED_TARGET_SPEC}")"
    if [[ "${PARSED_TARGET_SPEC}" == *-* ]]; then
      target_destination="${PARSED_TARGET_HOST}"
    else
      target_destination="${PARSED_TARGET_HOST}:${PARSED_TARGET_SPEC}"
    fi

    while IFS= read -r protocol; do
      "${IPTABLES_BIN}" -t nat -A CAKESSH_SNAT -o "${WG_INTERFACE}" -p "${protocol}" -d "${PARSED_TARGET_HOST}" -j MASQUERADE
      "${IPTABLES_BIN}" -t nat -A CAKESSH_DNAT -p "${protocol}" -d "${VPS1_IPV4}" --dport "${listen_iptables_spec}" -j DNAT --to-destination "${target_destination}"
      "${IPTABLES_BIN}" -t filter -A CAKESSH_FORWARD -o "${WG_INTERFACE}" -p "${protocol}" -d "${PARSED_TARGET_HOST}" --dport "${target_iptables_spec}" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
    done < <(protocol_items "${PARSED_PROTOCOLS}")
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
  chmod 0755 "$(forwarder_script_path)"
}

write_forwarder_unit() {
  cat > "/etc/systemd/system/$(forwarder_service_name)" <<EOF
[Unit]
Description=cakessh TCP/UDP public relay
After=network-online.target $(wireguard_service_name)
Wants=network-online.target $(wireguard_service_name)

[Service]
Type=oneshot
ExecStart=$(forwarder_script_path) up
ExecReload=$(forwarder_script_path) up
ExecStop=$(forwarder_script_path) down
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
    printf 'FORWARD_RULE_COUNT=%q\n' "${#FORWARD_RULE_NAMES[@]}"
    for index in "${!FORWARD_RULE_NAMES[@]}"; do
      rule_value="${FORWARD_RULE_NAMES[$index]}|${FORWARD_RULE_LISTEN_SPECS[$index]}|${FORWARD_RULE_TARGET_HOSTS[$index]}|${FORWARD_RULE_TARGET_SPECS[$index]}|${FORWARD_RULE_PROTOCOLS[$index]}|${FORWARD_RULE_DESCRIPTIONS[$index]}"
      printf 'FORWARD_RULE_%s=%q\n' "$((index + 1))" "${rule_value}"
    done
  } > "$(forwarder_config_path)"
  chmod 0600 "$(forwarder_config_path)"
}

write_ip_forward_sysctl() {
  printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-cakessh-ip-forward.conf
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
}

upsert_forwarder_service() {
  local service_name=""
  service_name="$(forwarder_service_name)"

  systemctl daemon-reload
  systemctl enable --now "${service_name}"
  systemctl restart "${service_name}"
  systemctl is-active --quiet "${service_name}" || fail "Forwarder service failed to start: ${service_name}"
}

forwarded_public_port_protocol_specs() {
  local index=""
  local listen_spec=""
  local protocols=""
  local protocol=""
  local key=""
  local -a seen=()

  for index in "${!FORWARD_RULE_NAMES[@]}"; do
    listen_spec="${FORWARD_RULE_LISTEN_SPECS[$index]}"
    protocols="${FORWARD_RULE_PROTOCOLS[$index]}"
    while IFS= read -r protocol; do
      key="${protocol}:${listen_spec}"
      if ! array_contains "${key}" "${seen[@]:-}"; then
        seen+=("${key}")
        printf '%s\n' "${key}"
      fi
    done < <(protocol_items "${protocols}")
  done
}

format_protocol_port_spec() {
  local protocol_port_spec="$1"
  local protocol="${protocol_port_spec%%:*}"
  local port_spec="${protocol_port_spec#*:}"
  printf '%s/%s' "$(iptables_port_spec "${port_spec}")" "${protocol}"
}

forwarded_public_port_protocol_specs_csv() {
  local item=""
  local -a output=()

  while IFS= read -r item; do
    [[ -n "${item}" ]] && output+=("$(format_protocol_port_spec "${item}")")
  done < <(forwarded_public_port_protocol_specs)
  join_by_comma "${output[@]:-}"
}

configure_ufw() {
  local protocol_port_spec=""
  local protocol=""
  local port_spec=""
  local ufw_port_spec=""
  local public_ports=""

  public_ports="$(forwarded_public_port_protocol_specs_csv)"

  if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw is not installed. Open manually: ${public_ports} and ${WG_PORT}/udp"
    return 0
  fi

  if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    warn "ufw is not active. Open manually if another firewall is used: ${public_ports} and ${WG_PORT}/udp"
    return 0
  fi

  ufw allow "${WG_PORT}/udp" >/dev/null
  while IFS= read -r protocol_port_spec; do
    [[ -n "${protocol_port_spec}" ]] || continue
    protocol="${protocol_port_spec%%:*}"
    port_spec="${protocol_port_spec#*:}"
    ufw_port_spec="$(iptables_port_spec "${port_spec}")"
    ufw allow "${ufw_port_spec}/${protocol}" >/dev/null
  done < <(forwarded_public_port_protocol_specs)
}

configure_wireguard_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw is not installed. Make sure UDP ${WG_PORT}/udp is open on VM1/VPS1."
    return 0
  fi
  if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    warn "ufw is not active. Make sure UDP ${WG_PORT}/udp is open on VM1/VPS1."
    return 0
  fi
  ufw allow "${WG_PORT}/udp" >/dev/null
}

configure_backend_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw is not installed. Allow traffic from ${WG_VPS1_IP} on ${WG_INTERFACE} if another firewall is enabled."
    return 0
  fi
  if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    warn "ufw is not active. Allow traffic from ${WG_VPS1_IP} on ${WG_INTERFACE} if another firewall is enabled."
    return 0
  fi
  ufw allow in on "${WG_INTERFACE}" from "${WG_VPS1_IP}" >/dev/null
}

validate_forward_ports_are_free() {
  local item=""
  local protocol=""
  local port=""

  refresh_listening_public_ports
  for item in "${FORWARD_LISTEN_CHECKS[@]:-}"; do
    protocol="${item%%:*}"
    port="${item#*:}"
    if array_contains "${item}" "${USED_PUBLIC_PROTOCOL_PORTS[@]:-}"; then
      describe_port_usage "${protocol}" "${port}" >&2 || true
      fail "Port ${port}/${protocol} is already in use on VM1/VPS1."
    fi
  done
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

  while ((attempt < max_attempts)); do
    ping_ok="no"
    if command -v ping >/dev/null 2>&1 && ping -c 1 -W 2 "${WG_VPS2_IP}" >/dev/null 2>&1; then
      ping_ok="yes"
    fi

    if command -v nc >/dev/null 2>&1; then
      if nc -z -w 2 "${WG_VPS2_IP}" "${VPS2_SSH_PORT}" >/dev/null 2>&1; then
        VPS2_SSH_REACHABLE="yes"
        return 0
      fi
      if [[ "${ping_ok}" == "yes" ]]; then
        VPS2_SSH_REACHABLE="no"
        warn "WireGuard is up, but VM2/VPS2 SSH port ${VPS2_SSH_PORT} is unreachable. Direct SSH may fail until sshd is listening."
        return 0
      fi
    elif [[ "${ping_ok}" == "yes" ]]; then
      return 0
    fi

    if wireguard_peer_has_handshake; then
      warn "A WireGuard handshake exists, so continuing even though ping/SSH did not pass yet."
      return 0
    fi

    attempt=$((attempt + 1))
    ((attempt < max_attempts)) || break
    info "  WireGuard not ready yet (${attempt}/${max_attempts}). Retrying in 2 seconds..."
    sleep 2
  done

  fail "VM1/VPS1 cannot reach ${WG_VPS2_IP}. Make sure VM2/VPS2 finished install and UDP ${WG_PORT}/udp is open on VM1/VPS1."
}

client_ssh_dir() { printf '%s/.ssh' "${CLIENT_INSTALL_HOME}"; }
client_ssh_config_path() { printf '%s/config' "$(client_ssh_dir)"; }
client_ssh_config_dropin_dir() { printf '%s/config.d' "$(client_ssh_dir)"; }
client_ssh_config_dropin_path() { printf '%s/cakessh.conf' "$(client_ssh_config_dropin_dir)"; }

write_client_config() {
  local config_file="$1"
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
    printf 'CAKESSH_WINGS_PUBLIC_PORT=%q\n' "${WINGS_PUBLIC_PORT}"
    printf 'CAKESSH_SFTP_PUBLIC_PORT=%q\n' "${SFTP_PUBLIC_PORT}"
    printf 'CAKESSH_GAME_PORTS=%q\n' "${GAME_PORTS_CANONICAL}"
    printf 'CAKESSH_WG_INTERFACE=%q\n' "${WG_INTERFACE}"
  } > "${config_file}"
  chmod 0600 "${config_file}"
}

ensure_client_ssh_include() {
  local ssh_dir=""
  local main_config=""

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
  local alias_config=""
  alias_config="$(client_ssh_config_dropin_path)"
  mkdir -p "$(dirname "${alias_config}")"

  {
    printf 'Host cakessh-vps2\n'
    printf '  HostName %s\n' "${VPS2_HOST}"
    printf '  User %s\n' "${VPS2_USER}"
    printf '  Port %s\n' "${VPS2_SSH_PORT}"
    printf '  ProxyJump %s@%s:%s\n' "${VPS1_USER}" "${VPS1_IPV4}" "${VPS1_SSH_PORT}"
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
  local bin_dir=""
  local config_dir=""
  local helper_target=""
  local config_target=""

  progress 1 4 "Preparing client install"
  [[ -f "${HELPER_SOURCE}" ]] || fail "Helper script not found: ${HELPER_SOURCE}"
  ensure_ssh_client
  determine_client_home
  [[ -n "${IDENTITY_FILE}" && ! -f "${IDENTITY_FILE}" ]] && fail "Identity file not found: ${IDENTITY_FILE}"
  normalize_wireguard_addresses
  normalize_game_ports

  bin_dir="${CLIENT_INSTALL_HOME}/.local/bin"
  config_dir="${CLIENT_INSTALL_HOME}/.config/cakessh"
  helper_target="${bin_dir}/cakessh"
  config_target="${config_dir}/client.env"

  progress 2 4 "Installing helper and config"
  mkdir -p "${bin_dir}" "${config_dir}"
  install -m 0755 "${HELPER_SOURCE}" "${helper_target}"
  write_client_config "${config_target}"

  progress 3 4 "Writing SSH aliases"
  ensure_client_ssh_include
  write_client_ssh_alias_config

  if [[ "${EUID}" -eq 0 && "${CLIENT_INSTALL_USER}" != "root" ]]; then
    chown "${CLIENT_INSTALL_USER}" \
      "${CLIENT_INSTALL_HOME}/.local" "${bin_dir}" \
      "${CLIENT_INSTALL_HOME}/.config" "${config_dir}" \
      "$(client_ssh_dir)" "$(client_ssh_config_dropin_dir)" \
      "$(client_ssh_config_path)" "$(client_ssh_config_dropin_path)" \
      "${helper_target}" "${config_target}" 2>/dev/null || true
  fi

  progress 4 4 "Client install finished"
  info "Helper: ${helper_target}"
  info "Config: ${config_target}"
  info "Try: cakessh status"
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
}

validate_client_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_ipv4_basic "${VPS1_IPV4}"
  validate_port "${VPS1_SSH_PORT}"
  validate_port "${VPS2_SSH_PORT}"
  validate_port "${PUBLIC_SSH_FORWARD_PORT}"
  validate_wings_scheme
  validate_port "${WINGS_PUBLIC_PORT}"
  validate_port "${WINGS_TARGET_PORT}"
  validate_port "${SFTP_PUBLIC_PORT}"
  validate_port "${SFTP_TARGET_PORT}"
  normalize_game_ports
}

validate_vps1_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_ipv4_basic "${VPS1_IPV4}"
  validate_port "${VPS2_SSH_PORT}"
  validate_port "${PUBLIC_SSH_FORWARD_PORT}"
  validate_wings_scheme
  validate_port "${WINGS_PUBLIC_PORT}"
  validate_port "${WINGS_TARGET_PORT}"
  validate_port "${SFTP_PUBLIC_PORT}"
  validate_port "${SFTP_TARGET_PORT}"
  normalize_game_ports
  validate_watchdog_settings
  validate_wireguard_public_key_if_present "${WG_VPS2_PUBLIC_KEY}"
}

validate_vps2_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_ipv4_basic "${VPS1_IPV4}"
  validate_watchdog_settings
  validate_wireguard_public_key_if_present "${WG_VPS1_PUBLIC_KEY}"
  [[ -n "${WG_VPS1_PUBLIC_KEY}" ]] || fail "VM2/VPS2 needs the VM1/VPS1 public key."
}

validate_peer_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_peer_name
  validate_ipv4_basic "${VPS1_IPV4}"
  validate_watchdog_settings
  validate_wireguard_public_key_if_present "${WG_VPS1_PUBLIC_KEY}"
  [[ -n "${WG_VPS1_PUBLIC_KEY}" ]] || fail "Peer needs the VM1/VPS1 public key."
}

validate_vps1_add_peer_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_peer_name
  validate_ipv4_basic "${VPS1_IPV4}"
  validate_port "${PEER_SSH_PORT}"
  validate_port "${PEER_PUBLIC_SSH_PORT}"
  validate_peer_wings_settings
  validate_peer_sftp_settings
  validate_peer_game_ports
  validate_watchdog_settings
  normalize_game_ports
  validate_wireguard_public_key_if_present "${WG_PEER_PUBLIC_KEY}"
  [[ -n "${WG_PEER_PUBLIC_KEY}" ]] || fail "vps1-add-peer needs the peer public key."
}

prompt_install_inputs() {
  local detected_vps1_ipv4=""
  local suggested_wings_port=""
  local suggested_sftp_port=""
  local suggested_game_ports=""

  if [[ "${ROLE}" == "all" || "${ROLE}" == "vps1" ]]; then
    detected_vps1_ipv4="$(detect_primary_ipv4 || true)"
  fi

  if [[ "${ROLE}" == "client" || "${ROLE}" == "all" || "${ROLE}" == "vps1" || "${ROLE}" == "vps2" || "${ROLE}" == "peer" || "${ROLE}" == "vps1-add-peer" ]]; then
    prompt_value VPS1_IPV4 "VM1/VPS1 public IPv4 address" "${detected_vps1_ipv4}"
  fi

  if [[ "${ROLE}" == "client" || "${ROLE}" == "all" ]]; then
    prompt_value VPS1_USER "VM1/VPS1 SSH username" "${DEFAULT_VPS1_USER}"
    prompt_value VPS1_SSH_PORT "VM1/VPS1 SSH port" "${DEFAULT_VPS1_SSH_PORT}"
    prompt_value VPS2_USER "VM2/VPS2 SSH username" "${DEFAULT_VPS2_USER}"
    prompt_value VPS2_SSH_PORT "VM2/VPS2 SSH port" "${DEFAULT_VPS2_SSH_PORT}"
    prompt_value WG_VPS2_ADDRESS "VM2/VPS2 WireGuard address" "${DEFAULT_WG_VPS2_ADDRESS}"
    if [[ -z "${IDENTITY_FILE}" ]] && prompt_yes_no "Use an SSH key for cakessh connect?" "n"; then
      prompt_value IDENTITY_FILE "Path to SSH key" ""
    fi
  fi

  if [[ "${ROLE}" == "vps1" || "${ROLE}" == "all" ]]; then
    prompt_value VPS2_USER "VM2/VPS2 SSH username for direct SSH" "${DEFAULT_VPS2_USER}"
    prompt_value VPS2_SSH_PORT "VM2/VPS2 SSH port" "${DEFAULT_VPS2_SSH_PORT}"
    prompt_value PUBLIC_SSH_FORWARD_PORT "Public SSH port on VM1/VPS1 for VM2/VPS2" "${DEFAULT_PUBLIC_SSH_FORWARD_PORT}"
    prompt_value WG_INTERFACE "WireGuard interface name" "${DEFAULT_WG_INTERFACE}"
    prompt_value WG_PORT "WireGuard UDP port on VM1/VPS1" "${DEFAULT_WG_PORT}"
    prompt_value WG_VPS1_ADDRESS "VM1/VPS1 WireGuard address" "${DEFAULT_WG_VPS1_ADDRESS}"
    prompt_value WG_VPS2_ADDRESS "VM2/VPS2 WireGuard address" "${DEFAULT_WG_VPS2_ADDRESS}"

    if [[ -z "${WG_VPS2_PUBLIC_KEY}" ]] && prompt_yes_no "Do you already have the VM2/VPS2 WireGuard public key?" "n"; then
      prompt_optional_value WG_VPS2_PUBLIC_KEY "Paste VM2/VPS2 WireGuard public key"
    fi

    if [[ -z "${WINGS_SCHEME}" ]]; then
      if prompt_yes_no "Expose Wings over HTTPS?" "n"; then
        WINGS_SCHEME="https"
      else
        WINGS_SCHEME="http"
      fi
    fi

    if stdin_is_tty && [[ -z "${WINGS_PUBLIC_PORT}" || -z "${SFTP_PUBLIC_PORT}" || -z "${GAME_PORTS_RAW}" ]]; then
      refresh_used_public_ports
      reserve_used_protocol_port "tcp" "${PUBLIC_SSH_FORWARD_PORT}"
      info ""
      print_available_public_ports "Available Wings daemon public ports on VM1/VPS1" "tcp" ${DEFAULT_WINGS_PUBLIC_PORT_CANDIDATES}
      print_available_public_ports "Available Wings SFTP public ports on VM1/VPS1" "tcp" ${DEFAULT_SFTP_PUBLIC_PORT_CANDIDATES}
      [[ -n "${GAME_PORTS_RAW}" ]] || print_available_allocation_ranges "tcp,udp"
      info ""
    fi

    suggested_wings_port="$(first_available_public_port "tcp" ${DEFAULT_WINGS_PUBLIC_PORT_CANDIDATES} 2>/dev/null || true)"
    suggested_sftp_port="$(first_available_public_port "tcp" ${DEFAULT_SFTP_PUBLIC_PORT_CANDIDATES} 2>/dev/null || true)"
    suggested_game_ports="$(first_available_allocation_range "tcp,udp" 2>/dev/null || true)"

    prompt_value WINGS_PUBLIC_PORT "Public Wings daemon port on VM1/VPS1" "${suggested_wings_port:-$(default_wings_port)}"
    prompt_value WINGS_TARGET_PORT "Wings daemon port on VM2/VPS2" "$(default_wings_port)"
    prompt_value SFTP_PUBLIC_PORT "Public Wings SFTP port on VM1/VPS1" "${suggested_sftp_port:-${DEFAULT_SFTP_PUBLIC_PORT}}"
    prompt_value SFTP_TARGET_PORT "Wings SFTP port on VM2/VPS2" "${DEFAULT_SFTP_TARGET_PORT}"
    prompt_value GAME_PORTS_RAW "Game/allocation range to forward (TCP+UDP)" "${suggested_game_ports:-${DEFAULT_GAME_PORTS_RAW}}"
  fi

  if [[ "${ROLE}" == "vps2" ]]; then
    prompt_value WG_INTERFACE "WireGuard interface name" "${DEFAULT_WG_INTERFACE}"
    prompt_value WG_PORT "WireGuard UDP port on VM1/VPS1" "${DEFAULT_WG_PORT}"
    prompt_value WG_VPS1_ADDRESS "VM1/VPS1 WireGuard address" "${DEFAULT_WG_VPS1_ADDRESS}"
    prompt_value WG_VPS2_ADDRESS "VM2/VPS2 WireGuard address" "${DEFAULT_WG_VPS2_ADDRESS}"
    prompt_value WG_VPS1_PUBLIC_KEY "VM1/VPS1 WireGuard public key" ""
  fi

  if [[ "${ROLE}" == "peer" ]]; then
    prompt_value PEER_NAME "Peer name, for example vps3" "vps3"
    prompt_value WG_INTERFACE "WireGuard interface name" "${DEFAULT_WG_INTERFACE}"
    prompt_value WG_PORT "WireGuard UDP port on VM1/VPS1" "${DEFAULT_WG_PORT}"
    prompt_value WG_VPS1_ADDRESS "VM1/VPS1 WireGuard address" "${DEFAULT_WG_VPS1_ADDRESS}"
    prompt_value WG_PEER_ADDRESS "This peer WireGuard address" "${DEFAULT_WG_PEER_ADDRESS}"
    prompt_value WG_VPS1_PUBLIC_KEY "VM1/VPS1 WireGuard public key" ""
  fi

  if [[ "${ROLE}" == "vps1-add-peer" ]]; then
    prompt_value PEER_NAME "Peer name, for example vps3" "vps3"
    prompt_value PEER_USER "Peer SSH username" "${DEFAULT_PEER_USER}"
    prompt_value PEER_SSH_PORT "Peer SSH port" "${DEFAULT_PEER_SSH_PORT}"
    prompt_value PEER_PUBLIC_SSH_PORT "Public SSH port on VM1/VPS1 for this peer" "${DEFAULT_PEER_PUBLIC_SSH_PORT}"
    prompt_value WG_INTERFACE "WireGuard interface name" "${DEFAULT_WG_INTERFACE}"
    prompt_value WG_PORT "WireGuard UDP port on VM1/VPS1" "${DEFAULT_WG_PORT}"
    prompt_value WG_VPS1_ADDRESS "VM1/VPS1 WireGuard address" "${DEFAULT_WG_VPS1_ADDRESS}"
    prompt_value WG_PEER_ADDRESS "Peer WireGuard address" "${DEFAULT_WG_PEER_ADDRESS}"

    if [[ -z "${PEER_WINGS_PUBLIC_PORT}" && -z "${PEER_WINGS_TARGET_PORT}" ]] && prompt_yes_no "Forward Pterodactyl Wings to this peer?" "y"; then
      refresh_used_public_ports
      reserve_used_protocol_port "tcp" "${PEER_PUBLIC_SSH_PORT}"
      print_available_public_ports "Available Wings daemon public ports on VM1/VPS1" "tcp" ${DEFAULT_PEER_WINGS_PUBLIC_PORT_CANDIDATES}
      suggested_wings_port="$(first_available_public_port "tcp" ${DEFAULT_PEER_WINGS_PUBLIC_PORT_CANDIDATES} 2>/dev/null || true)"
      prompt_value PEER_WINGS_PUBLIC_PORT "Public Wings daemon port on VM1/VPS1 for this peer" "${suggested_wings_port:-${DEFAULT_PEER_WINGS_PUBLIC_PORT}}"
      prompt_value PEER_WINGS_TARGET_PORT "Wings daemon port on this peer" "${DEFAULT_PEER_WINGS_TARGET_PORT}"
    elif [[ -n "${PEER_WINGS_PUBLIC_PORT}" || -n "${PEER_WINGS_TARGET_PORT}" ]]; then
      prompt_value PEER_WINGS_PUBLIC_PORT "Public Wings daemon port on VM1/VPS1 for this peer" "${DEFAULT_PEER_WINGS_PUBLIC_PORT}"
      prompt_value PEER_WINGS_TARGET_PORT "Wings daemon port on this peer" "${DEFAULT_PEER_WINGS_TARGET_PORT}"
    fi

    if [[ -z "${PEER_SFTP_PUBLIC_PORT}" && -z "${PEER_SFTP_TARGET_PORT}" ]] && prompt_yes_no "Forward Pterodactyl SFTP to this peer?" "y"; then
      refresh_used_public_ports
      reserve_used_protocol_port "tcp" "${PEER_PUBLIC_SSH_PORT}"
      reserve_used_protocol_port "tcp" "${PEER_WINGS_PUBLIC_PORT}"
      print_available_public_ports "Available Wings SFTP public ports on VM1/VPS1" "tcp" ${DEFAULT_PEER_SFTP_PUBLIC_PORT_CANDIDATES}
      suggested_sftp_port="$(first_available_public_port "tcp" ${DEFAULT_PEER_SFTP_PUBLIC_PORT_CANDIDATES} 2>/dev/null || true)"
      prompt_value PEER_SFTP_PUBLIC_PORT "Public Wings SFTP port on VM1/VPS1 for this peer" "${suggested_sftp_port:-${DEFAULT_PEER_SFTP_PUBLIC_PORT}}"
      prompt_value PEER_SFTP_TARGET_PORT "Wings SFTP port on this peer" "${DEFAULT_PEER_SFTP_TARGET_PORT}"
    elif [[ -n "${PEER_SFTP_PUBLIC_PORT}" || -n "${PEER_SFTP_TARGET_PORT}" ]]; then
      prompt_value PEER_SFTP_PUBLIC_PORT "Public Wings SFTP port on VM1/VPS1 for this peer" "${DEFAULT_PEER_SFTP_PUBLIC_PORT}"
      prompt_value PEER_SFTP_TARGET_PORT "Wings SFTP port on this peer" "${DEFAULT_PEER_SFTP_TARGET_PORT}"
    fi

    if [[ -z "${PEER_GAME_PORTS_RAW}" ]] && prompt_yes_no "Forward game/allocation ports to this peer?" "y"; then
      refresh_used_public_ports
      reserve_used_protocol_port "tcp" "${PEER_PUBLIC_SSH_PORT}"
      reserve_used_protocol_port "tcp" "${PEER_WINGS_PUBLIC_PORT}"
      reserve_used_protocol_port "tcp" "${PEER_SFTP_PUBLIC_PORT}"
      print_available_allocation_ranges "tcp,udp"
      suggested_game_ports="$(first_available_allocation_range "tcp,udp" 2>/dev/null || true)"
      prompt_value PEER_GAME_PORTS_RAW "Peer allocation forwards (TCP+UDP public[:target])" "${suggested_game_ports:-}"
    fi

    prompt_value WG_PEER_PUBLIC_KEY "Peer WireGuard public key" ""
  fi
}

print_vps1_bootstrap_summary() {
  info ""
  info "VM1/VPS1 WireGuard bootstrap complete."
  info "Autostart enabled: $(wireguard_service_name)"
  info ""
  info "Next:"
  info "  sudo bash install.sh show-key vps1"
  info "  sudo bash install.sh vps2 --vps1-ipv4 ${VPS1_IPV4}"
  info "  sudo bash install.sh show-key vps2"
  info "  sudo bash install.sh vps1"
}

install_vps1() {
  local first_game_port=""
  local peer_ips=""

  progress 1 5 "Preparing VM1/VPS1"
  require_root
  validate_vps1_inputs
  ensure_supported_linux
  ensure_systemd
  ensure_packages wireguard-tools iptables iproute2 iputils-ping

  progress 2 5 "Installing WireGuard"
  generate_wireguard_keys "vps1"
  write_vps1_wireguard_config
  upsert_wireguard_service
  configure_wireguard_firewall
  save_install_state

  if [[ -z "${WG_VPS2_PUBLIC_KEY}" ]]; then
    progress 3 5 "Waiting for VM2/VPS2 public key"
    print_vps1_bootstrap_summary
    return 0
  fi

  peer_ips="$(collect_watchdog_peer_ips)"
  upsert_watchdog "${peer_ips}"

  progress 3 5 "Checking WireGuard reachability"
  ensure_wireguard_backend_reachability
  prepare_forward_plan
  validate_forward_ports_are_free

  progress 4 5 "Installing TCP/UDP forwarder"
  write_ip_forward_sysctl
  write_forwarder_script
  write_forwarder_unit
  write_forwarder_config
  upsert_forwarder_service
  configure_ufw
  save_install_state

  progress 5 5 "VM1/VPS1 setup finished"
  first_game_port="${GAME_PORT_LIST[0]}"
  info ""
  info "Direct SSH: ssh -p ${PUBLIC_SSH_FORWARD_PORT} ${VPS2_USER}@${VPS1_IPV4}"
  info "Wings: ${WINGS_SCHEME}://${VPS1_IPV4}:${WINGS_PUBLIC_PORT} -> ${WG_VPS2_IP}:${WINGS_TARGET_PORT}"
  info "SFTP: sftp -P ${SFTP_PUBLIC_PORT} ${VPS2_USER}@${VPS1_IPV4} -> ${WG_VPS2_IP}:${SFTP_TARGET_PORT}"
  info "Game/allocation ranges: ${GAME_PORTS_CANONICAL} (TCP+UDP)"
  info "Quick TCP test: nc -vz ${VPS1_IPV4} ${first_game_port}"
  info "Watchdog: $(watchdog_timer_name) pings peers every minute and restarts stale tunnels after ${WG_WATCHDOG_STALE_SECONDS}s"
}

install_vps2() {
  progress 1 4 "Preparing VM2/VPS2"
  require_root
  validate_vps2_inputs
  ensure_supported_linux
  ensure_systemd
  ensure_packages wireguard-tools iproute2 iputils-ping

  progress 2 4 "Installing WireGuard"
  generate_wireguard_keys "vps2"
  write_vps2_wireguard_config
  upsert_wireguard_service

  progress 3 4 "Installing keepalive watchdog"
  upsert_watchdog "${WG_VPS1_IP}"
  configure_backend_firewall
  save_install_state

  progress 4 4 "VM2/VPS2 setup finished"
  info "Show this key on VM2/VPS2: sudo bash install.sh show-key vps2"
  info "Then rerun on VM1/VPS1: sudo bash install.sh vps1"
}

install_peer() {
  progress 1 4 "Preparing ${PEER_NAME}"
  require_root
  validate_peer_inputs
  ensure_supported_linux
  ensure_systemd
  ensure_packages wireguard-tools iproute2 iputils-ping

  progress 2 4 "Installing WireGuard"
  generate_wireguard_keys "peer"
  write_peer_wireguard_config
  upsert_wireguard_service

  progress 3 4 "Installing keepalive watchdog"
  upsert_watchdog "${WG_VPS1_IP}"
  configure_backend_firewall
  save_install_state

  progress 4 4 "${PEER_NAME} setup finished"
  info "Show this key on the peer: sudo bash install.sh show-key peer"
  info "Then add it on VM1/VPS1: sudo bash install.sh vps1-add-peer --peer-name ${PEER_NAME} --wg-peer-address ${WG_PEER_ADDRESS}"
}

install_vps1_add_peer() {
  local peer_ips=""

  progress 1 4 "Preparing VM1/VPS1 peer entry"
  require_root
  validate_vps1_add_peer_inputs
  ensure_supported_linux
  ensure_systemd
  ensure_packages wireguard-tools iptables iproute2 iputils-ping

  progress 2 4 "Adding ${PEER_NAME} to WireGuard"
  generate_wireguard_keys "vps1"
  save_ssh_peer_state
  write_vps1_wireguard_config
  upsert_wireguard_service
  configure_wireguard_firewall
  peer_ips="$(collect_watchdog_peer_ips)"
  upsert_watchdog "${peer_ips}"

  progress 3 4 "Refreshing TCP/UDP forwarder"
  prepare_forward_plan
  validate_forward_ports_are_free
  write_ip_forward_sysctl
  write_forwarder_script
  write_forwarder_unit
  write_forwarder_config
  upsert_forwarder_service
  configure_ufw
  save_install_state

  progress 4 4 "Peer forwarding finished"
  info "Direct SSH: ssh -p ${PEER_PUBLIC_SSH_PORT} ${PEER_USER}@${VPS1_IPV4}"
  [[ -n "${PEER_WINGS_PUBLIC_PORT}" ]] && info "Wings: VPS1 ${PEER_WINGS_PUBLIC_PORT} -> ${PEER_NAME} ${WG_PEER_IP}:${PEER_WINGS_TARGET_PORT}"
  [[ -n "${PEER_SFTP_PUBLIC_PORT}" ]] && info "SFTP: sftp -P ${PEER_SFTP_PUBLIC_PORT} ${PEER_USER}@${VPS1_IPV4}"
  [[ -n "${PEER_GAME_PORTS_RAW}" ]] && info "Game/allocation ranges: ${PEER_GAME_PORTS_RAW} (TCP+UDP)"
}

remove_client() {
  local helper_target=""
  local config_dir=""
  local config_target=""
  local ssh_alias_config=""

  determine_client_home
  helper_target="${CLIENT_INSTALL_HOME}/.local/bin/cakessh"
  config_dir="${CLIENT_INSTALL_HOME}/.config/cakessh"
  config_target="${config_dir}/client.env"
  ssh_alias_config="$(client_ssh_config_dropin_path)"

  rm -f -- "${helper_target}" "${config_target}" "${ssh_alias_config}"
  rmdir "${config_dir}" 2>/dev/null || true
  rmdir "$(client_ssh_config_dropin_dir)" 2>/dev/null || true
  info "Removed client helper/config."
}

remove_vps1() {
  local forwarder_service=""
  require_root
  apply_defaults
  forwarder_service="$(forwarder_service_name)"

  if [[ -x "$(forwarder_script_path)" ]]; then
    "$(forwarder_script_path)" down >/dev/null 2>&1 || true
  fi
  systemctl disable --now "${forwarder_service}" >/dev/null 2>&1 || true
  rm -f -- "/etc/systemd/system/${forwarder_service}"
  rm -f -- "$(forwarder_script_path)" "$(forwarder_config_path)"
  rm -f -- /etc/sysctl.d/99-cakessh-ip-forward.conf
  remove_wireguard
  rm -rf -- "$(ssh_peer_state_dir)" 2>/dev/null || true
  rmdir /etc/cakessh 2>/dev/null || true
  rmdir /usr/local/lib/cakessh 2>/dev/null || true
  systemctl daemon-reload
  info "Removed VM1/VPS1 forwarder, watchdog, and WireGuard files."
  warn "Firewall allow rules were left in place; remove old ufw rules manually if needed."
}

remove_vps2() {
  require_root
  remove_wireguard
  info "Removed VM2/VPS2 WireGuard and watchdog files."
}

remove_peer() {
  require_root
  remove_wireguard
  info "Removed peer WireGuard and watchdog files."
}

run_remove() {
  case "${ROLE}" in
    client) remove_client ;;
    vps1) remove_vps1 ;;
    vps2) remove_vps2 ;;
    peer) remove_peer ;;
    all)
      remove_client
      remove_vps1
      ;;
    *) fail "Unsupported role for remove: ${ROLE}" ;;
  esac
}

run_install() {
  prompt_install_inputs

  case "${ROLE}" in
    client)
      validate_client_inputs
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
      [[ "${INSTALL_CLIENT_HELPER}" == "yes" ]] && install_client
      ;;
    *) fail "Unsupported role for install: ${ROLE}" ;;
  esac
}

main() {
  parse_args "$@"
  prompt_role_if_needed
  load_install_state

  case "${ACTION}" in
    remove)
      run_remove
      ;;
    show-key)
      show_public_key
      ;;
    install)
      run_install
      ;;
  esac
}

main "$@"
