# Mixfile

Simple Linux management utilities for VPS and networking systems.

---

## Features

### Socks Management System
Manage SOCKS proxy configurations easily through an interactive shell menu.

### DNS Management System
Manage DNS profiles with automatic resolver detection support:
- systemd-resolved
- resolvconf
- static `/etc/resolv.conf`

Includes:
- ControlD Ads Blocking DNS
- Default DNS
- Custom DNS Setup
- Automatic backup
- DNS cache flush
- Resolver auto detection

---

# Installation

## Socks Management System

```bash
wget -O msocks https://raw.githubusercontent.com/rewasu91/mixfile/refs/heads/main/msocks.sh && chmod +x msocks && ./msocks
```

---

## DNS Management System

```bash
wget -O mdns https://raw.githubusercontent.com/rewasu91/mixfile/refs/heads/main/mdns.sh && chmod +x mdns && ./mdns
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

---

# Notes

- Run scripts as root.
- Scripts automatically detect resolver type.
- Existing DNS configurations are backed up automatically.
- DNS cache is flushed automatically after applying changes.

---

# Author

GitHub:
https://github.com/rewasu91
