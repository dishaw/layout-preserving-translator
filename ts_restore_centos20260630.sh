#!/usr/bin/env bash
# =========================================================
# HUSKY TRANSLATE - Restore Script for CentOS / RHEL 8+
# Usage: sudo bash ts_restore_centos.sh <backup.7z>
# =========================================================

set -Eeuo pipefail

ARCHIVE="${1:-}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# onlyoffice_lib (document cache) and onlyoffice_logs are intentionally not
# backed up. They regenerate automatically on first use.
PROJECT_ROOT="${PROJECT_ROOT:-/opt/husky-trans}"
WORK_DIR="${WORK_DIR:-/tmp/husky_restore_${TIMESTAMP}}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
LOG_FILE="$LOG_DIR/husky_restore_${TIMESTAMP}.log"
PORT_PORTAL="${PORT_PORTAL:-8070}"
PORT_CLOUDREVE="${PORT_CLOUDREVE:-8080}"
PORT_ONLYOFFICE="${PORT_ONLYOFFICE:-8090}"
SERVER_IP="${SERVER_IP:-}"
SERVER_URL="${SERVER_URL:-}"
KEEP_WORK_DIR="${KEEP_WORK_DIR:-false}"

ZIP_CMD=""
PKG_CMD=""
PORTAL_OK=false
CLOUDREVE_OK=false
OO_OK=false

mkdir -p "$LOG_DIR"

log_info() { local msg="$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"; echo -e "\e[37m$msg\e[0m"; echo "$msg" >> "$LOG_FILE"; }
log_ok()   { local msg="$(date '+%Y-%m-%d %H:%M:%S') [ OK ] $*"; echo -e "\e[32m$msg\e[0m"; echo "$msg" >> "$LOG_FILE"; }
log_warn() { local msg="$(date '+%Y-%m-%d %H:%M:%S') [WARN] $*"; echo -e "\e[33m$msg\e[0m"; echo "$msg" >> "$LOG_FILE"; }
log_err()  { local msg="$(date '+%Y-%m-%d %H:%M:%S') [FAIL] $*"; echo -e "\e[31m$msg\e[0m"; echo "$msg" >> "$LOG_FILE"; }

on_error() {
    local line="${1:-unknown}"
    log_err "Restore failed near line $line"
    log_info "Log file: $LOG_FILE"
}
trap 'on_error $LINENO' ERR

as_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            exec sudo -E bash "$0" "$ARCHIVE"
        fi
        log_err "Please run as root: sudo bash $0 ${ARCHIVE:-/path/to/husky_trans_backup.7z}"
        exit 1
    fi
}

detect_pkg_manager() {
    if command -v dnf >/dev/null 2>&1; then
        PKG_CMD="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_CMD="yum"
    else
        log_err "Neither dnf nor yum was found. This script expects CentOS/RHEL 8+."
        exit 1
    fi
    log_ok "Package manager: $PKG_CMD"
}

pkg_install() {
    "$PKG_CMD" install -y "$@" 2>&1 | tee -a "$LOG_FILE"
}

find_archive() {
    if [ -n "$ARCHIVE" ] && [ -f "$ARCHIVE" ]; then
        return
    fi

    local latest=""
    latest="$( (ls -1t "$PWD"/husky_trans_backup_*.7z "$SCRIPT_DIR"/husky_trans_backup_*.7z 2>/dev/null || true) | head -n 1 )"
    if [ -n "$latest" ]; then
        ARCHIVE="$latest"
        log_info "Auto-detected archive: $ARCHIVE"
        return
    fi

    log_err "No backup archive specified and none found in current/script directory."
    log_err "Usage: sudo bash $0 <husky_trans_backup_YYYYMMDD_HHMMSS.7z>"
    exit 1
}

install_7zip_and_base_tools() {
    log_info "Installing base dependencies..."
    pkg_install ca-certificates curl tar gzip sed findutils coreutils shadow-utils || true

    local major=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        major="${VERSION_ID%%.*}"
    fi

    "$PKG_CMD" install -y epel-release 2>&1 | tee -a "$LOG_FILE" || {
        if [ -n "$major" ]; then
            "$PKG_CMD" install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${major}.noarch.rpm" 2>&1 | tee -a "$LOG_FILE" || true
        fi
    }

    "$PKG_CMD" makecache -y 2>&1 | tee -a "$LOG_FILE" || true
    "$PKG_CMD" install -y p7zip p7zip-plugins 2>&1 | tee -a "$LOG_FILE" || true
    "$PKG_CMD" install -y 7zip 2>&1 | tee -a "$LOG_FILE" || true

    ZIP_CMD="$(command -v 7za || command -v 7z || command -v 7zz || true)"
    if [ -z "$ZIP_CMD" ]; then
        log_err "Could not install/find a 7-Zip extractor (7za, 7z, or 7zz)."
        exit 1
    fi
    log_ok "7-Zip extractor: $ZIP_CMD"
}

install_or_start_docker() {
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker already installed: $(docker --version)"
    else
        log_info "Installing Docker Engine..."
        "$PKG_CMD" remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>&1 | tee -a "$LOG_FILE" || true
        pkg_install yum-utils dnf-plugins-core || true

        if command -v yum-config-manager >/dev/null 2>&1; then
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>&1 | tee -a "$LOG_FILE"
        else
            "$PKG_CMD" config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>&1 | tee -a "$LOG_FILE"
        fi

        pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    systemctl enable docker --now 2>&1 | tee -a "$LOG_FILE" || true

    if ! docker info >/dev/null 2>&1; then
        log_err "Docker is installed but not running or not accessible."
        exit 1
    fi
    if ! docker compose version >/dev/null 2>&1; then
        log_info "Installing Docker Compose plugin..."
        pkg_install docker-compose-plugin
    fi
    if ! docker compose version >/dev/null 2>&1; then
        log_err "Docker Compose plugin is not available."
        exit 1
    fi

    log_ok "Docker Compose: $(docker compose version)"
}

configure_firewall() {
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        log_info "Opening local firewalld ports: $PORT_PORTAL, $PORT_CLOUDREVE, $PORT_ONLYOFFICE"
        firewall-cmd --permanent --add-port="${PORT_PORTAL}/tcp" 2>&1 | tee -a "$LOG_FILE" || true
        firewall-cmd --permanent --add-port="${PORT_CLOUDREVE}/tcp" 2>&1 | tee -a "$LOG_FILE" || true
        firewall-cmd --permanent --add-port="${PORT_ONLYOFFICE}/tcp" 2>&1 | tee -a "$LOG_FILE" || true
        firewall-cmd --reload 2>&1 | tee -a "$LOG_FILE" || true
        log_ok "firewalld updated"
    else
        log_info "firewalld is not active; skipping local firewall changes"
    fi
}

extract_backup() {
    log_info "Extracting backup archive..."
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    "$ZIP_CMD" x "$ARCHIVE" -o"$WORK_DIR" -y 2>&1 | tee -a "$LOG_FILE"

    if [ ! -d "$WORK_DIR/project" ]; then
        log_err "Archive does not contain project/"
        exit 1
    fi
    if [ ! -f "$WORK_DIR/project/docker-compose.yml" ]; then
        log_err "Archive does not contain project/docker-compose.yml"
        exit 1
    fi
    log_ok "Extracted to $WORK_DIR"
}

stop_existing_stack() {
    if [ -f "$PROJECT_ROOT/docker-compose.yml" ]; then
        log_info "Stopping existing stack in $PROJECT_ROOT..."
        (cd "$PROJECT_ROOT" && docker compose down 2>&1 | tee -a "$LOG_FILE") || true
    fi

    log_info "Removing stale Husky containers, if any..."
    docker rm -f husky_portal husky_cloudreve husky_onlyoffice >/dev/null 2>&1 || true
    log_ok "Old containers cleaned"
}

restore_project_files() {
    log_info "Copying project files to $PROJECT_ROOT..."
    mkdir -p "$(dirname "$PROJECT_ROOT")"
    if [ -d "$PROJECT_ROOT" ]; then
        mv "$PROJECT_ROOT" "${PROJECT_ROOT}.before_${TIMESTAMP}"
        log_info "Previous project moved to ${PROJECT_ROOT}.before_${TIMESTAMP}"
    fi
    mkdir -p "$PROJECT_ROOT"
    cp -a "$WORK_DIR/project/." "$PROJECT_ROOT/"

    log_info "Normalizing Linux line endings and permissions..."
    find "$PROJECT_ROOT" -type f \( \
        -name "*.sh" -o -name "*.conf" -o -name "*.yml" -o -name "*.yaml" -o \
        -name "Dockerfile" -o -name ".dockerignore" -o -name "*.html" -o -name "*.js" -o -name "*.css" \
    \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true

    chmod -R a+rX "$PROJECT_ROOT" 2>/dev/null || true
    chmod +x "$PROJECT_ROOT/docker-entrypoint.sh" 2>/dev/null || true

    if [ ! -f "$PROJECT_ROOT/.dockerignore" ]; then
        log_warn ".dockerignore missing from backup; creating a safe default for cloud builds"
        cat > "$PROJECT_ROOT/.dockerignore" <<'EOF_DOCKERIGNORE'
.git/
logs/
__pycache__/
*.pyc
*.log
*.7z
*.mhtml
cloudreve_data/uploads/
cloudreve_data/*.db
cloudreve_data/*.db-*
screenshots/
EOF_DOCKERIGNORE
    fi

    if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" = "Enforcing" ] && command -v chcon >/dev/null 2>&1; then
        log_info "SELinux is enforcing; relabeling project files for Docker bind mounts..."
        chcon -Rt svirt_sandbox_file_t "$PROJECT_ROOT" 2>&1 | tee -a "$LOG_FILE" || log_warn "SELinux relabel failed; Docker bind mounts may need manual :Z labels"
    fi

    [ -f "$PROJECT_ROOT/husky.html" ] && log_ok "Portal entry found" || log_warn "husky.html not found; portal may not render"
    log_ok "Project restored"
}

restore_docker_volumes() {
    log_info "Restoring Docker volumes..."
    local backup_vols="$WORK_DIR/volumes"
    if [ ! -d "$backup_vols" ]; then
        log_warn "No volumes directory found in backup; named volumes will start fresh"
        return
    fi

    local found=false
    for vol_tar in "$backup_vols"/*.tar.gz; do
        [ -f "$vol_tar" ] || continue
        found=true
        local vol_name
        vol_name="$(basename "$vol_tar" .tar.gz)"
        log_info "Restoring volume: $vol_name"
        docker volume create "$vol_name" >/dev/null
        docker run --rm -v "${vol_name}:/dest" -v "$backup_vols:/src:ro" alpine sh -c "rm -rf /dest/* /dest/..?* /dest/.[!.]* 2>/dev/null || true; tar xzf /src/${vol_name}.tar.gz -C /dest" 2>&1 | tee -a "$LOG_FILE"
        log_ok "$vol_name restored"
    done

    [ "$found" = true ] || log_warn "No *.tar.gz volume archives found"
}

detect_server_url() {
    if [ -n "$SERVER_URL" ]; then
        SERVER_URL="${SERVER_URL%/}"
        return
    fi

    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="$(curl -fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)"
    fi
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    fi

    if [ -n "$SERVER_IP" ]; then
        SERVER_URL="http://${SERVER_IP}"
    else
        SERVER_URL="http://host.docker.internal"
        log_warn "Could not detect server IP. Set SERVER_URL=http://your-domain-or-ip before running restore."
    fi
}

configure_cloudreve_wopi() {
    local conf="$PROJECT_ROOT/cloudreve_data/conf.ini"
    local discovery_url="${SERVER_URL}:${PORT_ONLYOFFICE}/hosting/discovery"

    if [ ! -f "$conf" ]; then
        log_warn "Cloudreve config not found at $conf; WOPI DiscoveryUrl was not updated"
        return
    fi

    log_info "Setting Cloudreve WOPI DiscoveryUrl to $discovery_url"
    if grep -q '^DiscoveryUrl[[:space:]]*=' "$conf"; then
        sed -i "s|^DiscoveryUrl[[:space:]]*=.*|DiscoveryUrl = ${discovery_url}|" "$conf"
    elif grep -q '^\[WOPI\]' "$conf"; then
        sed -i "/^\[WOPI\]/a DiscoveryUrl = ${discovery_url}" "$conf"
    else
        cat >> "$conf" <<EOF_WOPI

[WOPI]
Enabled = true
DiscoveryUrl = ${discovery_url}
EOF_WOPI
    fi

    if grep -q '^Enabled[[:space:]]*=' "$conf"; then
        sed -i '/^\[WOPI\]/,/^\[/ s|^Enabled[[:space:]]*=.*|Enabled = true|' "$conf"
    fi
    log_ok "Cloudreve WOPI configured"
}

start_stack() {
    log_info "Validating Docker Compose config..."
    cd "$PROJECT_ROOT"
    docker compose config >/dev/null

    log_info "Pulling images..."
    docker compose pull 2>&1 | tee -a "$LOG_FILE" || true

    log_info "Building and starting husky-trans..."
    docker compose up -d --build 2>&1 | tee -a "$LOG_FILE"
}

wait_for_services() {
    log_info "Waiting for services to respond (up to 180s)..."
    for i in $(seq 1 36); do
        sleep 5

        if [ "$PORTAL_OK" = false ] && curl -sf "http://localhost:${PORT_PORTAL}/husky.html" >/dev/null 2>&1; then
            PORTAL_OK=true
            log_ok "Portal responding at :$PORT_PORTAL"
        fi
        if [ "$CLOUDREVE_OK" = false ] && curl -sf "http://localhost:${PORT_CLOUDREVE}/" >/dev/null 2>&1; then
            CLOUDREVE_OK=true
            log_ok "Cloudreve responding at :$PORT_CLOUDREVE"
        fi
        if [ "$OO_OK" = false ] && curl -sf "http://localhost:${PORT_ONLYOFFICE}/welcome/" >/dev/null 2>&1; then
            OO_OK=true
            log_ok "OnlyOffice responding at :$PORT_ONLYOFFICE"
        fi

        [ "$PORTAL_OK" = true ] && [ "$CLOUDREVE_OK" = true ] && [ "$OO_OK" = true ] && return
    done

    log_warn "Some services did not pass HTTP checks in time. Recent container status:"
    (cd "$PROJECT_ROOT" && docker compose ps 2>&1 | tee -a "$LOG_FILE") || true
}

print_summary() {
    cat <<EOF_SUMMARY

=========================================================
  HUSKY TRANSLATE - Restore Complete
=========================================================
Project     : $PROJECT_ROOT
Portal      : ${SERVER_URL}:${PORT_PORTAL}
Cloudreve   : ${SERVER_URL}:${PORT_CLOUDREVE}
OnlyOffice  : ${SERVER_URL}:${PORT_ONLYOFFICE}
Log         : $LOG_FILE

Status:
  Portal     (:$PORT_PORTAL)      : $PORTAL_OK
  Cloudreve  (:$PORT_CLOUDREVE)   : $CLOUDREVE_OK
  OnlyOffice (:$PORT_ONLYOFFICE)  : $OO_OK

Common commands:
  cd $PROJECT_ROOT && docker compose ps
  cd $PROJECT_ROOT && docker compose logs -f
  cd $PROJECT_ROOT && docker compose restart

Cloud note:
  Also open TCP $PORT_PORTAL, $PORT_CLOUDREVE, and $PORT_ONLYOFFICE in your cloud provider security group.
=========================================================

EOF_SUMMARY
}

main() {
    log_info "========================================="
    log_info "  HUSKY TRANSLATE Restore (CentOS/RHEL)"
    log_info "========================================="

    find_archive
    as_root
    detect_pkg_manager
    log_info "Archive : $ARCHIVE"
    log_info "Project : $PROJECT_ROOT"

    install_7zip_and_base_tools
    install_or_start_docker
    configure_firewall
    extract_backup
    stop_existing_stack
    restore_project_files
    restore_docker_volumes
    detect_server_url
    configure_cloudreve_wopi
    start_stack
    wait_for_services

    if [ "$KEEP_WORK_DIR" != "true" ]; then
        rm -rf "$WORK_DIR"
    fi

    print_summary | tee -a "$LOG_FILE"

    if [ "$PORTAL_OK" = true ] && [ "$CLOUDREVE_OK" = true ] && [ "$OO_OK" = true ]; then
        log_ok "Restore finished successfully"
        exit 0
    fi

    log_warn "Restore finished, but one or more health checks are not ready yet"
    exit 1
}

main "$@"
