#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE=/etc/systemd/system/ws-stunnel.service
JS=/usr/local/bin/websocket.js
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=/root/ssh-ws-fix-backup-$STAMP
mkdir -p "$BACKUP"

[[ -f "$SERVICE" ]] || { echo "[ERROR] $SERVICE not found"; exit 1; }
[[ -f "$JS" ]] || { echo "[ERROR] $JS not found"; exit 1; }
cp -a "$SERVICE" "$JS" "$BACKUP/"

echo "[INFO] Backup: $BACKUP"

# The first packet seen by the backend is the HTTP Upgrade handshake from Nginx.
# Do not forward that HTTP request to Dropbear; tunnel only subsequent SSH bytes.
if grep -q -- '-mport 2080' "$SERVICE"; then
    sed -i -E 's|(-mport[[:space:]]+2080)([[:space:]]+-skip[[:space:]]+[0-9]+)?|\1 -skip 1|' "$SERVICE"
fi

python3 - <<'PY'
p='/usr/local/bin/websocket.js'
s=open(p).read()
old='socket.write("HTTP/1.1 101 " + baner.fontcolor("blue") + "\\r\\nUpgrade: websocket\\r\\n\\r\\nSec-WebSocket-Accept: foo\\r\\n\\r\\n", function(err) {'
new='socket.write("HTTP/1.1 101 Switching Protocols\\r\\nUpgrade: websocket\\r\\nConnection: Upgrade\\r\\n\\r\\n", function(err) {'
if old in s:
    s=s.replace(old,new)
open(p,'w').write(s)
PY

node --check "$JS"
nginx -t
systemctl daemon-reload
systemctl restart ws-stunnel
sleep 1

if ! systemctl is-active --quiet ws-stunnel; then
    echo "[ERROR] ws-stunnel failed after patch. Restoring backup..."
    cp -a "$BACKUP/ws-stunnel.service" "$SERVICE"
    cp -a "$BACKUP/websocket.js" "$JS"
    systemctl daemon-reload
    systemctl restart ws-stunnel || true
    journalctl -u ws-stunnel -n 30 --no-pager || true
    exit 1
fi

echo "[OK] ws-stunnel is active"
ss -lntp 2>/dev/null | grep -E ':(2080|111|109)\b' || true
printf '\n[TEST] Local WebSocket handshake:\n'
printf 'GET /ssh HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n' | timeout 2 nc 127.0.0.1 2080 2>/dev/null | head -n 4 || true

echo "[DONE] SSH WebSocket fix applied."
