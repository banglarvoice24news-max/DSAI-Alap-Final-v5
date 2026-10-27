#!/usr/bin/env bash
set -euo pipefail
DOMAIN="${DOMAIN:-dsaialap.banglarvoice24news.com}"
EMAIL="${EMAIL:-admin@${DOMAIN}}"
docker compose -f docker-compose.prod.yml run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d "$DOMAIN" \
  --email "$EMAIL" \
  --agree-tos \
  --no-eff-email
docker compose -f docker-compose.prod.yml exec nginx nginx -s reload
