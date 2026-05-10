#!/usr/bin/env bash
set -u

APP_NAME="Socks-Dyno Bypass Manager"
APP_SUBTITLE="Manage Xray/V2Ray Routing Domain Rules"
TARGET_TAG="socks-dyno"
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/bypass-domain-manager.log"

# =========================================================
# UI helpers - plain white/no color
# =========================================================
clear_screen() {
  clear 2>/dev/null || true
}

print_line() {
  printf '%*s\n' "${COLUMNS:-72}" '' | tr ' ' '-'
}

print_big_line() {
  printf '%*s\n' "${COLUMNS:-72}" '' | tr ' ' '='
}

ok() {
  printf "✓ %s\n" "$1"
}

info() {
  printf "i %s\n" "$1"
}

warn() {
  printf "! %s\n" "$1"
}

err() {
  printf "x %s\n" "$1"
}

success_box() {
  echo
  print_big_line
  printf "  %s\n" "$1"
  print_big_line
  echo
}

section() {
  echo
  print_line
  printf "  %s\n" "$1"
  print_line
}

pause_enter() {
  echo
  read -r -p "Tekan ENTER untuk kembali ke menu..."
}

trim_text() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

log_event() {
  mkdir -p "$LOG_DIR"
  printf "%s | %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

header() {
  clear_screen
  cat <<'EOF'
╔════════════════════════════════════════════════════════════╗
║                 Socks-Dyno Bypass Manager                  ║
║          Manage Xray/V2Ray Routing Domain Rules            ║
╚════════════════════════════════════════════════════════════╝
EOF
}

main_menu() {
  header
  cat <<'EOF'
Main Menu

  1) Add domain manually
  2) Import domains from TXT file
  3) View current bypass domains
  4) Remove bypass domain
  5) Validate JSON config
  0) Exit

EOF
}

# =========================================================
# Dependency check
# =========================================================
check_dependencies() {
  if command -v python3 >/dev/null 2>&1; then
    ok "python3 dijumpai."
    return
  fi

  err "python3 tidak dijumpai."
  info "Cuba install python3 secara automatik..."

  if command -v apt-get >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
      apt-get update
      apt-get install -y python3
    else
      sudo apt-get update
      sudo apt-get install -y python3
    fi
  elif command -v dnf >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
      dnf install -y python3
    else
      sudo dnf install -y python3
    fi
  elif command -v yum >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
      yum install -y python3
    else
      sudo yum install -y python3
    fi
  else
    err "Package manager tidak disokong."
    err "Sila install python3 secara manual dahulu."
    exit 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    err "python3 masih tidak dijumpai selepas install."
    exit 1
  fi

  ok "python3 berjaya dipasang."
}

# =========================================================
# JSON path selection
# =========================================================
ask_json_path() {
  section "Pilih Fail Rules JSON"

  while true; do
    read -r -p "Masukkan path rules JSON file: " JSON_PATH

    if [ -z "$JSON_PATH" ]; then
      err "Path kosong. Sila cuba lagi."
      echo
      continue
    fi

    if [ ! -f "$JSON_PATH" ]; then
      err "invalid json, please try again."
      echo
      continue
    fi

    if ! python3 -m json.tool "$JSON_PATH" >/dev/null 2>&1; then
      err "invalid json, please try again."
      echo
      continue
    fi

    ok "JSON valid."
    info "File: $JSON_PATH"
    log_event "Selected JSON file: $JSON_PATH"
    break
  done
}

validate_json_config() {
  header
  section "Validate JSON Config"

  if python3 - "$JSON_PATH" <<'PY' >/dev/null
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(1)

issues = []

if not isinstance(data, dict):
    issues.append("Root JSON bukan object.")

routing = data.get("routing")
if not isinstance(routing, dict):
    issues.append("Field routing tidak wujud atau bukan object.")
else:
    rules = routing.get("rules")
    if not isinstance(rules, list):
        issues.append("Field routing.rules tidak wujud atau bukan array.")
    else:
        socks_rules = [
            i for i, rule in enumerate(rules)
            if isinstance(rule, dict) and rule.get("outboundTag") == "socks-dyno"
        ]

        network_rules = [
            i for i, rule in enumerate(rules)
            if isinstance(rule, dict) and "network" in rule
        ]

        if len(socks_rules) == 0:
            issues.append("Rule outboundTag socks-dyno belum wujud.")
        elif len(socks_rules) > 1:
            issues.append("Lebih dari satu rule outboundTag socks-dyno dijumpai.")
        else:
            idx = socks_rules[0]
            rule = rules[idx]
            if not isinstance(rule.get("domain"), list):
                issues.append("Rule socks-dyno tiada field domain array.")
            if network_rules and idx > min(network_rules):
                issues.append("Rule socks-dyno berada selepas field network. Sepatutnya di atas network rule.")

sys.exit(1 if issues else 0)
PY
  then
    RESULT="$(python3 - "$JSON_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))

rules = data.get("routing", {}).get("rules", [])
socks_index = None
domain_count = 0

for i, rule in enumerate(rules):
    if isinstance(rule, dict) and rule.get("outboundTag") == "socks-dyno":
        socks_index = i
        if isinstance(rule.get("domain"), list):
            domain_count = len(rule["domain"])
        break

print(f"RULES_COUNT={len(rules) if isinstance(rules, list) else 0}")
print(f"SOCKS_INDEX={socks_index if socks_index is not None else '-'}")
print(f"DOMAIN_COUNT={domain_count}")
PY
)"
    ok "JSON config valid."
    echo
    printf "  Rules Count       : %s\n" "$(printf '%s\n' "$RESULT" | awk -F= '/^RULES_COUNT=/{print $2}')"
    printf "  Socks-Dyno Index  : %s\n" "$(printf '%s\n' "$RESULT" | awk -F= '/^SOCKS_INDEX=/{print $2}')"
    printf "  Domain Count      : %s\n" "$(printf '%s\n' "$RESULT" | awk -F= '/^DOMAIN_COUNT=/{print $2}')"
    log_event "Validated JSON config successfully: $JSON_PATH"
  else
    err "JSON config ada isu."
    echo
    python3 - "$JSON_PATH" <<'PY' | sed 's/^/  /'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as e:
    print(f"invalid json, please try again. Detail: {e}")
    sys.exit(0)

issues = []

if not isinstance(data, dict):
    issues.append("Root JSON bukan object.")

routing = data.get("routing")
if not isinstance(routing, dict):
    issues.append("Field routing tidak wujud atau bukan object.")
else:
    rules = routing.get("rules")
    if not isinstance(rules, list):
        issues.append("Field routing.rules tidak wujud atau bukan array.")
    else:
        socks_rules = [
            i for i, rule in enumerate(rules)
            if isinstance(rule, dict) and rule.get("outboundTag") == "socks-dyno"
        ]
        network_rules = [
            i for i, rule in enumerate(rules)
            if isinstance(rule, dict) and "network" in rule
        ]

        if len(socks_rules) == 0:
            issues.append("Rule outboundTag socks-dyno belum wujud.")
        elif len(socks_rules) > 1:
            issues.append("Lebih dari satu rule outboundTag socks-dyno dijumpai.")
        else:
            idx = socks_rules[0]
            rule = rules[idx]
            if not isinstance(rule.get("domain"), list):
                issues.append("Rule socks-dyno tiada field domain array.")
            if network_rules and idx > min(network_rules):
                issues.append("Rule socks-dyno berada selepas field network. Sepatutnya di atas network rule.")

for issue in issues:
    print(f"- {issue}")
PY
    log_event "Validated JSON config with issues: $JSON_PATH"
  fi

  pause_enter
}

# =========================================================
# Domain validation
# =========================================================
validate_domain_list_light() {
  local file="$1"
  local warn_count=0

  while IFS= read -r domain; do
    [ -z "$domain" ] && continue

    case "$domain" in
      *" "*)
        warn "Domain mengandungi space: $domain"
        warn_count=$((warn_count + 1))
        ;;
      http://*|https://*)
        warn "Domain nampak seperti URL penuh. Script tidak auto-normalize: $domain"
        warn_count=$((warn_count + 1))
        ;;
      */*)
        warn "Domain mengandungi slash '/'. Script tidak auto-normalize: $domain"
        warn_count=$((warn_count + 1))
        ;;
    esac
  done < "$file"

  if [ "$warn_count" -gt 0 ]; then
    echo
    warn "Ada $warn_count warning format. Anda masih boleh teruskan jika memang format itu disengajakan."
  fi
}

preview_domains() {
  local file="$1"
  local total
  total="$(wc -l < "$file" | tr -d ' ')"

  section "Preview Domain Yang Akan Diproses"
  printf "  Jumlah input: %s domain\n\n" "$total"

  nl -w2 -s'. ' "$file" | sed 's/^/  /'

  echo
}

# =========================================================
# Add/import domain
# =========================================================
collect_manual_domains() {
  local tmp_file="$1"
  : > "$tmp_file"

  header
  section "Add Domain Manually"

  cat <<'EXAMPLE'
Contoh format yang diterima:

  g-bank.app
  domain:ott-1.xyz
  domain:go-ott.xyz
  geosite:netflix
  geosite:youtube
  regexp:.*.my$

Nota:
  - Tekan ENTER tanpa menaip apa-apa untuk selesai.
  - Duplicate akan diabaikan secara automatik.

EXAMPLE

  local count=0
  while true; do
    read -r -p "Domain #$((count + 1)): " domain
    domain="$(printf '%s' "$domain" | trim_text)"

    if [ -z "$domain" ]; then
      break
    fi

    printf '%s\n' "$domain" >> "$tmp_file"
    count=$((count + 1))
  done
}

collect_txt_domains() {
  local tmp_file="$1"
  : > "$tmp_file"

  header
  section "Import Domains From TXT File"

  cat <<'EXAMPLE'
Format fail .txt:

  g-bank.app
  domain:ott-1.xyz
  domain:go-ott.xyz
  geosite:netflix
  regexp:.*.my$

Nota:
  - Satu domain untuk satu baris.
  - Baris kosong akan diabaikan.
  - Baris bermula dengan # akan dianggap sebagai komen.

EXAMPLE

  while true; do
    read -r -p "Masukkan path fail .txt domain: " txt_path

    if [ -z "$txt_path" ]; then
      err "Path kosong. Sila cuba lagi."
      echo
      continue
    fi

    if [ ! -f "$txt_path" ]; then
      err "Fail tidak wujud, please try again."
      echo
      continue
    fi

    if [ ! -r "$txt_path" ]; then
      err "Fail tidak boleh dibaca, please try again."
      echo
      continue
    fi

    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "$txt_path" \
      | grep -v '^[[:space:]]*$' \
      | grep -v '^[[:space:]]*#' > "$tmp_file"

    ok "Fail TXT berjaya dibaca."
    info "File: $txt_path"
    log_event "Imported domain TXT file: $txt_path"
    break
  done
}

apply_add_domains() {
  local tmp_file="$1"

  if [ ! -s "$tmp_file" ]; then
    warn "Tiada domain dimasukkan. Tiada perubahan dibuat."
    pause_enter
    return
  fi

  local cleaned_file
  cleaned_file="$(mktemp)"
  awk '!seen[$0]++' "$tmp_file" > "$cleaned_file"
  mv "$cleaned_file" "$tmp_file"

  validate_domain_list_light "$tmp_file"
  preview_domains "$tmp_file"

  read -r -p "Teruskan update rules JSON? [y/N]: " confirm
  case "$confirm" in
    y|Y|yes|YES|Yes) ;;
    *)
      warn "Operasi dibatalkan. Tiada perubahan dibuat."
      pause_enter
      return
      ;;
  esac

  section "Processing"

  local backup_path
  backup_path="${JSON_PATH}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$JSON_PATH" "$backup_path"

  ok "Backup dibuat."
  info "Backup: $backup_path"

  local py_output
  py_output="$(python3 - "$JSON_PATH" "$tmp_file" "$TARGET_TAG" <<'PY'
import json
import sys
from pathlib import Path

json_path = Path(sys.argv[1])
domain_file = Path(sys.argv[2])
target_tag = sys.argv[3]

try:
    data = json.loads(json_path.read_text(encoding="utf-8"))
except Exception:
    print("STATUS=ERROR")
    print("MESSAGE=invalid json, please try again.")
    sys.exit(1)

domains = []
seen_input = set()

for line in domain_file.read_text(encoding="utf-8", errors="ignore").splitlines():
    item = line.strip()
    if not item or item.startswith("#"):
        continue
    if item not in seen_input:
        domains.append(item)
        seen_input.add(item)

if not domains:
    print("STATUS=EMPTY")
    print("MESSAGE=Tiada domain valid dijumpai.")
    sys.exit(0)

if not isinstance(data, dict):
    print("STATUS=ERROR")
    print("MESSAGE=invalid json, please try again.")
    sys.exit(1)

routing = data.setdefault("routing", {})
if not isinstance(routing, dict):
    print("STATUS=ERROR")
    print("MESSAGE=invalid json, please try again.")
    sys.exit(1)

rules = routing.setdefault("rules", [])
if not isinstance(rules, list):
    print("STATUS=ERROR")
    print("MESSAGE=invalid json, please try again.")
    sys.exit(1)

target_rule = None
target_index = None

for i, rule in enumerate(rules):
    if isinstance(rule, dict) and rule.get("outboundTag") == target_tag:
        target_rule = rule
        target_index = i
        break

created_new = False

if target_rule is None:
    target_rule = {
        "type": "field",
        "outboundTag": target_tag,
        "domain": []
    }
    created_new = True

if "domain" not in target_rule or not isinstance(target_rule.get("domain"), list):
    target_rule["domain"] = []

existing_domains = set(str(x) for x in target_rule["domain"])
added = []
skipped = []

for domain in domains:
    if domain not in existing_domains:
        target_rule["domain"].append(domain)
        existing_domains.add(domain)
        added.append(domain)
    else:
        skipped.append(domain)

if created_new:
    insert_at = None
    for i, rule in enumerate(rules):
        if isinstance(rule, dict) and "network" in rule:
            insert_at = i
            break

    if insert_at is None:
        rules.append(target_rule)
        target_index = len(rules) - 1
    else:
        rules.insert(insert_at, target_rule)
        target_index = insert_at
else:
    network_index = None
    for i, rule in enumerate(rules):
        if isinstance(rule, dict) and "network" in rule:
            network_index = i
            break

    if network_index is not None and target_index is not None and target_index > network_index:
        rule_obj = rules.pop(target_index)
        rules.insert(network_index, rule_obj)
        target_index = network_index

json_path.write_text(
    json.dumps(data, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8"
)

print("STATUS=OK")
print(f"CREATED_NEW={1 if created_new else 0}")
print(f"ADDED={len(added)}")
print(f"SKIPPED={len(skipped)}")
print(f"TOTAL_IN_RULE={len(target_rule['domain'])}")
print(f"RULE_INDEX={target_index}")
print("ADDED_LIST_START")
for item in added:
    print(item)
print("ADDED_LIST_END")
PY
)"

  local status=$?

  if [ "$status" -ne 0 ]; then
    err "Update gagal."
    echo "$py_output" | sed 's/^/  /'
    info "Backup asal ada di: $backup_path"
    log_event "Update failed. JSON: $JSON_PATH | Backup: $backup_path"
    pause_enter
    return
  fi

  local created_new added skipped total_in_rule rule_index
  created_new="$(printf '%s\n' "$py_output" | awk -F= '/^CREATED_NEW=/{print $2}')"
  added="$(printf '%s\n' "$py_output" | awk -F= '/^ADDED=/{print $2}')"
  skipped="$(printf '%s\n' "$py_output" | awk -F= '/^SKIPPED=/{print $2}')"
  total_in_rule="$(printf '%s\n' "$py_output" | awk -F= '/^TOTAL_IN_RULE=/{print $2}')"
  rule_index="$(printf '%s\n' "$py_output" | awk -F= '/^RULE_INDEX=/{print $2}')"

  success_box "Update Completed Successfully"

  printf "  Rules JSON       : %s\n" "$JSON_PATH"
  printf "  Backup           : %s\n" "$backup_path"
  printf "  Outbound Tag     : %s\n" "$TARGET_TAG"

  if [ "$created_new" = "1" ]; then
    printf "  Rule             : Baru dicipta\n"
  else
    printf "  Rule             : Rule sedia ada dikemaskini\n"
  fi

  printf "  Rule Position    : Index %s dalam array rules\n" "$rule_index"
  printf "  Domain Ditambah  : %s\n" "$added"
  printf "  Duplicate Skip   : %s\n" "$skipped"
  printf "  Total Dalam Rule : %s\n" "$total_in_rule"

  if [ "${added:-0}" -gt 0 ] 2>/dev/null; then
    echo
    echo "  Domain yang ditambah:"
    printf '%s\n' "$py_output" \
      | awk '/^ADDED_LIST_START$/{flag=1;next}/^ADDED_LIST_END$/{flag=0}flag' \
      | sed 's/^/   - /'
  fi

  log_event "Added domains. JSON: $JSON_PATH | Added: $added | Skipped: $skipped | Backup: $backup_path"
  pause_enter
}

add_manual_domain_flow() {
  local tmp_file
  tmp_file="$(mktemp)"
  collect_manual_domains "$tmp_file"
  apply_add_domains "$tmp_file"
  rm -f "$tmp_file"
}

import_txt_domain_flow() {
  local tmp_file
  tmp_file="$(mktemp)"
  collect_txt_domains "$tmp_file"
  apply_add_domains "$tmp_file"
  rm -f "$tmp_file"
}

# =========================================================
# View domains
# =========================================================
view_current_domains() {
  header
  section "Current Socks-Dyno Bypass Domains"

  python3 - "$JSON_PATH" "$TARGET_TAG" <<'PY'
import json
import sys
from pathlib import Path

json_path = Path(sys.argv[1])
target_tag = sys.argv[2]

try:
    data = json.loads(json_path.read_text(encoding="utf-8"))
except Exception:
    print("invalid json, please try again.")
    sys.exit(0)

rules = data.get("routing", {}).get("rules", [])
target_rule = None
target_index = None

if isinstance(rules, list):
    for i, rule in enumerate(rules):
        if isinstance(rule, dict) and rule.get("outboundTag") == target_tag:
            target_rule = rule
            target_index = i
            break

if target_rule is None:
    print("Rule socks-dyno belum wujud.")
    sys.exit(0)

domains = target_rule.get("domain", [])

print(f"Rule Index : {target_index}")
print(f"Total      : {len(domains) if isinstance(domains, list) else 0}")
print()

if not isinstance(domains, list) or not domains:
    print("Tiada domain dalam rule socks-dyno.")
    sys.exit(0)

for idx, domain in enumerate(domains, start=1):
    print(f"{idx:>3}. {domain}")
PY

  log_event "Viewed current bypass domains. JSON: $JSON_PATH"
  pause_enter
}

# =========================================================
# Remove domain
# =========================================================
remove_bypass_domain() {
  header
  section "Remove Bypass Domain"

  local tmp_current
  tmp_current="$(mktemp)"

  python3 - "$JSON_PATH" "$TARGET_TAG" > "$tmp_current" <<'PY'
import json
import sys
from pathlib import Path

json_path = Path(sys.argv[1])
target_tag = sys.argv[2]

try:
    data = json.loads(json_path.read_text(encoding="utf-8"))
except Exception:
    print("ERROR|invalid json, please try again.")
    sys.exit(0)

rules = data.get("routing", {}).get("rules", [])
target_rule = None

if isinstance(rules, list):
    for rule in rules:
        if isinstance(rule, dict) and rule.get("outboundTag") == target_tag:
            target_rule = rule
            break

if target_rule is None:
    print("ERROR|Rule socks-dyno belum wujud.")
    sys.exit(0)

domains = target_rule.get("domain", [])
if not isinstance(domains, list) or not domains:
    print("ERROR|Tiada domain dalam rule socks-dyno.")
    sys.exit(0)

for idx, domain in enumerate(domains, start=1):
    print(f"{idx}|{domain}")
PY

  if grep -q '^ERROR|' "$tmp_current"; then
    sed 's/^ERROR|//' "$tmp_current"
    rm -f "$tmp_current"
    pause_enter
    return
  fi

  echo "Senarai domain semasa:"
  echo
  awk -F'|' '{printf "  %3d. %s\n", $1, $2}' "$tmp_current"
  echo

  cat <<'NOTE'
Cara remove:
  - Taip nombor domain, contoh: 3
  - Atau taip domain penuh, contoh: domain:ott-1.xyz
  - Taip 0 untuk batal

NOTE

  read -r -p "Pilihan remove: " remove_input
  remove_input="$(printf '%s' "$remove_input" | trim_text)"

  if [ -z "$remove_input" ] || [ "$remove_input" = "0" ]; then
    warn "Operasi dibatalkan."
    rm -f "$tmp_current"
    pause_enter
    return
  fi

  local selected_domain=""

  if printf '%s' "$remove_input" | grep -Eq '^[0-9]+$'; then
    selected_domain="$(awk -F'|' -v n="$remove_input" '$1 == n {print $2}' "$tmp_current")"
    if [ -z "$selected_domain" ]; then
      err "Nombor domain tidak sah."
      rm -f "$tmp_current"
      pause_enter
      return
    fi
  else
    selected_domain="$remove_input"
  fi

  echo
  warn "Domain akan dibuang: $selected_domain"
  read -r -p "Teruskan remove? [y/N]: " confirm
  case "$confirm" in
    y|Y|yes|YES|Yes) ;;
    *)
      warn "Operasi dibatalkan. Tiada perubahan dibuat."
      rm -f "$tmp_current"
      pause_enter
      return
      ;;
  esac

  local backup_path
  backup_path="${JSON_PATH}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$JSON_PATH" "$backup_path"

  local py_output
  py_output="$(python3 - "$JSON_PATH" "$TARGET_TAG" "$selected_domain" <<'PY'
import json
import sys
from pathlib import Path

json_path = Path(sys.argv[1])
target_tag = sys.argv[2]
selected_domain = sys.argv[3]

try:
    data = json.loads(json_path.read_text(encoding="utf-8"))
except Exception:
    print("STATUS=ERROR")
    print("MESSAGE=invalid json, please try again.")
    sys.exit(1)

rules = data.get("routing", {}).get("rules", [])
if not isinstance(rules, list):
    print("STATUS=ERROR")
    print("MESSAGE=routing.rules tidak valid.")
    sys.exit(1)

target_rule = None

for rule in rules:
    if isinstance(rule, dict) and rule.get("outboundTag") == target_tag:
        target_rule = rule
        break

if target_rule is None:
    print("STATUS=ERROR")
    print("MESSAGE=Rule socks-dyno belum wujud.")
    sys.exit(1)

domains = target_rule.get("domain", [])
if not isinstance(domains, list):
    print("STATUS=ERROR")
    print("MESSAGE=Field domain bukan array.")
    sys.exit(1)

before = len(domains)
target_rule["domain"] = [d for d in domains if str(d) != selected_domain]
after = len(target_rule["domain"])

if before == after:
    print("STATUS=NOT_FOUND")
    print(f"MESSAGE=Domain tidak dijumpai: {selected_domain}")
    sys.exit(0)

json_path.write_text(
    json.dumps(data, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8"
)

print("STATUS=OK")
print(f"REMOVED={selected_domain}")
print(f"TOTAL_IN_RULE={after}")
PY
)"

  local status=$?

  if [ "$status" -ne 0 ]; then
    err "Remove gagal."
    echo "$py_output" | sed 's/^/  /'
    info "Backup asal ada di: $backup_path"
    log_event "Remove failed. JSON: $JSON_PATH | Domain: $selected_domain | Backup: $backup_path"
    rm -f "$tmp_current"
    pause_enter
    return
  fi

  if printf '%s\n' "$py_output" | grep -q '^STATUS=NOT_FOUND'; then
    warn "Domain tidak dijumpai. Tiada perubahan dibuat pada JSON."
    info "Backup tetap telah dibuat: $backup_path"
    log_event "Remove skipped not found. JSON: $JSON_PATH | Domain: $selected_domain"
  else
    ok "Domain berjaya dibuang."
    info "Removed: $selected_domain"
    info "Backup: $backup_path"
    log_event "Removed domain. JSON: $JSON_PATH | Domain: $selected_domain | Backup: $backup_path"
  fi

  rm -f "$tmp_current"
  pause_enter
}

# =========================================================
# Main
# =========================================================
check_dependencies
header
ask_json_path

while true; do
  main_menu
  read -r -p "Pilihan anda [1/2/3/4/5/0]: " choice

  case "$choice" in
    1) add_manual_domain_flow ;;
    2) import_txt_domain_flow ;;
    3) view_current_domains ;;
    4) remove_bypass_domain ;;
    5) validate_json_config ;;
    0)
      echo
      ok "Terima kasih. Keluar."
      log_event "Exited application."
      exit 0
      ;;
    *)
      err "Pilihan tidak sah. Sila pilih menu yang betul."
      sleep 1
      ;;
  esac
done
