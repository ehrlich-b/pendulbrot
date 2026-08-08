#!/bin/bash
set -e

SERVER="root@104.131.94.68"
REMOTE_DIR="/var/www/pendulbrot"

ssh $SERVER "mkdir -p $REMOTE_DIR"
scp index.html $SERVER:$REMOTE_DIR/

# Plumbing (nginx vhost) is owned by ~/repos/infra — this script only ships content.
echo "Deployed to pendulbrot.ehrlich.dev"
