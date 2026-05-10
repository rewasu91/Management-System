#!/bin/bash

# ==========================================================
# Root Login System
# ==========================================================

clear

line() {
    echo "----------------------------------------------------------"
}

header() {
    line
    echo "                   ROOT LOGIN SYSTEM"
    line
}

pause() {
    echo
    read -rp "Press Enter to continue..."
}

header

if [ "$(id -u)" -eq 0 ]; then
    echo "Status : You are already logged in as root."
    echo "Action : No changes are required."
    line
    exit 0
fi

echo "Status : You are not logged in as root."
echo "Action : The system will prepare root login access."
line

echo
echo "Checking sudo permission..."

if ! sudo -v; then
    echo
    echo "Error  : This user does not have sudo permission."
    echo "Result : Unable to enable root login."
    line
    exit 1
fi

echo "Status : Sudo permission verified."
line

echo
echo "Setting root password..."
echo "Please enter the new root password when prompted."

sudo passwd root

if [ $? -ne 0 ]; then
    echo
    echo "Error  : Failed to set root password."
    echo "Result : Root login was not enabled."
    line
    exit 1
fi

line
echo "Updating SSH configuration..."

SSHD_CONFIG="/etc/ssh/sshd_config"

if [ ! -f "$SSHD_CONFIG" ]; then
    echo "Error  : SSH configuration file not found."
    echo "Path   : $SSHD_CONFIG"
    line
    exit 1
fi

sudo cp "$SSHD_CONFIG" "$SSHD_CONFIG.backup.$(date +%Y%m%d%H%M%S)"

sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$SSHD_CONFIG"
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"

if ! grep -q "^PermitRootLogin yes" "$SSHD_CONFIG"; then
    echo "PermitRootLogin yes" | sudo tee -a "$SSHD_CONFIG" >/dev/null
fi

if ! grep -q "^PasswordAuthentication yes" "$SSHD_CONFIG"; then
    echo "PasswordAuthentication yes" | sudo tee -a "$SSHD_CONFIG" >/dev/null
fi

line
echo "Restarting SSH service..."

if sudo systemctl restart ssh 2>/dev/null; then
    echo "Status : SSH service restarted successfully."
elif sudo systemctl restart sshd 2>/dev/null; then
    echo "Status : SSHD service restarted successfully."
else
    echo "Warning: Unable to restart SSH service automatically."
    echo "Please restart SSH manually using one of these commands:"
    echo "        sudo systemctl restart ssh"
    echo "        sudo systemctl restart sshd"
fi

line
echo "Result : Root login has been enabled successfully."
echo "Info   : You can now login as root using the password you set."
line

exit 0
