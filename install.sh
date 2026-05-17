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
GAME_PORTS_RAW=""
INSTALL_CLIENT_HELPER="yes"

WG_INTERFACE=""
WG_PORT=""
WG_VPS1_ADDRESS=""
WG_VPS2_ADDRESS=""
WG_VPS1_PUBLIC_KEY=""
WG_VPS2_PUBLIC_KEY=""
WG_VPS1_IP=""
WG_VPS2_IP=""
VPS2_HOST=""

CLIENT_INSTALL_USER=""
CLIENT_INSTALL_HOME=""
LOCAL_WG_PRIVATE_KEY=""
LOCAL_WG_PUBLIC_KEY=""

RELAY_NAMES=()
RELAY_LISTEN_PORTS=()
RELAY_TARGET_PORTS=()
RELAY_DESCRIPTIONS=()
GAME_PORT_LIST=()

DEFAULT_VPS1_USER="root"
DEFAULT_VPS2_USER="root"
DEFAULT_VPS1_SSH_PORT="22"
DEFAULT_VPS2_SSH_PORT="22"
DEFAULT_PUBLIC_SSH_FORWARD_PORT="2222"
DEFAULT_WINGS_SCHEME="http"
DEFAULT_GAME_PORTS_RAW="25565"
DEFAULT_WG_INTERFACE="cakessh-wg"
DEFAULT_WG_PORT="51820"
DEFAULT_WG_VPS1_ADDRESS="10.0.0.1/24"
DEFAULT_WG_VPS2_ADDRESS="10.0.0.2/24"

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
  sudo bash install.sh all
  sudo bash install.sh remove vps1

Roles:
  client   Install the local `cakessh` helper only.
  vps1     Install WireGuard on VPS1 and, once VPS2's public key is known, install relays.
  vps2     Install WireGuard on VPS2 so it auto-connects back to VPS1.
  all      Run the VPS1 flow and also install the local `cakessh` helper.

Client extras:
  - creates `cakessh connect` for SSH through VPS1
  - creates `cakessh direct` for SSH through VPS1's forwarded SSH port
  - creates SSH aliases `cakessh-vps2` and `cakessh-vps2-port`

Optional flags:
  --role client|vps1|vps2|all
  --mode install|remove
  --vps1-ipv4 203.0.113.10
  --vps1-user root
  --vps1-ssh-port 22
  --vps2-user root
  --vps2-ssh-port 22
  --identity-file /path/to/key
  --public-ssh-port 2222
  --wings-scheme http|https
  --game-ports 25565,25566,3000-4000
  --wg-interface cakessh-wg
  --wg-port 51820
  --wg-vps1-address 10.0.0.1/24
  --wg-vps2-address 10.0.0.2/24
  --wg-vps1-public-key BASE64KEY
  --wg-vps2-public-key BASE64KEY
  --no-client-helper
  --help

Uninstall:
  bash uninstall.sh client
  sudo bash uninstall.sh vps1
  sudo bash uninstall.sh vps2
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
    client|vps1|vps2|all) return 0 ;;
    *) return 1 ;;
  esac
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      client|vps1|vps2|all)
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
    install|remove) ;;
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
    if [[ "${ACTION}" == "remove" ]]; then
      ROLE="vps1"
    else
      ROLE="all"
    fi
    return 0
  fi

  local reply=""
  while true; do
    if [[ "${ACTION}" == "remove" ]]; then
      read -r -p "What do you want to remove? (client/vps1/vps2/all) [vps1]: " reply
      reply="${reply:-vps1}"
    else
      read -r -p "Which role do you want to install? (client/vps1/vps2/all) [all]: " reply
      reply="${reply:-all}"
    fi

    if is_supported_role "${reply}"; then
      ROLE="${reply}"
      return 0
    fi

    info "Please choose client, vps1, vps2, or all."
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

array_contains() {
  local needle="$1"
  shift || true
  local item=""
  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
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
  VPS1_SSH_PORT="${VPS1_SSH_PORT:-${DEFAULT_VPS1_SSH_PORT}}"
  VPS2_SSH_PORT="${VPS2_SSH_PORT:-${DEFAULT_VPS2_SSH_PORT}}"
  PUBLIC_SSH_FORWARD_PORT="${PUBLIC_SSH_FORWARD_PORT:-${DEFAULT_PUBLIC_SSH_FORWARD_PORT}}"
  WINGS_SCHEME="${WINGS_SCHEME:-${DEFAULT_WINGS_SCHEME}}"
  GAME_PORTS_RAW="${GAME_PORTS_RAW:-${DEFAULT_GAME_PORTS_RAW}}"
  WG_INTERFACE="${WG_INTERFACE:-${DEFAULT_WG_INTERFACE}}"
  WG_PORT="${WG_PORT:-${DEFAULT_WG_PORT}}"
  WG_VPS1_ADDRESS="${WG_VPS1_ADDRESS:-${DEFAULT_WG_VPS1_ADDRESS}}"
  WG_VPS2_ADDRESS="${WG_VPS2_ADDRESS:-${DEFAULT_WG_VPS2_ADDRESS}}"
}

normalize_wireguard_addresses() {
  apply_defaults
  validate_ipv4_cidr "${WG_VPS1_ADDRESS}"
  validate_ipv4_cidr "${WG_VPS2_ADDRESS}"

  WG_VPS1_IP="${WG_VPS1_ADDRESS%%/*}"
  WG_VPS2_IP="${WG_VPS2_ADDRESS%%/*}"
  VPS2_HOST="${WG_VPS2_IP}"

  [[ "${WG_VPS1_IP}" != "${WG_VPS2_IP}" ]] || fail "VPS1 and VPS2 WireGuard IPs must be different."
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

wireguard_private_key_path() {
  local node_role="$1"
  printf '%s/%s.privatekey' "$(wireguard_state_dir)" "${node_role}"
}

wireguard_public_key_path() {
  local node_role="$1"
  printf '%s/%s.publickey' "$(wireguard_state_dir)" "${node_role}"
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

upsert_wireguard_service() {
  local service_name
  service_name="$(wireguard_service_name)"

  systemctl enable --now "${service_name}"
  systemctl restart "${service_name}"
  systemctl is-active --quiet "${service_name}" || fail "WireGuard service failed to start: ${service_name}"
}

remove_wireguard() {
  local service_name

  apply_defaults
  service_name="$(wireguard_service_name)"

  systemctl disable --now "${service_name}" >/dev/null 2>&1 || true
  rm -f -- "$(wireguard_config_path)"
  rm -f -- "$(wireguard_private_key_path "vps1")"
  rm -f -- "$(wireguard_public_key_path "vps1")"
  rm -f -- "$(wireguard_private_key_path "vps2")"
  rm -f -- "$(wireguard_public_key_path "vps2")"
  rmdir "$(wireguard_state_dir)" 2>/dev/null || true
}

ensure_wireguard_backend_reachability() {
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "${WG_VPS2_IP}" "${VPS2_SSH_PORT}" >/dev/null 2>&1 \
      || fail "VPS1 cannot reach ${WG_VPS2_IP}:${VPS2_SSH_PORT} over WireGuard. Make sure VPS2 is installed and connected."
    return 0
  fi

  if command -v ping >/dev/null 2>&1; then
    ping -c 1 -W 2 "${WG_VPS2_IP}" >/dev/null 2>&1 \
      || fail "VPS1 cannot ping ${WG_VPS2_IP} over WireGuard. Make sure VPS2 is installed and connected."
    return 0
  fi

  fail "Could not find nc or ping to validate WireGuard reachability."
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
  if [[ "${WINGS_SCHEME}" == "https" ]]; then
    printf '8443'
  else
    printf '8080'
  fi
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

configure_ufw() {
  local port=""

  if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw is not installed. Open these TCP ports manually: $(join_by_comma "${RELAY_LISTEN_PORTS[@]}") and ${WG_PORT}/udp"
    return 0
  fi

  if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    warn "ufw is not active. Open these TCP ports manually if another firewall is enabled: $(join_by_comma "${RELAY_LISTEN_PORTS[@]}") and ${WG_PORT}/udp"
    return 0
  fi

  ufw allow "${WG_PORT}/udp" >/dev/null
  for port in "${RELAY_LISTEN_PORTS[@]}"; do
    ufw allow "${port}/tcp" >/dev/null
  done
}

prompt_install_inputs() {
  local detected_vps1_ipv4=""

  if [[ "${ROLE}" == "all" || "${ROLE}" == "vps1" ]]; then
    detected_vps1_ipv4="$(detect_primary_ipv4 || true)"
  fi

  if [[ "${ROLE}" == "client" || "${ROLE}" == "all" || "${ROLE}" == "vps1" || "${ROLE}" == "vps2" ]]; then
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
      prompt_optional_value WG_VPS2_PUBLIC_KEY "Paste the VPS2 WireGuard public key"
    fi

    if [[ -z "${WINGS_SCHEME}" ]]; then
      if prompt_yes_no "Expose Wings over HTTPS on port 8443?" "n"; then
        WINGS_SCHEME="https"
      else
        WINGS_SCHEME="http"
      fi
    fi

    prompt_value GAME_PORTS_RAW "Game TCP ports to forward (comma-separated)" "${DEFAULT_GAME_PORTS_RAW}"
  fi

  if [[ "${ROLE}" == "vps2" ]]; then
    prompt_value WG_INTERFACE "WireGuard interface name" "${DEFAULT_WG_INTERFACE}"
    prompt_value WG_PORT "WireGuard UDP port on VPS1" "${DEFAULT_WG_PORT}"
    prompt_value WG_VPS1_ADDRESS "VPS1 WireGuard address" "${DEFAULT_WG_VPS1_ADDRESS}"
    prompt_value WG_VPS2_ADDRESS "VPS2 WireGuard address" "${DEFAULT_WG_VPS2_ADDRESS}"
    prompt_value WG_VPS1_PUBLIC_KEY "VPS1 WireGuard public key" ""
  fi
}

prepare_relay_plan() {
  local wings_port=""
  local game_port=""

  RELAY_NAMES=()
  RELAY_LISTEN_PORTS=()
  RELAY_TARGET_PORTS=()
  RELAY_DESCRIPTIONS=()
  wings_port="$(calc_wings_port)"

  add_relay "ssh-vps2" "${PUBLIC_SSH_FORWARD_PORT}" "${VPS2_SSH_PORT}" "Direct SSH to VPS2 over WireGuard"
  add_relay "wings" "${wings_port}" "${wings_port}" "Pterodactyl Wings over WireGuard"
  add_relay "sftp" "2022" "2022" "Pterodactyl SFTP over WireGuard"

  for game_port in "${GAME_PORT_LIST[@]}"; do
    add_relay "game-${game_port}" "${game_port}" "${game_port}" "Minecraft game port ${game_port} over WireGuard"
  done
}

validate_client_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_ipv4_basic "${VPS1_IPV4}"
  validate_port "${VPS1_SSH_PORT}"
  validate_port "${VPS2_SSH_PORT}"
  validate_port "${PUBLIC_SSH_FORWARD_PORT}"
  validate_wings_scheme
  normalize_game_ports
  validate_identity_file_if_present
}

validate_vps1_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_ipv4_basic "${VPS1_IPV4}"
  validate_port "${VPS2_SSH_PORT}"
  validate_port "${PUBLIC_SSH_FORWARD_PORT}"
  validate_port "${WG_PORT}"
  validate_wings_scheme
  normalize_game_ports
  validate_wireguard_public_key_if_present "${WG_VPS2_PUBLIC_KEY}"
}

validate_vps2_inputs() {
  apply_defaults
  normalize_wireguard_addresses
  validate_ipv4_basic "${VPS1_IPV4}"
  validate_port "${WG_PORT}"
  validate_wireguard_public_key_if_present "${WG_VPS1_PUBLIC_KEY}"
  [[ -n "${WG_VPS1_PUBLIC_KEY}" ]] || fail "VPS2 install requires --wg-vps1-public-key."
}

validate_vps1_relay_phase() {
  local listen_port=""

  stop_existing_relays
  for listen_port in "${RELAY_LISTEN_PORTS[@]}"; do
    ensure_port_is_free "${listen_port}"
  done
}

print_vps1_bootstrap_summary() {
  info ""
  info "VPS1 WireGuard bootstrap complete."
  info "Autostart enabled: $(wireguard_service_name)"
  info "VPS1 WireGuard public key:"
  info "  ${LOCAL_WG_PUBLIC_KEY}"
  info ""
  info "Run this on VPS2 next:"
  info "  sudo bash install.sh vps2 --vps1-ipv4 ${VPS1_IPV4} --wg-interface ${WG_INTERFACE} --wg-port ${WG_PORT} --wg-vps1-address ${WG_VPS1_ADDRESS} --wg-vps2-address ${WG_VPS2_ADDRESS} --wg-vps1-public-key ${LOCAL_WG_PUBLIC_KEY}"
  info ""
  info "After VPS2 prints its public key, rerun this on VPS1 to finish the relays:"
  info "  sudo bash install.sh vps1 --vps1-ipv4 ${VPS1_IPV4} --vps2-user ${VPS2_USER} --vps2-ssh-port ${VPS2_SSH_PORT} --public-ssh-port ${PUBLIC_SSH_FORWARD_PORT} --wings-scheme ${WINGS_SCHEME} --game-ports $(join_by_comma "${GAME_PORT_LIST[@]}") --wg-interface ${WG_INTERFACE} --wg-port ${WG_PORT} --wg-vps1-address ${WG_VPS1_ADDRESS} --wg-vps2-address ${WG_VPS2_ADDRESS} --wg-vps2-public-key <PASTE_VPS2_PUBLIC_KEY>"
  info ""
  info "After that you can use either:"
  info "  cakessh connect"
  info "  ssh -p ${PUBLIC_SSH_FORWARD_PORT} ${VPS2_USER}@${VPS1_IPV4}"
}

print_vps2_summary() {
  info ""
  info "VPS2 WireGuard install complete."
  info "Autostart enabled: $(wireguard_service_name)"
  info "VPS2 WireGuard public key:"
  info "  ${LOCAL_WG_PUBLIC_KEY}"
  info ""
  info "Run this on VPS1 now:"
  info "  sudo bash install.sh vps1 --vps1-ipv4 ${VPS1_IPV4} --vps2-user ${DEFAULT_VPS2_USER} --vps2-ssh-port ${DEFAULT_VPS2_SSH_PORT} --public-ssh-port ${DEFAULT_PUBLIC_SSH_FORWARD_PORT} --wings-scheme ${DEFAULT_WINGS_SCHEME} --game-ports ${DEFAULT_GAME_PORTS_RAW} --wg-interface ${WG_INTERFACE} --wg-port ${WG_PORT} --wg-vps1-address ${WG_VPS1_ADDRESS} --wg-vps2-address ${WG_VPS2_ADDRESS} --wg-vps2-public-key ${LOCAL_WG_PUBLIC_KEY}"
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

  if [[ -z "${WG_VPS2_PUBLIC_KEY}" ]]; then
    progress 3 5 "Waiting for VPS2 public key to finish setup"
    print_vps1_bootstrap_summary
    return 0
  fi

  progress 3 5 "Checking WireGuard connection to VPS2"
  ensure_wireguard_backend_reachability
  prepare_relay_plan
  validate_vps1_relay_phase

  progress 4 5 "Installing TCP relays on VPS1"
  ensure_socat_installed
  write_relay_runner
  write_systemd_unit
  write_relay_envs
  systemctl daemon-reload
  enable_relays
  configure_ufw

  progress 5 5 "VPS1 setup finished"
  wings_port="$(calc_wings_port)"
  first_game_port="${GAME_PORT_LIST[0]}"

  info ""
  info "VPS1 relay install complete."
  info "WireGuard backend: ${WG_VPS2_IP} via ${WG_INTERFACE}"
  info "Autostart enabled: $(wireguard_service_name)"
  info "Direct SSH:"
  info "  ssh -p ${PUBLIC_SSH_FORWARD_PORT} ${VPS2_USER}@${VPS1_IPV4}"
  if [[ "${WINGS_SCHEME}" == "https" ]]; then
    info "Wings:"
    info "  curl -k https://${VPS1_IPV4}:${wings_port}"
  else
    info "Wings:"
    info "  curl http://${VPS1_IPV4}:${wings_port}"
  fi
  info "SFTP:"
  info "  sftp -P 2022 ${VPS2_USER}@${VPS1_IPV4}"
  info "Minecraft test:"
  info "  nc -vz ${VPS1_IPV4} ${first_game_port}"
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
  progress 4 4 "VPS2 setup finished"
  print_vps2_summary
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
  require_root
  progress 1 3 "Stopping VPS1 relays"
  disable_relay_instances "Stopping relay batch" "yes"
  find /etc/cakessh/relays -mindepth 1 -maxdepth 1 -type f -name '*.env' -delete 2>/dev/null || true
  rm -f -- /etc/cakessh/instances.list
  rm -f -- /etc/systemd/system/cakessh-relay@.service
  rm -f -- /usr/local/lib/cakessh/cakessh-relay-runner
  rmdir /etc/cakessh/relays 2>/dev/null || true
  rmdir /etc/cakessh 2>/dev/null || true
  rmdir /usr/local/lib/cakessh 2>/dev/null || true
  progress 2 3 "Removing WireGuard from VPS1"
  remove_wireguard
  systemctl daemon-reload

  progress 3 3 "VPS1 uninstall finished"
  info "Removed cakessh relay services and WireGuard from VPS1."
  warn "Firewall rules were left in place. Remove them manually if you no longer need them."
}

remove_vps2() {
  require_root
  progress 1 2 "Removing WireGuard from VPS2"
  remove_wireguard
  progress 2 2 "VPS2 uninstall finished"
  info "Removed WireGuard from VPS2."
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

  if [[ "${ACTION}" == "remove" ]]; then
    run_remove
    return 0
  fi

  run_install
}

main "$@"
