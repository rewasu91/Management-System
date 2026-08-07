#!/usr/bin/env bash
set -euo pipefail

HAP=/etc/haproxy/haproxy.cfg
NGMAIN=/etc/funny/nginx/main.conf
TCPCONF=/etc/funny/config/tcp/tcp.conf
TCPJSON=/etc/funny/json/tcp.json
TS=$(date +%Y%m%d-%H%M%S)
BACKUP=/root/kaizensc-tcp80-fix-$TS

fail(){ echo "[ERROR] $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail "Run as root"
for f in "$HAP" "$NGMAIN" "$TCPJSON"; do [[ -f "$f" ]] || fail "$f not found"; done

mkdir -p "$BACKUP"
cp -a "$HAP" "$BACKUP/haproxy.cfg"
cp -a "$NGMAIN" "$BACKUP/main.conf"
cp -a "$TCPJSON" "$BACKUP/tcp.json"
[[ -f "$TCPCONF" ]] && cp -a "$TCPCONF" "$BACKUP/tcp.conf"

echo "[INFO] Backup: $BACKUP"

python3 - "$TCPJSON" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
ports={i.get('port'):i for i in j.get('inbounds',[])}
for port,proto in ((1235,'vless'),(1234,'vmess')):
    i=ports.get(port)
    if not i or i.get('protocol')!=proto: raise SystemExit(f'[ERROR] inbound {port}/{proto} not found')
    t=i.get('streamSettings',{}).get('tcpSettings',{})
    if not t.get('acceptProxyProtocol'): raise SystemExit(f'[ERROR] {port} acceptProxyProtocol is not true')
    if t.get('header',{}).get('type')!='http': raise SystemExit(f'[ERROR] {port} header.type is not http')
print('[OK] Xray TCP backends verified')
PY

python3 - "$NGMAIN" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); s=p.read_text()
s=re.sub(r'(?m)^\s*listen\s+80(?:\s+[^;]*)?;.*\n','',s)
s=re.sub(r'(?m)^\s*listen\s+\[::\]:80(?:\s+[^;]*)?;.*\n','',s)
s=re.sub(r'(?m)^\s*listen\s+18080(?:\s+[^;]*)?;.*\n','',s)
m=re.search(r'(?m)^\s*listen\s+1010[^\n]*\n',s)
line='listen 18080 proxy_protocol so_keepalive=on reuseport; # HAProxy HTTP backend\n'
if m: s=s[:m.end()]+line+s[m.end():]
else: s=s.replace('server {\n','server {\n    '+line,1)
p.write_text(s)
PY

if [[ -f "$TCPCONF" ]]; then
cat > "$TCPCONF" <<'EOF2'
# KaizenSC pre-v2 TCP80 FIX
# RAW Xray TCP paths are handled by HAProxy :80.
# Do not reverse-proxy /tcpvless or /tcpvmess through Nginx HTTP.
EOF2
fi

python3 - "$HAP" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); s=p.read_text()

s=re.sub(r'(?ms)^# === KAIZENSC XRAY TCP NON-TLS PORT 80.*?(?=^frontend |\Z)','',s)
for name in ('XRAY_VLESS_TCP80','XRAY_VMESS_TCP80','NGINX_HTTP_18080'):
    s=re.sub(rf'(?ms)^backend\s+{name}\b.*?(?=^backend |^frontend |\Z)','',s)
s=re.sub(r'(?m)^\s*bind\s+\*:80(?:\s+[^\n]*)?\n','',s)

m=re.search(r'(?m)^frontend\s+',s)
if not m: raise SystemExit('[ERROR] No HAProxy frontend found')
block='''# === KAIZENSC XRAY TCP NON-TLS PORT 80
frontend xray_tcp80
    mode tcp
    bind *:80
    option tcplog
    tcp-request inspect-delay 5s

    acl is_tcpvless req.payload(0,4096) -m sub /tcpvless
    acl is_tcpvmess req.payload(0,4096) -m sub /tcpvmess

    tcp-request content accept if is_tcpvless
    tcp-request content accept if is_tcpvmess
    tcp-request content accept if HTTP

    use_backend XRAY_VLESS_TCP80 if is_tcpvless
    use_backend XRAY_VMESS_TCP80 if is_tcpvmess
    default_backend NGINX_HTTP_18080

'''
s=s[:m.start()]+block+s[m.start():]
s=s.rstrip()+'''\n\nbackend XRAY_VLESS_TCP80
    mode tcp
    timeout connect 10s
    timeout server 1h
    server vless_tcp 127.0.0.1:1235 send-proxy check

backend XRAY_VMESS_TCP80
    mode tcp
    timeout connect 10s
    timeout server 1h
    server vmess_tcp 127.0.0.1:1234 send-proxy check

backend NGINX_HTTP_18080
    mode tcp
    timeout connect 10s
    timeout server 1h
    server nginx_http 127.0.0.1:18080 send-proxy check
'''
p.write_text(s+'\n')
PY

python3 - <<'PY'
from pathlib import Path
import re
root=Path('/usr/local/rere')
for name in ['add-vless-tcp','add-trial-vless-tcp','bulk-vless-tcp','config-tcp','add-vmess-tcp','add-trial-vmess-tcp','bulk-vmess-tcp']:
    p=root/name
    if not p.exists(): continue
    s=p.read_text(errors='ignore'); old=s
    s=s.replace('path=/tcpvless&security=none&encryption=none&host=${domain}&type=tcp#','path=/tcpvless&security=none&encryption=none&host=${domain}&type=tcp&headerType=http#')
    s=re.sub(r'("port"\s*:\s*"80"\s*,.*?"net"\s*:\s*"tcp"\s*,.*?"path"\s*:\s*"/tcpvmess"\s*,\s*"type"\s*:\s*)"none"',r'\1"http"',s,flags=re.S)
    if s!=old: p.write_text(s)
PY

XRAY_BIN=$(systemctl cat xray-tcp 2>/dev/null | grep -oE '/[^ ]*/xray' | head -n1 || true)
[[ -x "$XRAY_BIN" ]] || XRAY_BIN=/usr/local/xray-mod/xray
[[ -x "$XRAY_BIN" ]] || XRAY_BIN=/usr/local/bin/xray
if [[ -x "$XRAY_BIN" ]]; then "$XRAY_BIN" run -test -config "$TCPJSON"; fi

nginx -t
systemctl restart nginx
sleep 1

if ! haproxy -c -f "$HAP"; then
  echo '[ERROR] HAProxy validation failed; restoring configs'
  cp -a "$BACKUP/haproxy.cfg" "$HAP"
  cp -a "$BACKUP/main.conf" "$NGMAIN"
  [[ -f "$BACKUP/tcp.conf" ]] && cp -a "$BACKUP/tcp.conf" "$TCPCONF"
  systemctl restart nginx || true
  exit 1
fi

systemctl restart xray-tcp
systemctl restart haproxy
sleep 1

echo
echo '=================================================='
echo '[OK] KaizenSC pre-v2 TCP port 80 fix applied'
echo '=================================================='
echo 'Routing:'
echo '  :80 /tcpvless -> Xray :1235 (raw TCP + PROXY)'
echo '  :80 /tcpvmess -> Xray :1234 (raw TCP + PROXY)'
echo '  :80 other HTTP -> Nginx :18080'
echo
echo 'VLESS non-TLS:'
echo '  Port 80 | type=tcp | headerType=http | path=/tcpvless'
echo 'VMess non-TLS:'
echo '  Port 80 | net=tcp | type=http | path=/tcpvmess'
echo
echo 'Listeners:'
ss -lntp | grep -E ':(80|18080|1234|1235|1236)\b' || true
echo
echo "Backup: $BACKUP"
