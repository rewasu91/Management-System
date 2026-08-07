# Management System

Simple Linux management utilities for VPS and networking systems.

---

# Features

## Root Login System

Enable root login access safely through an automated shell script.

Included features:
- Root user detection
- Sudo permission checking
- Root password setup
- SSH root login configuration
- Password authentication enablement
- SSH service restart
- Automatic SSH configuration backup

---

## DNS Management System

Manage DNS profiles with automatic resolver detection support.

Supported resolver systems:
- systemd-resolved
- resolvconf
- static `/etc/resolv.conf`

Included features:
- ControlD Ads Blocking DNS
- Default DNS
- Custom DNS Setup
- Automatic backup
- DNS cache flush
- Resolver auto detection

---

## Socks Management System

Manage SOCKS proxy configurations easily through an interactive shell menu.

Included features:
- SOCKS configuration management
- Interactive shell interface
- VPS networking utilities
- Simple deployment system

---

# Installation

## Root Login System

```bash
wget -O mroot https://raw.githubusercontent.com/rewasu91/Management-System/refs/heads/main/mroot.sh && chmod +x mroot && ./mroot
```

---

## DNS Management System

```bash
wget -O mdns https://raw.githubusercontent.com/rewasu91/Management-System/refs/heads/main/mdns.sh && chmod +x mdns && ./mdns
```

---

## Socks Management System

```bash
wget -O msocks https://raw.githubusercontent.com/rewasu91/Management-System/refs/heads/main/msocks.sh && chmod +x msocks && ./msocks
```

---

## Reinstall VPS

```bash
wget -O mreinstall https://raw.githubusercontent.com/rewasu91/Management-System/refs/heads/main/mreinstall && chmod +x mreinstall && ./mreinstall
```

---

## Disable IPV6

```bash
wget -O mipv6 https://raw.githubusercontent.com/rewasu91/Management-System/refs/heads/main/mipv6 && chmod +x mipv6 && ./mipv6
```

---

# DNS Profiles

## ControlD Ads Blocking DNS

Primary DNS:
- 76.76.2.2
- 76.76.10.2

Fallback DNS:
- 1.1.1.1
- 8.8.8.8

Recommended for:
- Website ads blocking
- Stable YouTube playback
- Streaming compatibility
- General browsing

---

## Default DNS

DNS:
- 1.1.1.1
- 8.8.8.8

Recommended for:
- Maximum compatibility
- Gaming
- Raw performance
- Minimal filtering

---

# Supported Systems

- Ubuntu
- Debian
- VPS Linux environments
- systemd-resolved
- resolvconf
- static resolver systems
- OpenSSH server environments

---

# Notes

- Run scripts as root or with sudo permission.
- Scripts automatically detect resolver type where applicable.
- Existing DNS configurations are backed up automatically.
- DNS cache is flushed automatically after applying changes.
- Root Login System automatically backs up SSH configuration before making changes.

---

# Author

GitHub:
https://github.com/rewasu91
