# WordPress Docker FPM + Nginx

Production-ready WordPress stack using PHP-FPM, Nginx, and MariaDB — fully containerized with Docker Compose. Includes an auto setup script with optional Let's Encrypt SSL.

## Stack

| Service  | Image                          |
|----------|--------------------------------|
| Nginx    | `nginx:alpine`                 |
| PHP-FPM  | `wordpress:php8.3-fpm-alpine`  |
| Database | `mariadb:11`                   |
| Redis    | `redis:alpine`                 |
| SSL      | `certbot/certbot`              |
| WP-CLI   | `wordpress:cli`                |

---

## Project Structure

```
.
├── docker-compose.yml
├── setup.sh                  # Auto setup script
├── .env.example              # Environment variable template
├── nginx/
│   ├── nginx.conf            # Main Nginx config
│   └── conf.d/
│       └── wordpress.conf    # WordPress virtual host
├── php/
│   ├── Dockerfile            # PHP-FPM image with extensions
│   └── php.ini               # Custom PHP settings
└── wordpress/                # WordPress files (auto-created, git-ignored)
```

---

## Quick Start (Auto Setup)

```bash
git clone https://github.com/nooblk-98/wordpress-docker-fpm-nginx.git
cd wordpress-docker-fpm-nginx
sudo bash setup.sh
```

The script will:
- Prompt for your domain, email, and DB credentials
- Generate `.env` from `.env.example`
- Build and start all containers
- Set correct file permissions
- Optionally obtain a Let's Encrypt SSL certificate

---

## Manual Installation Guide

### 1. Clone the repository

```bash
git clone https://github.com/nooblk-98/wordpress-docker-fpm-nginx.git
cd wordpress-docker-fpm-nginx
```

### 2. Configure environment variables

```bash
cp .env.example .env
nano .env
```

Edit the following values:

```env
NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443

DB_NAME=wordpress
DB_USER=wpuser
DB_PASSWORD=your_strong_password
DB_ROOT_PASSWORD=your_root_password

DOMAIN=yourdomain.com
EMAIL=admin@yourdomain.com
```

### 3. Update Nginx server_name

Edit [nginx/conf.d/wordpress.conf](nginx/conf.d/wordpress.conf) and replace `_` with your domain:

```nginx
server_name yourdomain.com www.yourdomain.com;
```

### 4. Build and start containers

```bash
docker compose up -d --build
```

### 5. Verify containers are running

```bash
docker compose ps
```

Expected output:

```
NAME          IMAGE                          STATUS
wp_nginx      nginx:alpine                   Up
wp_php        wordpress-docker-fpm-nginx-php Up
wp_db         mariadb:11                     Up
```

### 6. Set WordPress file permissions

```bash
docker compose exec php chown -R www-data:www-data /var/www/html
docker compose exec php find /var/www/html -type d -exec chmod 755 {} \;
docker compose exec php find /var/www/html -type f -exec chmod 644 {} \;
```

### 7. Complete WordPress installation

Visit `http://yourdomain.com` in your browser and follow the WordPress setup wizard.

---

## Redis Object Cache

Redis is included in the stack for persistent object caching. After the containers are running, enable it with WP-CLI:

```bash
docker compose --profile tools run --rm wpcli wp plugin install redis-cache --activate
docker compose --profile tools run --rm wpcli wp redis enable
```

Verify Redis is connected:

```bash
docker compose --profile tools run --rm wpcli wp redis status
```

> Redis memory limit is controlled by `REDIS_MAXMEMORY` in `.env` (default: `128mb`).

---

## WP-CLI

Run any WP-CLI command without entering the container:

```bash
docker compose --profile tools run --rm wpcli wp <command>
```

Common examples:

| Action                  | Command                                                                 |
|-------------------------|-------------------------------------------------------------------------|
| List plugins            | `docker compose --profile tools run --rm wpcli wp plugin list`         |
| Update all plugins      | `docker compose --profile tools run --rm wpcli wp plugin update --all` |
| Flush cache             | `docker compose --profile tools run --rm wpcli wp cache flush`         |
| Search-replace URL      | `docker compose --profile tools run --rm wpcli wp search-replace 'old.com' 'new.com'` |
| Create admin user       | `docker compose --profile tools run --rm wpcli wp user create admin admin@example.com --role=administrator` |

---

## SSL Setup (Let's Encrypt)

### Prerequisites
- Domain DNS must point to your server's IP
- Port 80 must be publicly accessible

### Obtain certificate

```bash
docker compose run --rm certbot certonly \
    --webroot --webroot-path=/var/www/certbot \
    --email admin@yourdomain.com \
    --agree-tos --no-eff-email \
    -d yourdomain.com -d www.yourdomain.com
```

### Enable HTTPS in Nginx

Edit [nginx/conf.d/wordpress.conf](nginx/conf.d/wordpress.conf):

1. Uncomment `return 301 https://...` inside the HTTP block
2. Uncomment the entire `server { listen 443 ... }` block
3. Replace `yourdomain.com` with your actual domain
4. Reload Nginx:

```bash
docker compose exec nginx nginx -s reload
```

### Auto-renew SSL

The `certbot` container is configured to auto-renew every 12 hours. It runs as a background service when the stack is up.

To manually trigger renewal:

```bash
docker compose up certbot
```

---

## Common Commands

| Action                  | Command                                                                        |
|-------------------------|--------------------------------------------------------------------------------|
| Start stack             | `docker compose up -d`                                                         |
| Stop stack              | `docker compose down`                                                          |
| View logs               | `docker compose logs -f`                                                       |
| Nginx logs              | `docker compose logs -f nginx`                                                 |
| PHP logs                | `docker compose logs -f php`                                                   |
| Restart Nginx           | `docker compose restart nginx`                                                 |
| Reload Nginx config     | `docker compose exec nginx nginx -s reload`                                    |
| MySQL shell             | `docker compose exec db mysql -u wpuser -p`                                    |
| PHP shell               | `docker compose exec php bash`                                                 |
| Rebuild PHP image       | `docker compose build php`                                                     |
| Redis CLI               | `docker compose exec redis redis-cli`                                          |
| Flush Redis cache       | `docker compose --profile tools run --rm wpcli wp cache flush`                 |
| Run WP-CLI command      | `docker compose --profile tools run --rm wpcli wp <command>`                   |

---

## Configuration

### PHP settings

Edit [php/php.ini](php/php.ini) to adjust:
- `memory_limit` (default: 256M)
- `upload_max_filesize` (default: 64M)
- `max_execution_time` (default: 300s)
- OPcache settings

After changes, rebuild the PHP container:

```bash
docker compose build php && docker compose up -d php
```

### Nginx settings

Edit [nginx/nginx.conf](nginx/nginx.conf) for global settings or [nginx/conf.d/wordpress.conf](nginx/conf.d/wordpress.conf) for site-specific config.

Reload without downtime:

```bash
docker compose exec nginx nginx -s reload
```

---

## Backup & Restore

### Backup database

```bash
docker compose exec db mysqldump -u wpuser -p wordpress > backup_$(date +%F).sql
```

### Restore database

```bash
cat backup_2025-01-01.sql | docker compose exec -T db mysql -u wpuser -p wordpress
```

### Backup WordPress files

```bash
tar -czf wordpress_files_$(date +%F).tar.gz wordpress/
```

---

## Troubleshooting

**502 Bad Gateway**
- PHP-FPM container may not be ready. Check: `docker compose logs php`

**Database connection error**
- Verify `.env` credentials match. Check: `docker compose logs db`

**Permission denied on uploads**
- Re-run the permissions fix from step 6.

**SSL certificate failed**
- Ensure DNS is propagated and port 80 is open on your firewall.

**Redis not connecting**
- Check Redis is running: `docker compose logs redis`
- Verify status inside WordPress: `docker compose --profile tools run --rm wpcli wp redis status`

---

## License

MIT
