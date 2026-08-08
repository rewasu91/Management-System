#!/usr/bin/env bash
set -Eeuo pipefail

# KaizenSC live patch: Adjust Text Brightness
# Adds System VPS menu option [05] without reinstalling the full autoscript.

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo 'ERROR: Please run this patch as root.' >&2
  exit 1
fi

ROOT_PREFIX="${KAIZEN_ROOT:-}"
RERE_DIR="${ROOT_PREFIX}/usr/local/rere"
MENU_FILE="${RERE_DIR}/menu-system"
ADJUST_FILE="${RERE_DIR}/adjust-text-brightness"
BACKUP_DIR="${ROOT_PREFIX}/root/kaizensc-patch-backup"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "$MENU_FILE" ]]; then
  echo "ERROR: KaizenSC menu-system not found: $MENU_FILE" >&2
  exit 1
fi

# python3 is needed by the brightness switcher. On a normal live VPS,
# install it only when missing. During an isolated KAIZEN_ROOT test, do not apt-install.
if ! command -v python3 >/dev/null 2>&1; then
  if [[ -n "$ROOT_PREFIX" ]]; then
    echo 'ERROR: python3 is required for isolated test mode.' >&2
    exit 1
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y python3
fi

mkdir -p "$RERE_DIR" "$BACKUP_DIR"
cp -a "$MENU_FILE" "$BACKUP_DIR/menu-system.$STAMP.bak"
if [[ -e "$ADJUST_FILE" ]]; then
  cp -a "$ADJUST_FILE" "$BACKUP_DIR/adjust-text-brightness.$STAMP.bak"
fi

cat > "$ADJUST_FILE" <<'ADJUST'
#!/usr/bin/env bash
set -u

STATE_DIR='/etc/kaizensc'
STATE_FILE="${STATE_DIR}/text-brightness.conf"
SELF='/usr/local/rere/adjust-text-brightness'

current_mode(){
  if [[ -f "$STATE_FILE" ]]; then
    case "$(cat "$STATE_FILE" 2>/dev/null)" in
      normal) printf 'Normal / Not Bright' ;;
      bold) printf 'Bright / Bold' ;;
      *) printf 'Bright / Bold' ;;
    esac
  else
    printf 'Bright / Bold'
  fi
}

apply_mode(){
  local mode="$1"
  command -v python3 >/dev/null 2>&1 || {
    echo 'python3 is required for this function.'
    return 1
  }

  MODE="$mode" SELF_PATH="$SELF" python3 <<'PY'
import os
import re
import stat

mode = os.environ['MODE']
self_path = os.environ['SELF_PATH']
roots = ['/usr/local/rere']
extra_files = ['/usr/local/bin/service-fixing', '/usr/local/bin/websocket.js']
ansi = re.compile(r'(\\(?:e|033)\[)([0-9;]+)(m)')
dynamic_256 = re.compile(r'(\\(?:e|033)\[)(?:(?:0|1);)?(38;5;\$\{[^}]+\})(m)')


def has_foreground(parts):
    i = 0
    while i < len(parts):
        token = parts[i]
        try:
            value = int(token, 10)
        except ValueError:
            i += 1
            continue
        if 30 <= value <= 37 or 90 <= value <= 97:
            return True
        if value == 38:
            return True
        i += 1
    return False


def normalize_params(raw):
    parts = raw.split(';')
    if not has_foreground(parts):
        return raw

    kept = []
    i = 0
    while i < len(parts):
        token = parts[i]
        try:
            value = int(token, 10)
        except ValueError:
            value = None

        if value in (38, 48) and i + 1 < len(parts):
            kept.append(token)
            kind = parts[i + 1]
            kept.append(kind)
            if kind == '5' and i + 2 < len(parts):
                kept.append(parts[i + 2])
                i += 3
                continue
            if kind == '2' and i + 4 < len(parts):
                kept.extend(parts[i + 2:i + 5])
                i += 5
                continue
            i += 2
            continue

        if value not in (0, 1):
            kept.append(token)
        i += 1

    prefix = '1' if mode == 'bold' else '0'
    return ';'.join([prefix] + kept)


def transform(text):
    def repl_dynamic(match):
        prefix = '1' if mode == 'bold' else '0'
        return match.group(1) + prefix + ';' + match.group(2) + match.group(3)

    text = dynamic_256.sub(repl_dynamic, text)

    def repl(match):
        return match.group(1) + normalize_params(match.group(2)) + match.group(3)
    return ansi.sub(repl, text)


def process(path):
    if os.path.abspath(path) == os.path.abspath(self_path):
        return False
    try:
        with open(path, 'rb') as fh:
            data = fh.read()
    except OSError:
        return False
    if b'\x00' in data:
        return False
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        return False
    new = transform(text)
    if new == text:
        return False
    st = os.stat(path)
    with open(path, 'w', encoding='utf-8', newline='') as fh:
        fh.write(new)
    os.chmod(path, stat.S_IMODE(st.st_mode))
    return True

changed = 0
scanned = 0
for root in roots:
    if not os.path.isdir(root):
        continue
    for base, dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(base, name)
            scanned += 1
            if process(path):
                changed += 1

for path in extra_files:
    if os.path.isfile(path):
        scanned += 1
        if process(path):
            changed += 1

print(f'Updated {changed} text file(s); scanned {scanned} file(s).')
PY
  local rc=$?
  (( rc == 0 )) || return "$rc"
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$mode" > "$STATE_FILE"
}

while true; do
  clear
  cat <<EOF2
============================================================
                  ADJUST TEXT BRIGHTNESS
============================================================
Current Mode : $(current_mode)

[01] Bright / Bold Text
[02] Normal / Not Bright Text
[ x] Back
============================================================
EOF2
  read -rp 'Input Option: ' opt
  case "$opt" in
    1|01)
      if apply_mode bold; then
        echo 'Text brightness changed to Bright / Bold.'
        sleep 1
        exit 0
      fi
      read -rp 'Press Enter to continue...' _
      ;;
    2|02)
      if apply_mode normal; then
        echo 'Text brightness changed to Normal / Not Bright.'
        sleep 1
        exit 0
      fi
      read -rp 'Press Enter to continue...' _
      ;;
    x|X) exit 0 ;;
    *) echo 'Invalid option, please try again!'; sleep 1 ;;
  esac
done
ADJUST
chmod 0755 "$ADJUST_FILE"

# Patch only the System VPS menu. It is idempotent and recognizes the exact
# menu layout used by KaizenSC-v14-login-title-menu-polish-fixed.
MENU_FILE="$MENU_FILE" python3 <<'PY'
import os
import sys

path = os.environ['MENU_FILE']
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Already patched: leave menu intact.
if 'Adjust Text Brightness' in text and '5|05) adjust-text-brightness' in text:
    print('System VPS menu already contains Adjust Text Brightness; no duplicate added.')
    sys.exit(0)

old_block = ''' echo -e "│ ${BIYellow}[05]${NC} ${BIWhite}| Menu Bot Manager                                      ${BIGreen}│"
 echo -e "│ ${BIYellow}[06]${NC} ${BIWhite}| Reinstall / Rebuild VPS                               ${BIGreen}│"
 echo -e "│ ${BIYellow}[07]${NC} ${BIWhite}| Check Detail Port & Protocol                          ${BIGreen}│"
 echo -e "│ ${BIYellow}[08]${NC} ${BIWhite}| Check Status: Uptime, CPU, RAM & SSD                  ${BIGreen}│"
 echo -e "│ ${BIYellow}[09]${NC} ${BIWhite}| Setup Cloudflare Argo Tunnel Routing                  ${BIGreen}│"
 echo -e "│ ${BIYellow}[10]${NC} ${BIWhite}| Change SSH Banner                                     ${BIGreen}│"
 echo -e "│ ${BIYellow}[11]${NC} ${BIWhite}| Setup Service (ON/OFF)                                ${BIGreen}│"
 echo -e "│ ${BIYellow}[12]${NC} ${BIWhite}| Menu API / REST API Support                           ${BIGreen}│"
 echo -e "│ ${BIYellow}[13]${NC} ${BIWhite}| Menu Admin VPS                                        ${BIGreen}│"'''

new_block = ''' echo -e "│ ${BIYellow}[05]${NC} ${BIWhite}| Adjust Text Brightness                                ${BIGreen}│"
 echo -e "│ ${BIYellow}[06]${NC} ${BIWhite}| Menu Bot Manager                                      ${BIGreen}│"
 echo -e "│ ${BIYellow}[07]${NC} ${BIWhite}| Reinstall / Rebuild VPS                               ${BIGreen}│"
 echo -e "│ ${BIYellow}[08]${NC} ${BIWhite}| Check Detail Port & Protocol                          ${BIGreen}│"
 echo -e "│ ${BIYellow}[09]${NC} ${BIWhite}| Check Status: Uptime, CPU, RAM & SSD                  ${BIGreen}│"
 echo -e "│ ${BIYellow}[10]${NC} ${BIWhite}| Setup Cloudflare Argo Tunnel Routing                  ${BIGreen}│"
 echo -e "│ ${BIYellow}[11]${NC} ${BIWhite}| Change SSH Banner                                     ${BIGreen}│"
 echo -e "│ ${BIYellow}[12]${NC} ${BIWhite}| Setup Service (ON/OFF)                                ${BIGreen}│"
 echo -e "│ ${BIYellow}[13]${NC} ${BIWhite}| Menu API / REST API Support                           ${BIGreen}│"
 echo -e "│ ${BIYellow}[14]${NC} ${BIWhite}| Menu Admin VPS                                        ${BIGreen}│"'''

old_case = '''  5|05) bot-menu;; 6|06) rebuild_vps;; 7|07) detail; read -rp 'Press Enter to continue...' _;; 8|08) htop;;
  9|09) menu-argo;; 10) change_banner; read -rp 'Press Enter to continue...' _;; 11) fn-sc1;; 12) menu-api;; 13) menu-admin;;'''

new_case = '''  5|05) adjust-text-brightness; exec menu-system;; 6|06) bot-menu;; 7|07) rebuild_vps;; 8|08) detail; read -rp 'Press Enter to continue...' _;; 9|09) htop;;
  10) menu-argo;; 11) change_banner; read -rp 'Press Enter to continue...' _;; 12) fn-sc1;; 13) menu-api;; 14) menu-admin;;'''

checks = [
    (old_block, new_block, 'menu entries'),
    ('Input Option [01-13/X]:', 'Input Option [01-14/X]:', 'input range'),
    (old_case, new_case, 'case routing'),
]

for old, new, label in checks:
    if old not in text:
        print(f'ERROR: Could not safely locate expected {label} in menu-system.', file=sys.stderr)
        print('No uncertain menu rewrite was performed. Restore backup if needed.', file=sys.stderr)
        sys.exit(2)
    text = text.replace(old, new, 1)

with open(path, 'w', encoding='utf-8', newline='') as f:
    f.write(text)
print('System VPS menu patched successfully.')
PY

chmod 0755 "$MENU_FILE"

# Validate shell syntax before reporting success.
bash -n "$MENU_FILE"
bash -n "$ADJUST_FILE"

echo
echo '============================================================'
echo ' KaizenSC Adjust Text Brightness patch installed successfully'
echo '============================================================'
echo 'System VPS: [05] Adjust Text Brightness'
echo 'Backup dir : /root/kaizensc-patch-backup'
echo 'No VPN/Xray/HAProxy/Nginx/account configuration was changed.'
echo
echo 'Open the KaizenSC menu and select System VPS > 05.'
