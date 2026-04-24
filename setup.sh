#!/usr/bin/env bash
set -euo pipefail

# ─── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }

# ─── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║   WordPress FPM + Nginx Docker Setup         ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"

# ─── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Run this script as root or with sudo."

# ─── Dependency checks ─────────────────────────────────────────────────────────
check_dep() {
    command -v "$1" &>/dev/null || error "$1 is not installed. Please install it first."
}
check_dep docker
check_dep docker compose 2>/dev/null || check_dep docker-compose

# ─── .env setup ────────────────────────────────────────────────────────────────
if [[ ! -f .env ]]; then
    info "No .env file found. Creating from .env.example..."
    cp .env.example .env

    echo
    read -rp "$(echo -e "${BOLD}Enter your domain name (e.g. example.com): ${RESET}")" DOMAIN
    read -rp "$(echo -e "${BOLD}Enter admin email for SSL (e.g. admin@example.com): ${RESET}")" EMAIL
    read -rp "$(echo -e "${BOLD}Enter DB password (leave blank for random): ${RESET}")" DB_PASS

    DB_PASS=${DB_PASS:-$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)}
    DB_ROOT_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)

    sed -i "s/yourdomain\.com/${DOMAIN}/g" .env
    sed -i "s/admin@yourdomain\.com/${EMAIL}/g" .env
    sed -i "s/change_me_strong_password/${DB_PASS}/g" .env
    sed -i "s/change_me_root_password/${DB_ROOT_PASS}/g" .env

    success ".env configured."
    warn "Your DB password: ${DB_PASS}"
    warn "Your DB root password: ${DB_ROOT_PASS}"
    echo
else
    info ".env already exists. Skipping configuration."
    source .env
    DOMAIN="${DOMAIN:-localhost}"
    EMAIL="${EMAIL:-admin@example.com}"
fi

# ─── Update Nginx server_name ───────────────────────────────────────────────────
info "Updating Nginx config with domain: ${DOMAIN}"
sed -i "s/server_name _;/server_name ${DOMAIN} www.${DOMAIN};/" nginx/conf.d/wordpress.conf

# ─── Build & Start containers ──────────────────────────────────────────────────
info "Building and starting Docker containers..."
docker compose up -d --build

# ─── Wait for DB ───────────────────────────────────────────────────────────────
info "Waiting for MariaDB to be ready..."
for i in $(seq 1 30); do
    if docker compose exec -T db mysqladmin ping -h localhost --silent 2>/dev/null; then
        success "MariaDB is ready."
        break
    fi
    [[ $i -eq 30 ]] && error "MariaDB did not become ready in time."
    sleep 2
done

# ─── WordPress file permissions ────────────────────────────────────────────────
info "Setting WordPress file permissions..."
docker compose exec -T php chown -R www-data:www-data /var/www/html
docker compose exec -T php find /var/www/html -type d -exec chmod 755 {} \;
docker compose exec -T php find /var/www/html -type f -exec chmod 644 {} \;
success "Permissions set."

# ─── Optional SSL setup ────────────────────────────────────────────────────────
echo
read -rp "$(echo -e "${BOLD}Set up SSL with Let's Encrypt? [y/N]: ${RESET}")" DO_SSL
if [[ "${DO_SSL,,}" == "y" ]]; then
    info "Requesting SSL certificate for ${DOMAIN}..."
    docker compose run --rm certbot certonly \
        --webroot --webroot-path=/var/www/certbot \
        --email "${EMAIL}" \
        --agree-tos --no-eff-email \
        -d "${DOMAIN}" -d "www.${DOMAIN}"

    info "Enabling HTTPS in Nginx config..."
    CONF="nginx/conf.d/wordpress.conf"
    # Uncomment the HTTPS block
    sed -i 's|# return 301|return 301|' "$CONF"
    sed -i 's|# server {|server {|' "$CONF"
    sed -i "s|# *yourdomain\.com|    server_name ${DOMAIN} www.${DOMAIN};|" "$CONF"
    sed -i "s|# *ssl_certificate |    ssl_certificate |g" "$CONF"
    sed -i "s|/etc/letsencrypt/live/yourdomain\.com/|/etc/letsencrypt/live/${DOMAIN}/|g" "$CONF"
    sed -i 's|# *ssl_|    ssl_|g' "$CONF"
    sed -i 's|# *location|    location|g' "$CONF"
    sed -i 's|# *fastcgi_|        fastcgi_|g' "$CONF"
    sed -i 's|# *include fastcgi|        include fastcgi|g' "$CONF"
    sed -i 's|# *try_files|        try_files|g' "$CONF"
    sed -i 's|# *expires|        expires|g' "$CONF"
    sed -i 's|# *log_not_found|        log_not_found|g' "$CONF"
    sed -i 's|# *deny all|        deny all|g' "$CONF"
    sed -i 's|# *}|    }|g' "$CONF"

    docker compose exec nginx nginx -s reload
    success "SSL enabled and Nginx reloaded."
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo
echo -e "${GREEN}${BOLD}Setup complete!${RESET}"
echo -e "  Site URL : ${CYAN}http://${DOMAIN}${RESET}"
[[ "${DO_SSL,,}" == "y" ]] && echo -e "  Secure   : ${CYAN}https://${DOMAIN}${RESET}"
echo -e "  WP Admin : ${CYAN}http://${DOMAIN}/wp-admin${RESET}"
echo
echo -e "${YELLOW}Next steps:${RESET}"
echo "  1. Visit your site URL to complete WordPress installation."
echo "  2. Review nginx/conf.d/wordpress.conf for any additional tuning."
echo "  3. To renew SSL: docker compose up certbot"
echo
