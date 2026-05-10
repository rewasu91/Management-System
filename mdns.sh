#!/bin/bash

# DNS Management System
# Supports: systemd-resolved, resolvconf, static resolv.conf

LINE="============================================================"

pause() {
  echo
  read -p "Press Enter to continue..."
}

check_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "Error: Please run this script as root."
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

show_current_dns_short() {
  grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print "  - " $2}'
}

show_header() {
  clear
  detect_resolver

  echo "$LINE"
  echo "                    DNS MANAGEMENT SYSTEM"
  echo "$LINE"
  echo " Resolver Type : $RESOLVER_TYPE"
  echo " Resolv Path   : /etc/resolv.conf -> $RESOLV_TARGET"
  echo "$LINE"
  echo " Current DNS:"
  show_current_dns_short
  echo "$LINE"
}

backup_files() {
  DATE_TAG="$(date +%Y%m%d-%H%M%S)"

  [ -f /etc/resolv.conf ] && cp /etc/resolv.conf "/etc/resolv.conf.bak-$DATE_TAG" 2>/dev/null
  [ -f /etc/systemd/resolved.conf ] && cp /etc/systemd/resolved.conf "/etc/systemd/resolved.conf.bak-$DATE_TAG" 2>/dev/null
  [ -f /etc/resolvconf/resolv.conf.d/head ] && cp /etc/resolvconf/resolv.conf.d/head "/etc/resolvconf/resolv.conf.d/head.bak-$DATE_TAG" 2>/dev/null
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

  restart_dns_service
}

apply_static_resolv() {
  NS_LIST="$1"

  rm -f /etc/resolv.conf
  echo "$NS_LIST" > /etc/resolv.conf

  restart_dns_service
}

apply_dns() {
  MODE="$1"

  detect_resolver

  if [ "$MODE" = "ads" ]; then
    TITLE="Block Ads DNS"
    DNS_MAIN="76.76.2.2 76.76.10.2"
    DNS_FALLBACK="1.1.1.1 8.8.8.8"
    NS_LIST="nameserver 76.76.2.2
nameserver 76.76.10.2
nameserver 1.1.1.1
nameserver 8.8.8.8"

  else
    TITLE="Default DNS"
    DNS_MAIN="1.1.1.1 8.8.8.8"
    DNS_FALLBACK=""
    NS_LIST="nameserver 1.1.1.1
nameserver 8.8.8.8"
  fi

  echo
  echo "$LINE"
  echo " Apply DNS Profile: $TITLE"
  echo "$LINE"
  echo " Resolver Type : $RESOLVER_TYPE"
  echo " DNS Main      : $DNS_MAIN"
  echo " DNS Fallback  : ${DNS_FALLBACK:-None}"
  echo "$LINE"
  read -p " Continue? [y/N]: " confirm

  case "$confirm" in
    y|Y)
      backup_files

      if [ "$RESOLVER_TYPE" = "systemd-resolved" ]; then
        apply_systemd_resolved "$DNS_MAIN" "$DNS_FALLBACK"
      elif [ "$RESOLVER_TYPE" = "resolvconf" ]; then
        apply_resolvconf "$NS_LIST"
      else
        apply_static_resolv "$NS_LIST"
      fi

      echo
      echo "$LINE"
      echo " DNS has been updated successfully."
      echo "$LINE"
      echo " Final /etc/resolv.conf:"
      echo "$LINE"
      cat /etc/resolv.conf
      echo "$LINE"
      ;;
    *)
      echo "Cancelled."
      ;;
  esac

  pause
}

custom_dns_menu() {
  DNS_LIST=""
  NS_LIST=""

  echo
  echo "$LINE"
  echo " Custom DNS Setup"
  echo "$LINE"
  echo " Enter DNS one by one."
  echo " Example: 9.9.9.9"
  echo " Press Enter without typing anything when finished."
  echo "$LINE"

  while true; do
    read -p " Enter DNS: " dns_input

    if [ -z "$dns_input" ]; then
      break
    fi

    DNS_LIST="$DNS_LIST $dns_input"
    NS_LIST="${NS_LIST}nameserver $dns_input
"
  done

  if [ -z "$DNS_LIST" ]; then
    echo "No DNS entered. Cancelled."
    pause
    return
  fi

  echo
  echo "$LINE"
  echo " Custom DNS to apply:"
  echo "$NS_LIST"
  echo "$LINE"
  read -p " Continue? [y/N]: " confirm

  case "$confirm" in
    y|Y)
      detect_resolver
      backup_files

      if [ "$RESOLVER_TYPE" = "systemd-resolved" ]; then
        apply_systemd_resolved "$DNS_LIST" ""
      elif [ "$RESOLVER_TYPE" = "resolvconf" ]; then
        apply_resolvconf "$NS_LIST"
      else
        apply_static_resolv "$NS_LIST"
      fi

      echo
      echo "$LINE"
      echo " Custom DNS has been updated successfully."
      echo "$LINE"
      echo " Final /etc/resolv.conf:"
      echo "$LINE"
      cat /etc/resolv.conf
      echo "$LINE"
      ;;
    *)
      echo "Cancelled."
      ;;
  esac

  pause
}

show_full_dns() {
  show_header
  echo " Full /etc/resolv.conf content:"
  echo "$LINE"
  cat /etc/resolv.conf
  echo "$LINE"
  pause
}

main_menu() {
  while true; do
    show_header

    echo " [1] Use ControlD Ads Blocking DNS"
    echo "     Primary : 76.76.2.2, 76.76.10.2"
    echo "     Fallback: 1.1.1.1, 8.8.8.8"
    echo
    echo " [2] Use Default DNS"
    echo "     Primary : 1.1.1.1, 8.8.8.8"
    echo
    echo " [3] Use Custom DNS"
    echo "     Enter your own DNS servers"
    echo
    echo " [4] Show Current DNS Details"
    echo
    echo " [0] Exit"
    echo "$LINE"
    read -p " Select option: " opt

    case "$opt" in
      1)
        apply_dns "ads"
        ;;
      2)
        apply_dns "default"
        ;;
      3)
        custom_dns_menu
        ;;
      4)
        show_full_dns
        ;;
      0)
        echo "Exiting DNS Management System."
        exit 0
        ;;
      *)
        echo "Invalid option."
        pause
        ;;
    esac
  done
}

check_root
main_menu
