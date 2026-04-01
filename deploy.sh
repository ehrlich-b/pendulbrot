#!/bin/bash
set -e

SERVER="root@104.131.94.68"
REMOTE_DIR="/var/www/pendulbrot"
NGINX_CONF="/etc/nginx/sites-enabled/pendulbrot.ehrlich.dev.conf"

ssh $SERVER "mkdir -p $REMOTE_DIR"
scp index.html $SERVER:$REMOTE_DIR/

# Ensure nginx config exists
ssh $SERVER "test -f $NGINX_CONF || cat > $NGINX_CONF << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name pendulbrot.ehrlich.dev;
    root /var/www/pendulbrot;
    index index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF"

ssh $SERVER "nginx -t && nginx -s reload"

echo "Deployed to pendulbrot.ehrlich.dev"
