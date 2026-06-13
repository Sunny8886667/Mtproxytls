#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="mtproxy-faketls"
IMAGE="seriyps/mtproto-proxy:latest"
INSTALL_DIR="/opt/${APP_NAME}"
ENV_FILE="${INSTALL_DIR}/.env"
COMPOSE_FILE="${INSTALL_DIR}/compose.yml"
SERVICE_NAME="${APP_NAME}"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
MANAGER_BIN="/usr/local/bin/mtproxy"
DEFAULT_PORT="443"
DEFAULT_TAG="00000000000000000000000000000000"

DOMAIN=""
PORT="${DEFAULT_PORT}"
FRONT_DOMAIN=""
PUBLIC_IP=""
SECRET=""
TAG=""
CF_API_TOKEN="${CF_API_TOKEN:-}"
CF_ZONE_ID="${CF_ZONE_ID:-}"
DO_DNS="auto"
ACTION="install"
FORCE="0"

usage() {
  cat <<'EOF'
MTProxy FakeTLS installer with promoted-channel tag support.

+------------------------------------------------------------------+
| Support / Development / Customization                            |
| Telegram: @Bill_999                                               |
+------------------------------------------------------------------+

Usage:
  sudo bash install.sh --domain mtproto.example.com [options]

Options:
  --domain DOMAIN          Public hostname for the proxy. Required for install.
  --port PORT              Listen port. Default: 443.
  --front-domain DOMAIN    FakeTLS SNI hostname in the Telegram secret. Default: same as --domain.
  --public-ip IP           Public IPv4. Auto-detected when omitted.
  --secret SECRET          Existing 32-hex MTProxy server secret. Auto-generated when omitted.
  --tag TAG                Telegram promoted-channel tag from @MTProxybot.
  --update-tag TAG         Update only the promoted-channel tag and restart.
  --cf-token TOKEN         Cloudflare API token. Or use CF_API_TOKEN env.
  --cf-zone-id ZONE_ID     Cloudflare zone ID. Or use CF_ZONE_ID env.
  --dns auto|yes|no        Manage Cloudflare DNS. Default: auto.
  --force                  Replace existing config and continue if port is in use.
  --start                  Start the service.
  --stop                   Stop the service.
  --restart                Restart the service.
  --status                 Show service and container status.
  --logs                   Follow service logs.
  --link                   Print Telegram proxy parameters and import link.
  --remove                 Stop and remove service/config. Keeps Docker installed.
  -h, --help               Show this help.

Cloudflare DNS:
  The installer creates/updates only the exact hostname passed by --domain.
  The record is A, DNS-only, pointing to the server public IPv4.

Examples:
  sudo bash install.sh --domain mtproto.example.com

  sudo bash install.sh --domain mtproto.example.com --tag 0123456789abcdef0123456789abcdef

  export CF_API_TOKEN="..."
  export CF_ZONE_ID="..."
  sudo -E bash install.sh --domain mtproto.example.com --dns yes

  sudo bash install.sh --update-tag 0123456789abcdef0123456789abcdef

  sudo bash install.sh --status
  sudo bash install.sh --restart
  sudo bash install.sh --logs

  sudo bash install.sh --remove
EOF
}

log() {
  printf '[mtproxy] %s\n' "$*"
}

print_contact_box() {
  cat <<'EOF'
+------------------------------------------------------------------+
| MTProxy FakeTLS Installer                                        |
|                                                                  |
| Script support, development, and customization                    |
| Telegram: @Bill_999                                               |
+------------------------------------------------------------------+
EOF
}

die() {
  printf '[mtproxy] ERROR: %s\n' "$*" >&2
  exit 1
}

need_root() {
  [[ "${EUID}" -eq 0 ]] || die "run as root, for example: sudo bash install.sh --domain mtproto.example.com"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_value() {
  local opt="$1"
  local value="${2:-}"
  [[ -n "${value}" && "${value}" != -* ]] || die "${opt} requires a value"
  printf '%s\n' "${value}"
}

is_hostname() {
  local name="${1%.}"
  [[ ${#name} -ge 3 && ${#name} -le 253 ]] || return 1
  [[ "${name}" == *.* ]] || return 1
  [[ "${name}" =~ ^[A-Za-z0-9.-]+$ ]] || return 1

  local label
  IFS='.' read -ra labels <<< "${name}"
  for label in "${labels[@]}"; do
    [[ -n "${label}" && ${#label} -le 63 ]] || return 1
    [[ "${label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

is_ipv4() {
  local ip="$1"
  [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

  local octet
  IFS='.' read -ra octets <<< "${ip}"
  [[ ${#octets[@]} -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "${octet}" =~ ^[0-9]+$ ]] || return 1
    (( 10#${octet} >= 0 && 10#${octet} <= 255 )) || return 1
  done
}

ensure_systemd() {
  have_cmd systemctl || die "systemctl is required"
  [[ -d /run/systemd/system ]] || die "systemd is not running; run this on a systemd-based VPS"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)
        DOMAIN="$(require_value "$1" "${2:-}")"; shift 2 ;;
      --port)
        PORT="$(require_value "$1" "${2:-}")"; shift 2 ;;
      --front-domain)
        FRONT_DOMAIN="$(require_value "$1" "${2:-}")"; shift 2 ;;
      --public-ip)
        PUBLIC_IP="$(require_value "$1" "${2:-}")"; shift 2 ;;
      --secret)
        SECRET="$(require_value "$1" "${2:-}")"; shift 2 ;;
      --tag)
        TAG="$(require_value "$1" "${2:-}")"; shift 2 ;;
      --update-tag)
        ACTION="update-tag"; TAG="$(require_value "$1" "${2:-}")"; shift 2 ;;
      --cf-token)
        CF_API_TOKEN="$(require_value "$1" "${2:-}")"; shift 2 ;;
      --cf-zone-id)
        CF_ZONE_ID="$(require_value "$1" "${2:-}")"; shift 2 ;;
      --dns)
        DO_DNS="$(require_value "$1" "${2:-}")"; shift 2 ;;
      --force)
        FORCE="1"; shift ;;
      --start)
        ACTION="start"; shift ;;
      --stop)
        ACTION="stop"; shift ;;
      --restart)
        ACTION="restart"; shift ;;
      --status)
        ACTION="status"; shift ;;
      --logs)
        ACTION="logs"; shift ;;
      --link)
        ACTION="link"; shift ;;
      --remove)
        ACTION="remove"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        die "unknown argument: $1" ;;
    esac
  done
}

validate_common() {
  DOMAIN="${DOMAIN%.}"
  FRONT_DOMAIN="${FRONT_DOMAIN%.}"
  if [[ -n "${DOMAIN}" ]] && ! is_hostname "${DOMAIN}"; then
    die "--domain must be a valid public hostname, for example mtproto.example.com"
  fi
  if [[ -n "${FRONT_DOMAIN}" ]] && ! is_hostname "${FRONT_DOMAIN}"; then
    die "--front-domain must be a valid public hostname"
  fi
  if [[ -n "${PUBLIC_IP}" ]] && ! is_ipv4 "${PUBLIC_IP}"; then
    die "--public-ip must be a valid IPv4 address"
  fi
  [[ "${PORT}" =~ ^[0-9]+$ ]] || die "--port must be a number"
  if (( PORT < 1 || PORT > 65535 )); then
    die "--port must be between 1 and 65535"
  fi
  case "${DO_DNS}" in
    auto|yes|no) ;;
    *) die "--dns must be auto, yes, or no" ;;
  esac
  if [[ -n "${SECRET}" && ! "${SECRET}" =~ ^[[:xdigit:]]{32}$ ]]; then
    die "--secret must be exactly 32 hex characters for seriyps/mtproto-proxy"
  fi
  if [[ -n "${TAG}" && ! "${TAG}" =~ ^[[:xdigit:]]{32}$ ]]; then
    die "--tag/--update-tag must be exactly 32 hex characters from @MTProxybot"
  fi
}

validate_args() {
  validate_common
  case "${ACTION}" in
    install)
      [[ -n "${DOMAIN}" ]] || die "--domain is required"
      ;;
    update-tag)
      [[ -n "${TAG}" ]] || die "--update-tag requires a tag"
      ;;
    start|stop|restart|status|logs|link)
      ;;
    remove)
      ;;
    *)
      die "invalid action: ${ACTION}"
      ;;
  esac
}

install_base_deps() {
  local missing=()
  for cmd in curl awk sed grep openssl systemctl python3 ss; do
    have_cmd "${cmd}" || missing+=("${cmd}")
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    return
  fi

  if have_cmd apt-get; then
    log "installing dependencies: ${missing[*]}"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates openssl coreutils grep sed gawk python3 iproute2
  elif have_cmd dnf; then
    log "installing dependencies: ${missing[*]}"
    dnf install -y curl ca-certificates openssl coreutils grep sed gawk python3 iproute
  elif have_cmd yum; then
    log "installing dependencies: ${missing[*]}"
    yum install -y curl ca-certificates openssl coreutils grep sed gawk python3 iproute
  else
    die "missing dependencies (${missing[*]}) and no supported package manager found"
  fi
}

install_docker() {
  if have_cmd docker; then
    ensure_docker_running
    return
  fi

  log "Docker not found; installing Docker"
  if have_cmd apt-get; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc || \
      curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    . /etc/os-release
    local repo_os="${ID}"
    case "${ID}" in
      ubuntu|debian) ;;
      *) repo_os="ubuntu" ;;
    esac
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${repo_os} ${VERSION_CODENAME:-jammy} stable" > /etc/apt/sources.list.d/docker.list
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif have_cmd dnf; then
    dnf install -y dnf-plugins-core
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif have_cmd yum; then
    yum install -y yum-utils
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    die "cannot install Docker automatically on this OS"
  fi

  ensure_docker_running
}

has_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi
  have_cmd docker-compose
}

install_compose_plugin() {
  if has_docker_compose; then
    return
  fi

  log "Docker Compose not found; installing Compose plugin"
  if have_cmd apt-get; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin || \
      DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose
  elif have_cmd dnf; then
    dnf install -y docker-compose-plugin || dnf install -y docker-compose
  elif have_cmd yum; then
    yum install -y docker-compose-plugin || yum install -y docker-compose
  else
    die "Docker Compose is not available and no supported package manager found"
  fi

  has_docker_compose || die "Docker Compose is still not available after installation"
}

ensure_docker_running() {
  have_cmd docker || die "Docker is not installed"
  systemctl enable --now docker
  docker info >/dev/null 2>&1 || die "Docker daemon is not running"
}

docker_compose_cmd() {
  if have_cmd docker && docker compose version >/dev/null 2>&1; then
    printf '%s compose\n' "$(command -v docker)"
  elif have_cmd docker-compose; then
    command -v docker-compose
  else
    die "Docker Compose is not available"
  fi
}

update_env_var() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"

  if grep -q "^${key}=" "${ENV_FILE}"; then
    awk -v key="${key}" -v value="${value}" 'BEGIN { updated=0 }
      $0 ~ "^" key "=" && !updated { print key "=" value; updated=1; next }
      { print }
      END { if (!updated) print key "=" value }' "${ENV_FILE}" > "${tmp}"
  else
    cat "${ENV_FILE}" > "${tmp}"
    printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"
  fi

  cat "${tmp}" > "${ENV_FILE}"
  rm -f "${tmp}"
  chmod 600 "${ENV_FILE}"
}

detect_public_ip() {
  if [[ -n "${PUBLIC_IP}" ]]; then
    is_ipv4 "${PUBLIC_IP}" || die "--public-ip must be a valid IPv4 address"
    printf '%s\n' "${PUBLIC_IP}"
    return
  fi

  local ip=""
  for url in https://api.ipify.org https://ifconfig.co/ip https://icanhazip.com; do
    ip="$(curl -fsSL --connect-timeout 5 --max-time 10 "${url}" 2>/dev/null | tr -d '[:space:]' || true)"
    if is_ipv4 "${ip}"; then
      printf '%s\n' "${ip}"
      return
    fi
  done
  die "could not auto-detect public IPv4; pass --public-ip"
}

stop_existing_install() {
  if [[ -f "${SYSTEMD_FILE}" ]] || systemctl list-unit-files "${SERVICE_NAME}.service" >/dev/null 2>&1; then
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
      log "stopping existing ${SERVICE_NAME} service before reinstall"
      systemctl stop "${SERVICE_NAME}.service" || true
    fi
  fi

  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -Fxq "${SERVICE_NAME}"; then
    log "removing existing ${SERVICE_NAME} container before reinstall"
    docker rm -f "${SERVICE_NAME}" >/dev/null 2>&1 || true
  fi
}

check_port_free() {
  if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\])${PORT}$"; then
    if [[ "${FORCE}" != "1" ]]; then
      die "port ${PORT} is already in use; stop the conflicting service or pass --force"
    fi
  fi
}

generate_secret() {
  if [[ -n "${SECRET}" ]]; then
    printf '%s\n' "${SECRET}"
    return
  fi

  openssl rand -hex 16
}

write_env() {
  local public_ip secret
  public_ip="$(detect_public_ip)"
  secret="$(generate_secret)"
  [[ -n "${FRONT_DOMAIN}" ]] || FRONT_DOMAIN="${DOMAIN}"
  [[ -n "${TAG}" ]] || TAG="${DEFAULT_TAG}"
  mkdir -p "${INSTALL_DIR}"
  chmod 700 "${INSTALL_DIR}"
  cat > "${ENV_FILE}" <<EOF
DOMAIN=${DOMAIN}
FRONT_DOMAIN=${FRONT_DOMAIN}
PUBLIC_IP=${public_ip}
PORT=${PORT}
MTP_SECRET=${secret}
MTP_TAG=${TAG}
IMAGE=${IMAGE}
EOF
  chmod 600 "${ENV_FILE}"
}

write_compose() {
  cat > "${COMPOSE_FILE}" <<'EOF'
services:
  mtproxy:
    image: ${IMAGE}
    container_name: mtproxy-faketls
    restart: unless-stopped
    network_mode: host
    environment:
      MTP_PORT: ${PORT}
      MTP_SECRET: ${MTP_SECRET}
      MTP_TAG: ${MTP_TAG}
      MTP_TLS_ONLY: "t"
EOF
  chmod 600 "${COMPOSE_FILE}"
}

write_systemd() {
  local compose
  compose="$(docker_compose_cmd)"
  cat > "${SYSTEMD_FILE}" <<EOF
[Unit]
Description=Telegram MTProxy FakeTLS with adtag support
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
ExecStart=${compose} --env-file ${ENV_FILE} -f ${COMPOSE_FILE} up -d
ExecStop=${compose} --env-file ${ENV_FILE} -f ${COMPOSE_FILE} down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
}

write_manager() {
  cat > "${MANAGER_BIN}" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="mtproxy-faketls"
INSTALL_DIR="/opt/${APP_NAME}"
ENV_FILE="${INSTALL_DIR}/.env"
SERVICE_NAME="${APP_NAME}"
INSTALL_SCRIPT="${INSTALL_DIR}/install.sh"

die() {
  printf '[mtproxy] ERROR: %s\n' "$*" >&2
  exit 1
}

need_root() {
  [[ "${EUID}" -eq 0 ]] || die "run as root"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

load_env() {
  [[ -f "${ENV_FILE}" ]] || die "${ENV_FILE} not found; install first"
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
}

validate_hex32() {
  local value="$1"
  local label="$2"
  [[ "${value}" =~ ^[[:xdigit:]]{32}$ ]] || die "${label} must be exactly 32 hex characters"
}

update_env_var() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"

  if grep -q "^${key}=" "${ENV_FILE}"; then
    awk -v key="${key}" -v value="${value}" 'BEGIN { updated=0 }
      $0 ~ "^" key "=" && !updated { print key "=" value; updated=1; next }
      { print }
      END { if (!updated) print key "=" value }' "${ENV_FILE}" > "${tmp}"
  else
    cat "${ENV_FILE}" > "${tmp}"
    printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"
  fi

  cat "${tmp}" > "${ENV_FILE}"
  rm -f "${tmp}"
  chmod 600 "${ENV_FILE}"
}

telegram_secret() {
  local server_secret="$1"
  local front_domain="$2"
  python3 - "${server_secret}" "${front_domain}" <<'PY'
import base64
import sys
raw = b"\xee" + bytes.fromhex(sys.argv[1]) + sys.argv[2].encode("ascii")
print(base64.urlsafe_b64encode(raw).decode("ascii").rstrip("="))
PY
}

print_link() {
  load_env
  local tg_secret
  tg_secret="$(telegram_secret "${MTP_SECRET}" "${FRONT_DOMAIN}")"
  cat <<OUT
Telegram:
  Type:   MTProto
  Server: ${DOMAIN}
  Port:   ${PORT}
  Secret: ${tg_secret}

Import link:
  https://t.me/proxy?server=${DOMAIN}&port=${PORT}&secret=${tg_secret}

Promoted tag:
  ${MTP_TAG}

Support / Development / Customization:
  Telegram: @Bill_999
OUT
}

status_cmd() {
  systemctl status "${SERVICE_NAME}.service" --no-pager -l || true
  if command -v docker >/dev/null 2>&1; then
    docker ps -a --filter "name=mtproxy-faketls" || true
  fi
}

restart_compose() {
  systemctl restart "${SERVICE_NAME}.service"
  sleep 2
  systemctl is-active --quiet "${SERVICE_NAME}.service" || die "service failed to restart"
}

update_tag() {
  need_root
  load_env
  local tag="${1:-}"
  if [[ -z "${tag}" ]]; then
    read -r -p "Enter 32-hex promoted tag from @MTProxybot: " tag
  fi
  validate_hex32 "${tag}" "tag"
  update_env_var "MTP_TAG" "${tag}"
  restart_compose
  print_link
}

reset_secret() {
  need_root
  load_env
  local secret="${1:-}"
  if [[ -z "${secret}" ]]; then
    secret="$(openssl rand -hex 16)"
  fi
  validate_hex32 "${secret}" "secret"
  update_env_var "MTP_SECRET" "${secret}"
  restart_compose
  print_link
}

reinstall() {
  need_root
  [[ -x "${INSTALL_SCRIPT}" ]] || die "${INSTALL_SCRIPT} not found"
  load_env
  bash "${INSTALL_SCRIPT}" --domain "${DOMAIN}" --port "${PORT}" --public-ip "${PUBLIC_IP}" --secret "${MTP_SECRET}" --tag "${MTP_TAG}" --dns no --force
}

show_menu() {
  cat <<'MENU'

MTProxy FakeTLS Manager
1) Start
2) Stop
3) Restart
4) Reload config
5) Status
6) Logs
7) Show Telegram link
8) Update promoted tag
9) Reset secret/key
10) Reinstall
11) Uninstall
0) Exit
MENU
}

menu() {
  while true; do
    show_menu
    read -r -p "Choose: " choice
    case "${choice}" in
      1) need_root; systemctl start "${SERVICE_NAME}.service" ;;
      2) need_root; systemctl stop "${SERVICE_NAME}.service" ;;
      3) need_root; systemctl restart "${SERVICE_NAME}.service" ;;
      4) need_root; restart_compose ;;
      5) status_cmd ;;
      6) journalctl -u "${SERVICE_NAME}.service" -f ;;
      7) print_link ;;
      8) update_tag ;;
      9) reset_secret ;;
      10) reinstall ;;
      11)
        need_root
        read -r -p "Uninstall MTProxy? Type yes to continue: " confirm
        [[ "${confirm}" == "yes" ]] && bash "${INSTALL_SCRIPT}" --remove
        ;;
      0) exit 0 ;;
      *) echo "Invalid choice" ;;
    esac
  done
}

case "${1:-menu}" in
  menu) menu ;;
  start) need_root; systemctl start "${SERVICE_NAME}.service" ;;
  stop) need_root; systemctl stop "${SERVICE_NAME}.service" ;;
  restart) need_root; systemctl restart "${SERVICE_NAME}.service" ;;
  reload) need_root; restart_compose ;;
  status) status_cmd ;;
  logs) journalctl -u "${SERVICE_NAME}.service" -f ;;
  link) print_link ;;
  tag) shift; update_tag "${1:-}" ;;
  secret|reset-secret) shift; reset_secret "${1:-}" ;;
  reinstall) reinstall ;;
  uninstall|remove) need_root; bash "${INSTALL_SCRIPT}" --remove ;;
  help|-h|--help)
    cat <<'HELP'
Usage:
  mtproxy                 Open interactive menu
  mtproxy start
  mtproxy stop
  mtproxy restart
  mtproxy reload
  mtproxy status
  mtproxy logs
  mtproxy link
  mtproxy tag <32-hex-tag>
  mtproxy reset-secret [32-hex-secret]
  mtproxy reinstall
  mtproxy uninstall
HELP
    ;;
  *) die "unknown command: $1" ;;
esac
EOF
  chmod 0755 "${MANAGER_BIN}"
}

cloudflare_dns() {
  local public_ip
  public_ip="$(awk -F= '/^PUBLIC_IP=/ {print $2}' "${ENV_FILE}")"

  if [[ "${DO_DNS}" == "no" ]]; then
    return
  fi
  if [[ -z "${CF_API_TOKEN}" || -z "${CF_ZONE_ID}" ]]; then
    if [[ "${DO_DNS}" == "yes" ]]; then
      die "--dns yes requires CF_API_TOKEN and CF_ZONE_ID"
    fi
    log "Cloudflare credentials not provided; create DNS manually:"
    log "  ${DOMAIN} -> ${public_ip} (A, DNS-only)"
    return
  fi

  have_cmd python3 || die "Cloudflare DNS automation requires python3"
  log "creating/updating Cloudflare DNS record for ${DOMAIN}"
  CF_API_TOKEN="${CF_API_TOKEN}" CF_ZONE_ID="${CF_ZONE_ID}" DOMAIN="${DOMAIN}" PUBLIC_IP="${public_ip}" python3 <<'PY'
import json
import os
import urllib.error
import urllib.parse
import urllib.request

token = os.environ["CF_API_TOKEN"]
zone = os.environ["CF_ZONE_ID"]
domain = os.environ["DOMAIN"]
public_ip = os.environ["PUBLIC_IP"]
base = f"https://api.cloudflare.com/client/v4/zones/{zone}/dns_records"
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

def request(method, url, data=None):
    payload = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(url, data=payload, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            out = json.loads(res.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise SystemExit(f"Cloudflare API HTTP {exc.code}: {body}")
    except urllib.error.URLError as exc:
        raise SystemExit(f"Cloudflare API request failed: {exc.reason}")
    if not out.get("success"):
        raise SystemExit(json.dumps(out, indent=2))
    return out

query = urllib.parse.urlencode({"name": domain, "per_page": 100})
records = request("GET", f"{base}?{query}")["result"]
matching_a = [rec for rec in records if rec.get("type") == "A"]
payload = {
    "type": "A",
    "name": domain,
    "content": public_ip,
    "ttl": 1,
    "proxied": False,
    "comment": "Telegram MTProxy FakeTLS"
}

if matching_a:
    primary = matching_a[0]
    created = request("PUT", f"{base}/{primary['id']}", payload)["result"]
    for rec in matching_a[1:]:
        request("DELETE", f"{base}/{rec['id']}")
else:
    created = request("POST", base, payload)["result"]

print(f"{created['name']} {created['type']} {created['content']} proxied={created['proxied']}")
PY
}

start_service() {
  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}.service"
  sleep 3
  systemctl is-active --quiet "${SERVICE_NAME}.service" || {
    systemctl status "${SERVICE_NAME}.service" --no-pager -l || true
    if have_cmd docker; then
      docker logs "${SERVICE_NAME}" 2>/dev/null || true
    fi
    die "service failed to start"
  }
}

print_access() {
  [[ -f "${ENV_FILE}" ]] || die "${ENV_FILE} not found; run install first"
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  local tg_secret url
  tg_secret="$(telegram_secret "${MTP_SECRET}" "${FRONT_DOMAIN}")"
  url="https://t.me/proxy?server=${DOMAIN}&port=${PORT}&secret=${tg_secret}"
  cat <<EOF

Installed successfully.

Telegram:
  Type:   MTProto
  Server: ${DOMAIN}
  Port:   ${PORT}
  Secret: ${tg_secret}

Import link:
  ${url}

Promoted tag:
  ${MTP_TAG}

Service:
  systemctl status ${SERVICE_NAME}
  journalctl -u ${SERVICE_NAME} -f

Files:
  ${ENV_FILE}
  ${COMPOSE_FILE}

Support / Development / Customization:
  Telegram: @Bill_999
EOF
}

service_action() {
  need_root
  if [[ ! -f "${SYSTEMD_FILE}" && "${ACTION}" != "status" ]]; then
    die "${SERVICE_NAME} is not installed"
  fi
  case "${ACTION}" in
    start)
      systemctl start "${SERVICE_NAME}.service"
      systemctl is-active --quiet "${SERVICE_NAME}.service" && log "started"
      ;;
    stop)
      systemctl stop "${SERVICE_NAME}.service"
      log "stopped"
      ;;
    restart)
      systemctl restart "${SERVICE_NAME}.service"
      systemctl is-active --quiet "${SERVICE_NAME}.service" && log "restarted"
      ;;
    status)
      systemctl status "${SERVICE_NAME}.service" --no-pager -l || true
      if have_cmd docker; then
        docker ps -a --filter "name=mtproxy-faketls" || true
      fi
      ;;
    logs)
      journalctl -u "${SERVICE_NAME}.service" -f
      ;;
    link)
      print_access
      ;;
    *)
      die "unsupported service action: ${ACTION}"
      ;;
  esac
}

telegram_secret() {
  local server_secret="$1"
  local front_domain="$2"
python3 - "${server_secret}" "${front_domain}" <<'PY'
import base64
import sys

server_secret = sys.argv[1]
front_domain = sys.argv[2]
raw = b"\xee" + bytes.fromhex(server_secret) + front_domain.encode("ascii")
print(base64.urlsafe_b64encode(raw).decode("ascii").rstrip("="))
PY
}

update_tag() {
  need_root
  [[ -f "${ENV_FILE}" ]] || die "${ENV_FILE} not found; run install first"
  log "updating promoted-channel tag"
  [[ "${TAG}" =~ ^[[:xdigit:]]{32}$ ]] || die "tag must be exactly 32 hex characters"
  update_env_var "MTP_TAG" "${TAG}"
  systemctl restart "${SERVICE_NAME}.service"
  sleep 2
  systemctl is-active --quiet "${SERVICE_NAME}.service" || {
    systemctl status "${SERVICE_NAME}.service" --no-pager -l || true
    if have_cmd docker; then
      docker logs "${SERVICE_NAME}" 2>/dev/null || true
    fi
    die "service failed after tag update"
  }
  print_access
}

remove_installation() {
  need_root
  log "removing ${APP_NAME}"
  systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true
  local compose=""
  if [[ -d "${INSTALL_DIR}" ]]; then
    compose="$(docker_compose_cmd 2>/dev/null || true)"
    if [[ -n "${compose}" ]]; then
      (cd "${INSTALL_DIR}" && ${compose} --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" down) 2>/dev/null || true
    fi
  fi
  rm -f "${SYSTEMD_FILE}"
  rm -f "${MANAGER_BIN}"
  rm -rf "${INSTALL_DIR}"
  systemctl daemon-reload
  systemctl reset-failed 2>/dev/null || true
  log "removed. Docker itself was left installed."
}

main() {
  parse_args "$@"
  validate_args

  case "${ACTION}" in
    remove)
      remove_installation
      exit 0
      ;;
    update-tag)
      update_tag
      exit 0
      ;;
    start|stop|restart|status|logs|link)
      service_action
      exit 0
      ;;
  esac

  need_root
  print_contact_box
  ensure_systemd
  install_base_deps
  install_docker
  ensure_docker_running
  install_compose_plugin
  stop_existing_install
  check_port_free
  write_env
  write_compose
  write_systemd
  install -m 0755 "$0" "${INSTALL_DIR}/install.sh"
  write_manager
  start_service
  cloudflare_dns
  print_access
}

main "$@"
