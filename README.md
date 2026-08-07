# Management System

Simple yet powerful Linux management utilities designed for VPS administration, networking, and server automation.

---

# Features

## 🔐 Root Login System

Enable root login securely through an automated shell script.

### Features

- Root user detection
- Sudo permission verification
- Root password configuration
- SSH Root Login enablement
- Password Authentication configuration
- Automatic SSH service restart
- Automatic SSH configuration backup

```bash
wget -O mroot https://raw.githubusercontent.com/rewasu91/Management-System/refs/heads/main/mroot.sh && chmod +x mroot && ./mroot
```

---

## 🌐 DNS Management System

Manage DNS settings easily with automatic resolver detection.

### Supported Resolver Systems

- systemd-resolved
- resolvconf
- Static `/etc/resolv.conf`

### Features

- ControlD Ads Blocking DNS
- Restore Default DNS
- Custom DNS Configuration
- Automatic Backup
- DNS Cache Flush
- Automatic Resolver Detection

```bash
wget -O mdns https://raw.githubusercontent.com/rewasu91/Management-System/refs/heads/main/mdns.sh && chmod +x mdns && ./mdns
```

---

## 🧦 SOCKS Management System

Manage SOCKS proxy configurations using a simple interactive menu.

### Features

- SOCKS Configuration Management
- Interactive Shell Interface
- VPS Networking Utilities
- Simple Deployment
- Configuration Management

```bash
wget -O msocks https://raw.githubusercontent.com/rewasu91/Management-System/refs/heads/main/msocks.sh && chmod +x msocks && ./msocks
```

---

## 🔄 VPS Reinstallation System

Reinstall your VPS directly from the terminal without accessing your provider's control panel.

The script automatically detects your VPS provider and recommends compatible operating systems for installation.

### Supported Operating Systems

| Distribution | Supported Versions |
|--------------|-------------------|
| Debian | 11, 12, 13 |
| Ubuntu | 22.04 LTS, 24.04 LTS, 26.04 LTS |

### Features

- Automatic VPS provider detection
- Supported operating system recommendation
- Automatic operating system installation
- Preserve existing root password (supported providers only)
- Automatic network configuration
- Automatic reboot after installation
- Supports major VPS providers

> **Warning**
>
> Reinstalling your VPS will permanently erase all existing data.
>
> Please back up all important files before proceeding.

```bash
wget -O mreinstall https://raw.githubusercontent.com/rewasu91/Management-System/refs/heads/main/mreinstall && chmod +x mreinstall && ./mreinstall
```

---

## 🌐 IPv6 Management System

Disable IPv6 completely to improve compatibility with VPN services, Xray, HAProxy, Nginx, and other networking applications.

### Features

- Disable IPv6 permanently
- Apply changes immediately
- Automatic sysctl configuration
- Automatic GRUB configuration (when required)
- Supports Debian & Ubuntu
- One-click configuration

> **Note**
>
> A system reboot is recommended after disabling IPv6 to ensure all changes are applied.

```bash
wget -O mipv6 https://raw.githubusercontent.com/rewasu91/Management-System/refs/heads/main/mipv6 && chmod +x mipv6 && ./mipv6
```

---

# Requirements

- Root Access
- Debian 11 / 12 / 13
- Ubuntu 22.04 / 24.04 / 26.04
- Internet Connection

---

# Author

**Rewasu91**

GitHub

https://github.com/rewasu91
