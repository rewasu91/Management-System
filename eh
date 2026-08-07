#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP="/root/sshws-multiport-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

need=(/etc/haproxy/haproxy.cfg /etc/funny/nginx/main.conf /etc/systemd/system/ws-stunnel.service)
for f in "${need[@]}"; do
  [[ -f "$f" ]] || { echo "[ERROR] Missing: $f"; exit 1; }
  cp -a "$f" "$BACKUP/$(basename "$f")"
done
for f in /usr/local/rere/addssh /usr/local/rere/trial-ssh /usr/local/rere/api/vps/trialsshvpn; do
  [[ -f "$f" ]] && cp -a "$f" "$BACKUP/$(echo "$f" | tr '/' '_')"
done

echo "[INFO] Backup: $BACKUP"

python3 - <<'PY'
from pathlib import Path

# Move the private NodeJS SSH-WS backend off public port 2080.
p=Path('/etc/systemd/system/ws-stunnel.service')
s=p.read_text()
s=s.replace('-mport 2080 -skip 1','-mport 18080 -skip 1')
p.write_text(s)

# Nginx must follow the private backend port.
p=Path('/etc/funny/nginx/main.conf')
s=p.read_text().replace('127.0.0.1:2080','127.0.0.1:18080')
p.write_text(s)

# Patch HAProxy routing.
p=Path('/etc/haproxy/haproxy.cfg')
s=p.read_text()

# Add 8880 to the unified plain ingress when not already present.
if 'bind *:8880 tfo' not in s:
    s=s.replace('    bind *:8000 tfo\n    bind *:8080-8180 tfo',
                '    bind *:8000 tfo\n    bind *:8880 tfo\n    bind *:8080-8180 tfo')

# Add explicit /ssh routing to the TLS and plain unified frontends.
def add_ssh_route(block_name, text):
    start=text.find('frontend '+block_name+'\n')
    if start < 0: return text
    nxt=text.find('\nfrontend ', start+1)
    if nxt < 0: nxt=len(text)
    block=text[start:nxt]
    if 'use_backend SSH_WEBSOCKET if ssh_ws' not in block:
        target='    tcp-request content accept if HTTP\n'
        if target in block:
            block=block.replace(target, target +
                '    acl ssh_ws req.payload(0,1024) -m sub /ssh\n'
                '    use_backend SSH_WEBSOCKET if ssh_ws\n', 1)
        text=text[:start]+block+text[nxt:]
    return text

s=add_ssh_route('xray_tls', s)
s=add_ssh_route('xray_plain', s)

# Port 2082 is shared: /ssh -> SSH WS, everything else stays VLESS TCP.
start=s.find('frontend xray_vless_tcp_plain\n')
if start >= 0:
    nxt=s.find('\nfrontend ', start+1)
    if nxt < 0: nxt=len(s)
    block=s[start:nxt]
    if 'use_backend SSH_WEBSOCKET if ssh_ws' not in block:
        block='''frontend xray_vless_tcp_plain\n    mode tcp\n    bind *:2082 tfo\n    option tcplog\n    tcp-request inspect-delay 5s\n    tcp-request content accept if HTTP\n    acl ssh_ws req.payload(0,1024) -m sub /ssh\n    use_backend SSH_WEBSOCKET if ssh_ws\n    default_backend XRAY_VLESS_TCP\n'''
        s=s[:start]+block+s[nxt:]

# Make 2080 a real public ingress instead of the private NodeJS listener.
if 'frontend ssh_websocket_2080\n' not in s:
    anchor='frontend xray_vmess_tcp_tls\n'
    public='''# Public SSH WebSocket ingress; private backend is 127.0.0.1:18080.\nfrontend ssh_websocket_2080\n    mode tcp\n    bind *:2080 tfo\n    default_backend SSH_WEBSOCKET\n\n'''
    s=s.replace(anchor, public+anchor)

# Add the backend if needed.
if 'backend SSH_WEBSOCKET\n' not in s:
    anchor='backend OPENVPN\n'
    backend='''backend SSH_WEBSOCKET\n    mode tcp\n    server sshws 127.0.0.1:18080 check\n\n'''
    s=s.replace(anchor, backend+anchor)

p.write_text(s)

# User-facing SSH output.
for fn in ['/usr/local/rere/addssh','/usr/local/rere/trial-ssh','/usr/local/rere/api/vps/trialsshvpn']:
    p=Path(fn)
    if not p.exists(): continue
    s=p.read_text()
    for old in ['80, 2080, 2082','80,2082,2080','80,2080,2082']:
        s=s.replace(old,'80,2080,2082,8000,8080,8880')
    s=s.replace('80,2080,2082,8000,8080,8880,8000,8080,8880','80,2080,2082,8000,8080,8880')
    s=s.replace('Port TLS/SSL    : 443','Port TLS/SSL    : 443, 8443')
    s=s.replace('<b>TLS/SSL  :</b> <code>443</code>','<b>TLS/SSL  :</b> <code>443,8443</code>')
    s=s.replace('port_tls="443"','port_tls="443,8443"')
    p.write_text(s)
PY

# Static checks before service restart.
for f in /usr/local/rere/addssh /usr/local/rere/trial-ssh /usr/local/rere/api/vps/trialsshvpn; do
  [[ -f "$f" ]] && bash -n "$f"
done

if command -v node >/dev/null 2>&1 && [[ -f /usr/local/bin/websocket.js ]]; then
  node --check /usr/local/bin/websocket.js >/dev/null
fi

echo "[INFO] Validating Nginx..."
nginx -t

echo "[INFO] Validating HAProxy..."
haproxy -c -f /etc/haproxy/haproxy.cfg

systemctl daemon-reload
systemctl restart ws-stunnel
systemctl restart nginx
systemctl restart haproxy

# Open requested public ports when iptables is present.
if command -v iptables >/dev/null 2>&1; then
  for port in 80 2080 2082 8000 8080 8880 443 8443; do
    iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
      iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
  done
  command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true
fi

echo
echo "[OK] SSH WebSocket routing fixed."
echo "[OK] Non-TLS: 80, 2080, 2082, 8000, 8080, 8880"
echo "[OK] TLS    : 443, 8443"
echo "[INFO] Private SSH-WS backend: 127.0.0.1:18080"
echo
echo "[INFO] Listener check:"
ss -lntp 2>/dev/null | grep -E ':(80|2080|2082|8000|8080|8880|443|8443|18080)\\b' || true

echo
echo "[INFO] Service status:"
for svc in ws-stunnel nginx haproxy; do
  printf '%-14s %s\n' "$svc" "$(systemctl is-active "$svc" 2>/dev/null || true)"
done
