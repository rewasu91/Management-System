#!/bin/bash

# DNS Management System
# Supports: systemd-resolved, resolvconf, static resolv.conf

LINE="============================================================"
SELECTED_DNS_FILE="/etc/dns-manager-selected.conf"

pause() {
  echo
  read -p " Press Enter to continue..."
}

check_root() {
  if [ "$(id -u)" != "0" ]; then
    echo " Error: Please run this script as root."
    exit 1
  fi
}

detect_resolver() {
  RESOLV_TARGET="$(readlink -f /etc/resolv.conf 2>/dev/null)"

  if echo "$RESOLV_TARGET" | grep -q "systemd/resolve"; then
    RESOLVER_TYPE="systemd-resolved"
  elif echo "$RESOLV_TARGET" | grep -q "resolvconf"; then
    RESOLVER_TYPE="resolvconf"
  else
    RESOLVER_TYPE="static"
  fi
}

save_selected_dns() {
  SELECTED_DNS="$1"
  echo "$SELECTED_DNS" > "$SELECTED_DNS_FILE"
}

show_current_dns_short() {
  if [ -f "$SELECTED_DNS_FILE" ]; then
    DNS_NOW="$(cat "$SELECTED_DNS_FILE")"
  else
    DNS_NOW="$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | awk '!seen[$0]++')"
  fi

  if [ -z "$DNS_NOW" ]; then
    echo "   No DNS profile selected"
  else
    echo "$DNS_NOW" | while read dns; do
      [ -n "$dns" ] && echo "   - $dns"
    done
  fi
}

show_header() {
  clear
  detect_resolver

  echo "$LINE"
  echo "                    DNS MANAGEMENT SYSTEM"
  echo "$LINE"
  echo " Resolver Type : $RESOLVER_TYPE"
  echo " Config Path   : /etc/resolv.conf"
  echo
  echo " Selected DNS"
  show_current_dns_short
  echo "$LINE"
}

backup_files() {
  DATE_TAG="$(date +%Y%m%d-%H%M%S)"

  [ -f /etc/resolv.conf ] && cp /etc/resolv.conf "/etc/resolv.conf.bak-$DATE_TAG" 2>/dev/null
  [ -f /etc/systemd/resolved.conf ] && cp /etc/systemd/resolved.conf "/etc/systemd/resolved.conf.bak-$DATE_TAG" 2>/dev/null
  [ -f /etc/resolvconf/resolv.conf.d/head ] && cp /etc/resolvconf/resolv.conf.d/head "/etc/resolvconf/resolv.conf.d/head.bak-$DATE_TAG" 2>/dev/null
  [ -f /etc/resolvconf/resolv.conf.d/base ] && cp /etc/resolvconf/resolv.conf.d/base "/etc/resolvconf/resolv.conf.d/base.bak-$DATE_TAG" 2>/dev/null
  [ -f /etc/resolvconf/resolv.conf.d/tail ] && cp /etc/resolvconf/resolv.conf.d/tail "/etc/resolvconf/resolv.conf.d/tail.bak-$DATE_TAG" 2>/dev/null
}

restart_dns_service() {
  if [ "$RESOLVER_TYPE" = "systemd-resolved" ]; then
    systemctl restart systemd-resolved 2>/dev/null
    resolvectl flush-caches 2>/dev/null || systemd-resolve --flush-caches 2>/dev/null

  elif [ "$RESOLVER_TYPE" = "resolvconf" ]; then
    resolvconf -u 2>/dev/null
    systemctl restart resolvconf 2>/dev/null

  else
    systemctl restart networking 2>/dev/null
  fi
}

build_ns_list() {
  NS_LIST=""

  for dns in "$@"; do
    if [ -n "$dns" ]; then
      echo "$NS_LIST" | grep -q "nameserver $dns" || NS_LIST="${NS_LIST}nameserver $dns
"
    fi
  done
}

apply_systemd_resolved() {
  DNS_MAIN="$1"
  DNS_FALLBACK="$2"

  mkdir -p /etc/systemd

  cat > /etc/systemd/resolved.conf <<EOF
[Resolve]
DNS=$DNS_MAIN
FallbackDNS=$DNS_FALLBACK
EOF

  restart_dns_service
}

apply_resolvconf() {
  NS_LIST="$1"

  mkdir -p /etc/resolvconf/resolv.conf.d

  echo "$NS_LIST" > /etc/resolvconf/resolv.conf.d/head
  : > /etc/resolvconf/resolv.conf.d/base
  : > /etc/resolvconf/resolv.conf.d/tail

  resolvconf -u 2>/dev/null
  restart_dns_service
}

apply_static_resolv() {
  NS_LIST="$1"

  echo "$NS_LIST" > /etc/resolv.conf
  restart_dns_service
}

clean_duplicate_resolvconf() {
  if [ "$RESOLVER_TYPE" = "resolvconf" ]; then
    resolvconf -u 2>/dev/null
  fi
}

apply_dns_profile() {
  TITLE="$1"
  DNS_MAIN="$2"
  DNS_FALLBACK="$3"
  NS_LIST="$4"

  detect_resolver

  SELECTED_DNS="$(echo "$NS_LIST" | awk '/^nameserver/ {print $2}')"

  echo
  echo "$LINE"
  echo " Apply DNS Profile"
  echo "$LINE"
  echo " Profile       : $TITLE"
  echo " Resolver Type : $RESOLVER_TYPE"
  echo " Primary DNS   : $DNS_MAIN"
  echo " Fallback DNS  : ${DNS_FALLBACK:-None}"
  echo "$LINE"
  read -p " Continue with this DNS configuration? [y/N]: " confirm

  case "$confirm" in
    y|Y)
      backup_files
      save_selected_dns "$SELECTED_DNS"

      if [ "$RESOLVER_TYPE" = "systemd-resolved" ]; then
        apply_systemd_resolved "$DNS_MAIN" "$DNS_FALLBACK"
      elif [ "$RESOLVER_TYPE" = "resolvconf" ]; then
        apply_resolvconf "$NS_LIST"
      else
        apply_static_resolv "$NS_LIST"
      fi

      clean_duplicate_resolvconf

      echo
      echo "$LINE"
      echo " DNS configuration updated successfully."
      echo
      echo " Selected DNS"
      show_current_dns_short
      echo "$LINE"
      ;;
    *)
      echo " Operation cancelled."
      ;;
  esac

  pause
}

use_ads_dns() {
  build_ns_list "76.76.2.2" "76.76.10.2" "1.1.1.1" "8.8.8.8"

  apply_dns_profile \
    "ControlD Ads Blocking DNS" \
    "76.76.2.2 76.76.10.2" \
    "1.1.1.1 8.8.8.8" \
    "$NS_LIST"
}

use_default_dns() {
  build_ns_list "1.1.1.1" "8.8.8.8"

  apply_dns_profile \
    "Default DNS" \
    "1.1.1.1 8.8.8.8" \
    "" \
    "$NS_LIST"
}

custom_dns_menu() {
  DNS_LIST=""
  DNS_ARRAY=""

  echo
  echo "$LINE"
  echo " Custom DNS Setup"
  echo "$LINE"
  echo " Enter DNS servers one by one."
  echo " Leave empty and press Enter when finished."
  echo
  echo " Example:"
  echo "   9.9.9.9"
  echo "   149.112.112.112"
  echo "$LINE"

  while true; do
    read -p " DNS Server: " dns_input

    if [ -z "$dns_input" ]; then
      break
    fi

    echo "$DNS_LIST" | grep -q "$dns_input" && {
      echo " DNS already added. Skipped."
      continue
    }

    DNS_LIST="$DNS_LIST $dns_input"
    DNS_ARRAY="$DNS_ARRAY $dns_input"
  done

  if [ -z "$DNS_LIST" ]; then
    echo " No DNS entered. Operation cancelled."
    pause
    return
  fi

  build_ns_list $DNS_ARRAY

  apply_dns_profile \
    "Custom DNS" \
    "$DNS_LIST" \
    "" \
    "$NS_LIST"
}

show_full_dns() {
  show_header

  echo " Selected DNS Details"
  show_current_dns_short

  echo
  echo "$LINE"
  echo " Actual /etc/resolv.conf"
  echo "$LINE"

  cat /etc/resolv.conf

  echo "$LINE"
  pause
}

main_menu() {
  while true; do
    show_header

    echo " Available Options"
    echo
    echo " [1] ControlD Ads Blocking DNS"
    echo "     Primary : 76.76.2.2, 76.76.10.2"
    echo "     Fallback: 1.1.1.1, 8.8.8.8"
    echo
    echo " [2] Default DNS"
    echo "     Primary : 1.1.1.1, 8.8.8.8"
    echo
    echo " [3] Custom DNS"
    echo "     Manually enter your preferred DNS servers"
    echo
    echo " [4] Show Current DNS Details"
    echo
    echo " [0] Exit"
    echo "$LINE"
    read -p " Select an option: " opt

    case "$opt" in
      1)
        use_ads_dns
        ;;
      2)
        use_default_dns
        ;;
      3)
        custom_dns_menu
        ;;
      4)
        show_full_dns
        ;;
      0)
        echo " Exiting DNS Management System."
        exit 0
        ;;
      *)
        echo " Invalid option."
        pause
        ;;
    esac
  done
}

check_root
main_menu
