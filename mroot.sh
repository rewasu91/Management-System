#!/bin/bash

# ==========================================================
# ROOT LOGIN SYSTEM - SAFE SSH CONFIGURATION
# ==========================================================

clear

line() {
    echo "----------------------------------------------------------"
}

header() {
    line
    echo "                 ROOT LOGIN SYSTEM"
    line
}

header

echo "Checking current user..."
echo

if [ "$(id -u)" -eq 0 ]; then
    echo "Status : Already running as ROOT."
else
    echo "Status : Running as non-root user."
    echo "Action : Sudo will be used where required."
fi

line

# ==========================================================
# CHECK SUDO
# ==========================================================

echo
echo "Checking sudo permission..."

if [ "$(id -u)" -ne 0 ]; then
    if ! sudo -v; then
        echo
        echo "Error  : This user does not have sudo permission."
        echo "Result : Unable to configure root SSH login."
        line
        exit 1
    fi

    echo "Status : Sudo permission verified."
else
    echo "Status : Already root. Sudo is not required."
fi

line

# ==========================================================
# SUDO WRAPPER
# ==========================================================

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# ==========================================================
# SET ROOT PASSWORD
# ==========================================================

echo
echo "Setting / updating root password..."
echo
echo "Please enter the new ROOT password when prompted."
echo

$SUDO passwd root

if [ $? -ne 0 ]; then
    echo
    echo "Error  : Failed to set root password."
    line
    exit 1
fi

echo
echo "Status : Root password configured."
line

# ==========================================================
# SSH CONFIGURATION
# ==========================================================

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DIR="/etc/ssh/sshd_config.d"

echo
echo "Checking SSH configuration..."

if [ ! -f "$SSHD_CONFIG" ]; then
    echo "Error  : SSH configuration file not found."
    echo "Path   : $SSHD_CONFIG"
    line
    exit 1
fi

# ==========================================================
# BACKUP
# ==========================================================

BACKUP_DIR="/etc/ssh/root-login-backup-$(date +%Y%m%d%H%M%S)"

echo
echo "Creating SSH configuration backup..."

$SUDO mkdir -p "$BACKUP_DIR"

$SUDO cp -a "$SSHD_CONFIG" "$BACKUP_DIR/sshd_config"

if [ -d "$SSHD_DIR" ]; then
    $SUDO cp -a "$SSHD_DIR" "$BACKUP_DIR/sshd_config.d"
fi

echo "Backup : $BACKUP_DIR"

line

# ==========================================================
# DISABLE CONFLICTING GLOBAL SSH SETTINGS
# ==========================================================

echo
echo "Removing conflicting SSH authentication settings..."

# Disable conflicting directives in main sshd_config.
# They will be replaced with known-good values below.

$SUDO sed -i \
    -E 's/^[[:space:]]*#?[[:space:]]*(PermitRootLogin)[[:space:]].*/# Disabled by Root Login System: \1/' \
    "$SSHD_CONFIG"

$SUDO sed -i \
    -E 's/^[[:space:]]*#?[[:space:]]*(PasswordAuthentication)[[:space:]].*/# Disabled by Root Login System: \1/' \
    "$SSHD_CONFIG"

$SUDO sed -i \
    -E 's/^[[:space:]]*#?[[:space:]]*(KbdInteractiveAuthentication)[[:space:]].*/# Disabled by Root Login System: \1/' \
    "$SSHD_CONFIG"

$SUDO sed -i \
    -E 's/^[[:space:]]*#?[[:space:]]*(AuthenticationMethods)[[:space:]].*/# Disabled by Root Login System: \1/' \
    "$SSHD_CONFIG"

# ==========================================================
# FIX CONFIGURATION FILES UNDER sshd_config.d
# ==========================================================

if [ -d "$SSHD_DIR" ]; then

    echo
    echo "Checking SSH configuration fragments..."

    while IFS= read -r -d '' FILE; do

        # PermitRootLogin
        $SUDO sed -i \
            -E 's/^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]].*/# Disabled by Root Login System: PermitRootLogin/' \
            "$FILE"

        # PasswordAuthentication
        $SUDO sed -i \
            -E 's/^[[:space:]]*#?[[:space:]]*PasswordAuthentication[[:space:]].*/# Disabled by Root Login System: PasswordAuthentication/' \
            "$FILE"

        # KbdInteractiveAuthentication
        $SUDO sed -i \
            -E 's/^[[:space:]]*#?[[:space:]]*KbdInteractiveAuthentication[[:space:]].*/# Disabled by Root Login System: KbdInteractiveAuthentication/' \
            "$FILE"

        # AuthenticationMethods
        $SUDO sed -i \
            -E 's/^[[:space:]]*#?[[:space:]]*AuthenticationMethods[[:space:]].*/# Disabled by Root Login System: AuthenticationMethods/' \
            "$FILE"

    done < <(find "$SSHD_DIR" -type f \( -name "*.conf" -o -name "*.cfg" \) -print0)

fi

line

# ==========================================================
# CREATE DEDICATED ROOT LOGIN CONFIG
# ==========================================================

ROOT_CONF="$SSHD_DIR/00-root-login.conf"

echo
echo "Creating dedicated root login configuration..."

$SUDO mkdir -p "$SSHD_DIR"

$SUDO tee "$ROOT_CONF" >/dev/null <<'EOF'
# ==========================================================
# Root Login System
# ==========================================================

PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
AuthenticationMethods any
EOF

echo "Created : $ROOT_CONF"

line

# ==========================================================
# CHECK USER/GROUP RESTRICTIONS
# ==========================================================

echo
echo "Checking AllowUsers / DenyUsers restrictions..."

# Remove explicit root from DenyUsers.
if grep -RqsE '^[[:space:]]*DenyUsers[[:space:]].*\broot\b' \
    "$SSHD_CONFIG" "$SSHD_DIR" 2>/dev/null; then

    echo "Warning: root was found in DenyUsers."
    echo "Action : Removing root from DenyUsers..."

    $SUDO sed -i -E \
        's/^([[:space:]]*DenyUsers[[:space:]]+.*)[[:space:]]+\broot\b/\1/' \
        "$SSHD_CONFIG"

    if [ -d "$SSHD_DIR" ]; then
        while IFS= read -r -d '' FILE; do
            $SUDO sed -i -E \
                's/^([[:space:]]*DenyUsers[[:space:]]+.*)[[:space:]]+\broot\b/\1/' \
                "$FILE"
        done < <(find "$SSHD_DIR" -type f -name "*.conf" -print0)
    fi
fi

# If AllowUsers exists, make sure root is included.
if grep -RqsE '^[[:space:]]*AllowUsers[[:space:]]' \
    "$SSHD_CONFIG" "$SSHD_DIR" 2>/dev/null; then

    if ! grep -RhsE '^[[:space:]]*AllowUsers[[:space:]]' \
        "$SSHD_CONFIG" "$SSHD_DIR" 2>/dev/null | grep -qw root; then

        echo "Warning: AllowUsers exists but root is not listed."
        echo "Action : Adding root to AllowUsers..."

        $SUDO sed -i -E \
            '/^[[:space:]]*AllowUsers[[:space:]]/ s/$/ root/' \
            "$SSHD_CONFIG"

    fi
fi

line

# ==========================================================
# CHECK ROOT ACCOUNT STATUS
# ==========================================================

echo
echo "Checking root account..."

ROOT_STATUS="$(passwd -S root 2>/dev/null || true)"

echo "$ROOT_STATUS"

if echo "$ROOT_STATUS" | grep -qE '^[^ ]+[[:space:]]+L'; then
    echo
    echo "Root account appears to be LOCKED."
    echo "Action : Unlocking root account..."

    $SUDO passwd -u root
fi

line

# ==========================================================
# VALIDATE SSH SYNTAX
# ==========================================================

echo
echo "Validating SSH configuration..."

if ! $SUDO sshd -t; then
    echo
    echo "=========================================================="
    echo "ERROR: SSH CONFIGURATION TEST FAILED"
    echo "=========================================================="
    echo
    echo "Restoring previous configuration..."

    $SUDO cp -a "$BACKUP_DIR/sshd_config" "$SSHD_CONFIG"

    if [ -d "$BACKUP_DIR/sshd_config.d" ]; then
        $SUDO rm -rf "$SSHD_DIR"
        $SUDO cp -a "$BACKUP_DIR/sshd_config.d" "$SSHD_DIR"
    fi

    echo
    echo "Result : Previous SSH configuration restored."
    line
    exit 1
fi

echo "Status : SSH syntax is valid."

line

# ==========================================================
# CHECK EFFECTIVE SSH CONFIGURATION
# ==========================================================

echo
echo "Checking EFFECTIVE SSH configuration for root..."

EFFECTIVE_CONFIG="$($SUDO sshd -T -C user=root,host=localhost,addr=127.0.0.1 2>/dev/null)"

if [ -z "$EFFECTIVE_CONFIG" ]; then
    echo
    echo "Error  : Unable to read effective SSH configuration."
    echo "Result : SSH was NOT restarted."
    line
    exit 1
fi

PERMIT_ROOT="$(echo "$EFFECTIVE_CONFIG" | awk '$1=="permitrootlogin"{print $2}')"
PASSWORD_AUTH="$(echo "$EFFECTIVE_CONFIG" | awk '$1=="passwordauthentication"{print $2}')"
KBD_AUTH="$(echo "$EFFECTIVE_CONFIG" | awk '$1=="kbdinteractiveauthentication"{print $2}')"
AUTH_METHODS="$(echo "$EFFECTIVE_CONFIG" | awk '$1=="authenticationmethods"{print substr($0,index($0,$2))}')"

echo
echo "Effective SSH settings:"
echo
echo "PermitRootLogin           : ${PERMIT_ROOT:-UNKNOWN}"
echo "PasswordAuthentication    : ${PASSWORD_AUTH:-UNKNOWN}"
echo "KbdInteractiveAuthentication : ${KBD_AUTH:-UNKNOWN}"
echo "AuthenticationMethods     : ${AUTH_METHODS:-any}"

line

# ==========================================================
# FINAL SAFETY CHECK
# ==========================================================

echo
echo "Performing final root-login check..."

FAIL=0

if [ "$PERMIT_ROOT" != "yes" ]; then
    echo "ERROR: PermitRootLogin is NOT yes."
    FAIL=1
fi

if [ "$PASSWORD_AUTH" != "yes" ]; then
    echo "ERROR: PasswordAuthentication is NOT yes."
    FAIL=1
fi

if [ "$AUTH_METHODS" != "any" ] && [ -n "$AUTH_METHODS" ]; then
    echo "ERROR: AuthenticationMethods may still restrict password login."
    FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
    echo
    echo "=========================================================="
    echo "WARNING: ROOT PASSWORD LOGIN IS NOT FULLY VERIFIED"
    echo "=========================================================="
    echo
    echo "SSH will NOT be restarted automatically."
    echo
    echo "Effective configuration:"
    echo "$EFFECTIVE_CONFIG" | grep -E \
        '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|authenticationmethods|allowusers|denyusers|allowgroups|denygroups)'
    line
    exit 1
fi

echo "Status : Root password authentication is enabled."

line

# ==========================================================
# RESTART SSH
# ==========================================================

echo
echo "Restarting SSH service..."

if systemctl restart ssh 2>/dev/null; then

    echo "Status : SSH service restarted successfully."

elif systemctl restart sshd 2>/dev/null; then

    echo "Status : SSHD service restarted successfully."

else

    echo
    echo "ERROR  : Unable to restart SSH service."
    echo
    echo "Try manually:"
    echo "  systemctl restart ssh"
    echo "  systemctl restart sshd"

    line
    exit 1
fi

line

# ==========================================================
# FINAL STATUS
# ==========================================================

echo
echo "=========================================================="
echo "              ROOT LOGIN CONFIGURATION"
echo "=========================================================="
echo
echo "Root password             : CONFIGURED"
echo "PermitRootLogin           : YES"
echo "PasswordAuthentication    : YES"
echo "KbdInteractiveAuthentication : YES"
echo "AuthenticationMethods     : ANY"
echo "SSH service               : RESTARTED"
echo
echo "Root SSH login should now accept:"
echo
echo "    ssh root@YOUR_SERVER_IP"
echo
echo "=========================================================="

exit 0
