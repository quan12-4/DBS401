#!/usr/bin/env bash
#
# DBS401 SQL Injection Automated Setup
# ==================================================
# Installs & configures everything needed to run the
# intentionally-vulnerable Task Manager on a fresh Debian/Ubuntu VM.
#
# Usage:  sudo bash setup.sh
#

set -u

# ──────────────────────────────────────────────
# 0.  Configuration
# ──────────────────────────────────────────────
REPO_URL="https://github.com/quan12-4/DBS401.git"
REPO_BRANCH="main"
DB_NAME="task_manager"
DB_USER="taskmgr_user"
DB_PASS=""                              # auto-generated below if empty
SITE_DIR="/var/www/html/task-manager"

# ──────────────────────────────────────────────
# 1.  Preliminaries
# ──────────────────────────────────────────────
log()  { printf "\e[32m[*]\e[0m %s\n" "$*"; }
warn() { printf "\e[33m[!]\e[0m %s\n" "$*"; }
err()  { printf "\e[31m[-]\e[0m %s\n" "$*"; }

if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)."
    exit 1
fi

if [[ -z "${DB_PASS}" ]]; then
    DB_PASS="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 20 | head -n1 2>/dev/null)"
    DB_PASS_TASKS_RO="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 20 | head -n1 2>/dev/null)"
    DB_PASS_TASKS_RW="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 20 | head -n1 2>/dev/null)"
    DB_PASS_AUTH="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 20 | head -n1 2>/dev/null)"
    DB_PASS_USER_LOOKUP="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 20 | head -n1 2>/dev/null)"
    DB_PASS_USER_ERROR="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 20 | head -n1 2>/dev/null)"
    DB_PASS_PROFILE="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 20 | head -n1 2>/dev/null)"
    DB_PASS_FEEDBACK="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 20 | head -n1 2>/dev/null)"
fi

log "DBS401 SQL Injection Automated Setup"
log "Target: ${SITE_DIR}"
echo ""

# ──────────────────────────────────────────────
# 2.  OS Detection & Package Helpers
# ──────────────────────────────────────────────
OS_SUPPORTED=0
if [[ -f /etc/os-release ]]; then
    grep -qiE 'debian|ubuntu' /etc/os-release 2>/dev/null && OS_SUPPORTED=1
fi
if [[ $OS_SUPPORTED -eq 0 && -f /etc/lsb-release ]]; then
    grep -qiE 'debian|ubuntu' /etc/lsb-release 2>/dev/null && OS_SUPPORTED=1
fi

if [[ $OS_SUPPORTED -eq 0 ]]; then
    err "Unsupported OS – this script targets Debian / Ubuntu."
    exit 1
fi

pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -qc "install ok installed" || return 1
    return 0
}

pkg_ensure() {
    local pkg="$1"
    if pkg_installed "${pkg}"; then
        log "${pkg}  already installed"
        return 0
    fi
    log "Installing ${pkg} ..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkg}" 2>&1 || {
        warn "Failed to install ${pkg} — continuing anyway"
        return 1
    }
}

start_service() {
    local svc="$1"

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "${svc}" 2>/dev/null; then
            log "${svc} already running"
            return 0
        fi

        if systemctl start "${svc}" 2>/dev/null; then
            log "Started ${svc} with systemctl"
            return 0
        fi
    fi

    if command -v service >/dev/null 2>&1; then
        if service "${svc}" status >/dev/null 2>&1; then
            log "${svc} already running"
            return 0
        fi

        if service "${svc}" start 2>/dev/null; then
            log "Started ${svc} with service"
            return 0
        fi
    fi

    if [[ -x "/etc/init.d/${svc}" ]]; then
        if "/etc/init.d/${svc}" start 2>/dev/null; then
            log "Started ${svc} with init script"
            return 0
        fi
    fi

    warn "Could not start ${svc} automatically"
    return 1
}

prepare_mariadb_runtime_dir() {
    mkdir -p /run/mysqld 2>/dev/null || true
    chown -R mysql:mysql /run/mysqld 2>/dev/null || true
}

# ──────────────────────────────────────────────
# 3.  Install System Dependencies
# ──────────────────────────────────────────────
log "Updating package lists ..."
apt-get update -qq 2>&1 || warn "apt-get update failed — network might be unavailable"

log "Checking / installing dependencies ..."

# Apache
pkg_ensure "apache2"

# MariaDB server
if ! pkg_installed "mariadb-server" && ! pkg_installed "mysql-server"; then
    pkg_ensure "mariadb-server"
    pkg_ensure "mariadb-client"
else
    log "MySQL/MariaDB server already installed"
fi

# PHP + Apache module + MySQL extension
pkg_ensure "php"
pkg_ensure "libapache2-mod-php"
pkg_ensure "php-mysql"

# Utilities
pkg_ensure "git"
pkg_ensure "unzip"

# ──────────────────────────────────────────────
# 4.  Ensure Services Are Running
# ──────────────────────────────────────────────
echo ""
log "Starting services ..."

start_service "apache2" || true

prepare_mariadb_runtime_dir
if ! start_service "mariadb"; then
    start_service "mysql" || warn "Could not start MySQL/MariaDB"
fi

# ──────────────────────────────────────────────
# 5.  Clone / Update Source Code
# ──────────────────────────────────────────────
echo ""
log "Fetching source code from ${REPO_URL} ..."

if echo "${REPO_URL}" | grep -q "GITHUB_USERNAME"; then
    warn "REPO_URL still points to placeholder — check setup.sh line 15"
    warn "Using local files instead (must be run from the repo directory)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "${SCRIPT_DIR}/task_manager.sql" || -f "${SCRIPT_DIR}/task_manager.db" ]]; then
    log "Found local files in ${SCRIPT_DIR}. Copying..."
    mkdir -p "${SITE_DIR}" "${SITE_DIR}/config" "${SITE_DIR}/css"
    cp "${SCRIPT_DIR}"/*.php "${SITE_DIR}/" 2>/dev/null
    cp "${SCRIPT_DIR}"/*.sql "${SITE_DIR}/" 2>/dev/null
    cp "${SCRIPT_DIR}"/*.db "${SITE_DIR}/" 2>/dev/null
    cp "${SCRIPT_DIR}"/*.md "${SITE_DIR}/" 2>/dev/null
    cp "${SCRIPT_DIR}/config/constants.php" "${SITE_DIR}/config/" 2>/dev/null
    cp "${SCRIPT_DIR}/css/style.css" "${SITE_DIR}/css/" 2>/dev/null
    cp "${SCRIPT_DIR}/setup.sh" "${SITE_DIR}/" 2>/dev/null
    else
        err "No local files found and REPO_URL has placeholder — edit setup.sh first"
        exit 1
    fi
else
    if [[ -d "${SITE_DIR}" ]]; then
        log "Directory exists — removing to perform a fresh clone ..."
        rm -rf "${SITE_DIR}"
    fi
    git clone --branch "${REPO_BRANCH}" --depth 1 "${REPO_URL}" "${SITE_DIR}" 2>&1 || {
        err "Failed to clone repository — check REPO_URL and network"
        exit 1
    }
fi

# ──────────────────────────────────────────────
# 6.  Configure Database
# ──────────────────────────────────────────────
echo ""
log "Configuring database ..."

# Create database (idempotent)
mysql -u root -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" 2>&1
mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" 2>&1 || {
    err "Failed to create database — is MySQL running?"
    exit 1
}

# Create specific least-privilege users
for role in db_tasks_ro db_tasks_rw db_auth db_user_lookup db_user_error db_profile db_feedback; do
    mysql -u root -e "DROP USER IF EXISTS '${role}'@'localhost';" 2>&1
done

mysql -u root -e "CREATE USER 'db_tasks_ro'@'localhost' IDENTIFIED BY '${DB_PASS_TASKS_RO}';" 2>&1 || { err "Failed to create user db_tasks_ro"; exit 1; }
mysql -u root -e "CREATE USER 'db_tasks_rw'@'localhost' IDENTIFIED BY '${DB_PASS_TASKS_RW}';" 2>&1 || { err "Failed to create user db_tasks_rw"; exit 1; }
mysql -u root -e "CREATE USER 'db_auth'@'localhost' IDENTIFIED BY '${DB_PASS_AUTH}';" 2>&1 || { err "Failed to create user db_auth"; exit 1; }
mysql -u root -e "CREATE USER 'db_user_lookup'@'localhost' IDENTIFIED BY '${DB_PASS_USER_LOOKUP}';" 2>&1 || { err "Failed to create user db_user_lookup"; exit 1; }
mysql -u root -e "CREATE USER 'db_user_error'@'localhost' IDENTIFIED BY '${DB_PASS_USER_ERROR}';" 2>&1 || { err "Failed to create user db_user_error"; exit 1; }
mysql -u root -e "CREATE USER 'db_profile'@'localhost' IDENTIFIED BY '${DB_PASS_PROFILE}';" 2>&1 || { err "Failed to create user db_profile"; exit 1; }
mysql -u root -e "CREATE USER 'db_feedback'@'localhost' IDENTIFIED BY '${DB_PASS_FEEDBACK}';" 2>&1 || { err "Failed to create user db_feedback"; exit 1; }

# Import schema & seed data
if [[ -f "${SITE_DIR}/task_manager.db" ]]; then
    php -r '$k="nhom4_dbs401"; $d=base64_decode(file_get_contents("'${SITE_DIR}'/task_manager.db")); for($i=0;$i<strlen($d);$i++) echo $d[$i]^$k[$i%strlen($k)];' | mysql -u root "${DB_NAME}" 2>&1
    rm -f "${SITE_DIR}/task_manager.db"
    log "Schema imported from encrypted DB file"
elif [[ -f "${SITE_DIR}/task_manager.sql" ]]; then
    mysql -u root "${DB_NAME}" < "${SITE_DIR}/task_manager.sql" 2>&1
    rm -f "${SITE_DIR}/task_manager.sql"
    log "Schema imported"
else
    warn "Database schema not found - skipping DB import"
fi

# Grant restricted privileges
mysql -u root -e "GRANT SELECT ON \`${DB_NAME}\`.tbl_tasks TO 'db_tasks_ro'@'localhost';" 2>&1
mysql -u root -e "GRANT SELECT ON \`${DB_NAME}\`.tbl_lists TO 'db_tasks_ro'@'localhost';" 2>&1

mysql -u root -e "GRANT SELECT, INSERT, UPDATE, DELETE ON \`${DB_NAME}\`.tbl_tasks TO 'db_tasks_rw'@'localhost';" 2>&1
mysql -u root -e "GRANT SELECT, INSERT, UPDATE, DELETE ON \`${DB_NAME}\`.tbl_lists TO 'db_tasks_rw'@'localhost';" 2>&1

mysql -u root -e "GRANT SELECT (user_id, username, password, role), INSERT ON \`${DB_NAME}\`.tbl_users TO 'db_auth'@'localhost';" 2>&1

mysql -u root -e "GRANT SELECT (user_id, username, role) ON \`${DB_NAME}\`.tbl_users TO 'db_user_lookup'@'localhost';" 2>&1

mysql -u root -e "GRANT SELECT ON \`${DB_NAME}\`.tbl_tasks TO 'db_user_error'@'localhost';" 2>&1
mysql -u root -e "GRANT SELECT ON \`${DB_NAME}\`.tbl_lists TO 'db_user_error'@'localhost';" 2>&1
mysql -u root -e "GRANT SELECT ON \`${DB_NAME}\`.vw_error_flag TO 'db_user_error'@'localhost';" 2>&1

mysql -u root -e "GRANT SELECT (user_id, username, email, role), UPDATE (username, email) ON \`${DB_NAME}\`.tbl_users TO 'db_profile'@'localhost';" 2>&1
mysql -u root -e "GRANT SELECT ON \`${DB_NAME}\`.vw_time_flag TO 'db_profile'@'localhost';" 2>&1

mysql -u root -e "GRANT INSERT ON \`${DB_NAME}\`.tbl_feedback TO 'db_feedback'@'localhost';" 2>&1

mysql -u root -e "FLUSH PRIVILEGES;" 2>&1

# ──────────────────────────────────────────────
# 7.  Write Application Configuration
# ──────────────────────────────────────────────
echo ""
log "Writing application config ..."

mkdir -p "${SITE_DIR}/config"

cat > "${SITE_DIR}/config/constants.php" <<'CONFIGEOF'
<?php
session_start();

define('LOCALHOST', 'localhost');
define('DB_NAME', 'DB_NAME_PLACEHOLDER');

define('DB_USER_TASKS_RO', 'db_tasks_ro');
define('DB_PASS_TASKS_RO', 'DB_PASS_TASKS_RO_PLACEHOLDER');

define('DB_USER_TASKS_RW', 'db_tasks_rw');
define('DB_PASS_TASKS_RW', 'DB_PASS_TASKS_RW_PLACEHOLDER');

define('DB_USER_AUTH', 'db_auth');
define('DB_PASS_AUTH', 'DB_PASS_AUTH_PLACEHOLDER');

define('DB_USER_LOOKUP', 'db_user_lookup');
define('DB_PASS_LOOKUP', 'DB_PASS_USER_LOOKUP_PLACEHOLDER');

define('DB_USER_ERROR', 'db_user_error');
define('DB_PASS_ERROR', 'DB_PASS_USER_ERROR_PLACEHOLDER');

define('DB_USER_PROFILE', 'db_profile');
define('DB_PASS_PROFILE', 'DB_PASS_PROFILE_PLACEHOLDER');

define('DB_USER_FEEDBACK', 'db_feedback');
define('DB_PASS_FEEDBACK', 'DB_PASS_FEEDBACK_PLACEHOLDER');

$proto = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
if (!empty($_SERVER['HTTP_X_FORWARDED_PROTO'])) {
    $proto = trim(explode(',', $_SERVER['HTTP_X_FORWARDED_PROTO'])[0]);
} elseif (!empty($_SERVER['REQUEST_SCHEME'])) {
    $proto = $_SERVER['REQUEST_SCHEME'];
}

$host = $_SERVER['HTTP_HOST'];
if (!empty($_SERVER['HTTP_X_FORWARDED_HOST'])) {
    $host = trim(explode(',', $_SERVER['HTTP_X_FORWARDED_HOST'])[0]);
}

$dir = rtrim(dirname($_SERVER['SCRIPT_NAME']), '/\\');
define('SITEURL', "$proto://$host$dir/");

// Require login for all pages except login.php and signup.php
if (!isset($_SESSION['user']) && basename($_SERVER['PHP_SELF']) != 'login.php' && basename($_SERVER['PHP_SELF']) != 'signup.php') {
    header("Location: ".SITEURL."login.php");
    exit;
}

if (isset($_SESSION['user']) && !isset($_SESSION['user_id'])) {
    $conn_init = mysqli_connect(LOCALHOST, DB_USER_AUTH, DB_PASS_AUTH);
    if ($conn_init) {
        mysqli_select_db($conn_init, DB_NAME);
        $user_esc = mysqli_real_escape_string($conn_init, $_SESSION['user']);
        $res_init = mysqli_query($conn_init, "SELECT user_id FROM tbl_users WHERE username = '$user_esc'");
        if ($res_init && $row_init = mysqli_fetch_assoc($res_init)) {
            $_SESSION['user_id'] = $row_init['user_id'];
        }
        mysqli_close($conn_init);
    }
}
CONFIGEOF

sed -i "s/DB_NAME_PLACEHOLDER/${DB_NAME}/g" "${SITE_DIR}/config/constants.php"
sed -i "s/DB_PASS_TASKS_RO_PLACEHOLDER/${DB_PASS_TASKS_RO}/g" "${SITE_DIR}/config/constants.php"
sed -i "s/DB_PASS_TASKS_RW_PLACEHOLDER/${DB_PASS_TASKS_RW}/g" "${SITE_DIR}/config/constants.php"
sed -i "s/DB_PASS_AUTH_PLACEHOLDER/${DB_PASS_AUTH}/g" "${SITE_DIR}/config/constants.php"
sed -i "s/DB_PASS_USER_LOOKUP_PLACEHOLDER/${DB_PASS_USER_LOOKUP}/g" "${SITE_DIR}/config/constants.php"
sed -i "s/DB_PASS_USER_ERROR_PLACEHOLDER/${DB_PASS_USER_ERROR}/g" "${SITE_DIR}/config/constants.php"
sed -i "s/DB_PASS_PROFILE_PLACEHOLDER/${DB_PASS_PROFILE}/g" "${SITE_DIR}/config/constants.php"
sed -i "s/DB_PASS_FEEDBACK_PLACEHOLDER/${DB_PASS_FEEDBACK}/g" "${SITE_DIR}/config/constants.php"

log "config/constants.php updated"

# ──────────────────────────────────────────────
# 8.  Set Permissions
# ──────────────────────────────────────────────
echo ""
log "Setting file permissions ..."
chown -R www-data:www-data "${SITE_DIR}" 2>/dev/null || warn "Could not set ownership"
find "${SITE_DIR}" -type d -exec chmod 755 {} \; 2>/dev/null
find "${SITE_DIR}" -type f -exec chmod 644 {} \; 2>/dev/null

# ──────────────────────────────────────────────
# 9.  Restart Apache
# ──────────────────────────────────────────────
echo ""
log "Restarting Apache ..."
systemctl restart apache2 2>&1 || warn "Could not restart apache2"

# ──────────────────────────────────────────────
# 10. Summary
# ──────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       DBS401 SQL Injection Playground — Ready!           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Local access:  http://localhost/task-manager/"
echo "  LAN access:    http://$(hostname -I 2>/dev/null | awk '{print $1}')/task-manager/"
echo "  (SITEURL auto-detects the IP — other machines on your"
echo "  LAN can reach it at the VM's IP shown above.)"
echo ""
echo "  [!] The application uses a Least Privilege Database Architecture."
echo "  Different features use different DB accounts to enforce isolation!"
echo "  You may need the shortcut Ctrl+Shift+I to find something interesting!"
echo ""

log "Setup complete."