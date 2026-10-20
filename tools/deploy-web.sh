#!/bin/sh
# Deploys the browser build (build/web) to the host that serves the Ishtaria portal, the way the package ishtaria-client-web would:
# files into /usr/share/ishtaria-client-web/html and an `Alias /play/` in the Apache vhost, with a backup of the vhost, a configtest
# before the reload (graceful, other sites on the host are not interrupted) and a rollback if the configtest fails.
#   tools/deploy-web.sh [HOST] [VHOST_FILE]          (default: ishtaria.vitexsoftware.com, ishtaria.vitexsoftware.com.conf)
# Needs ssh access with sudo on the host and `make build-web` done. Once the Debian package is released this script is not needed.
set -eu
HOST="${1:-ishtaria.vitexsoftware.com}"
VHOST="/etc/apache2/sites-available/${2:-ishtaria.vitexsoftware.com.conf}"
SRC="$(cd "$(dirname "$0")/.." && pwd)/build/web"
[ -f "$SRC/index.html" ] && [ -f "$SRC/index.wasm" ] && [ -f "$SRC/index.pck" ] || { echo "no build in $SRC: run make build-web" >&2; exit 1; }
tar -C "$SRC" -cf - . | ssh "$HOST" 'set -e
  # (the login shell of the host may be zsh, which refuses a glob without a match: no globs here)
  find /tmp -maxdepth 1 -type d -name "ishtaria-web-*" -user "$(id -un)" -exec rm -rf {} +
  tmp=$(mktemp -d /tmp/ishtaria-web-XXXXXX)
  tar -xf - -C "$tmp"
  sudo install -d -m 0755 /usr/share/ishtaria-client-web/html
  sudo find /usr/share/ishtaria-client-web/html -mindepth 1 -delete
  sudo cp -a "$tmp"/. /usr/share/ishtaria-client-web/html/
  sudo chown -R root:root /usr/share/ishtaria-client-web
  sudo find /usr/share/ishtaria-client-web -type d -exec chmod 755 {} +
  sudo find /usr/share/ishtaria-client-web -type f -exec chmod 644 {} +
  rm -rf "$tmp"'
ssh "$HOST" "VHOST='$VHOST' sh -s" <<'REMOTE'
set -eu
if sudo grep -q 'Alias /play/' "$VHOST"; then echo "vhost already has /play/: left as it is"; exit 0; fi
backup="$VHOST.bak-$(date +%Y%m%d%H%M%S)"
sudo cp -a "$VHOST" "$backup"
# the block goes into the https virtual host, in front of the documentation alias
sudo python3 - "$VHOST" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
block = '''    # Browser client (HTML5 / WebAssembly). Default API URL is /etc/ishtaria/client-web-config.js
    # (window.ISHTARIA_SERVER_URL), not a hardcoded world. Optional: /play/?server=/api still works.
    Alias /play/ishtaria-config.js /etc/ishtaria/client-web-config.js
    Alias /play/ /usr/share/ishtaria-client-web/html/
    <Directory /usr/share/ishtaria-client-web/html/>
        Options -Indexes +FollowSymLinks
        Require all granted
        AddType application/wasm .wasm
        AddType application/octet-stream .pck
        Header set Cache-Control "public, max-age=3600"
        <IfModule mod_deflate.c>
            AddOutputFilterByType DEFLATE text/html text/javascript application/javascript application/wasm
        </IfModule>
    </Directory>
    <Location "/play/ishtaria-config.js">
        Require all granted
        Header set Cache-Control "no-cache"
    </Location>

'''
marker = '    # Documentation of the ishtaria-doc package'
i = s.index(marker, s.index('<VirtualHost *:443>'))
open(p, 'w').write(s[:i] + block + s[i:])
PY
if sudo apache2ctl configtest 2>&1 | tail -1 | grep -q 'Syntax OK'; then
  sudo systemctl reload apache2 && echo "deployed; backup of the vhost: $backup"
else
  sudo cp -a "$backup" "$VHOST"; echo "configtest failed: vhost restored from $backup, nothing reloaded" >&2; exit 1
fi
REMOTE
echo "Try: https://$HOST/play/"
