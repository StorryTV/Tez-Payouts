#!/bin/bash
set -euo pipefail

# install.sh
# Installs dependencies, downloads the payout script into /var/tezos/,
# ensures ownership for user `tezos`, and adds a cron entry for that user
# if it doesn't already exist.

SCRIPT_URL='https://raw.githubusercontent.com/StorryTV/Tez-Payouts/refs/heads/main/tez-payouts.sh'
DEST_DIR='/var/tezos'
DEST_PATH="$DEST_DIR/tez-payouts.sh"
TEZOS_USER='tezos'
CRONLINE='*/30 * * * * /var/tezos/tez-payouts.sh >> /var/log/tez-payouts.log 2>&1'

# Helper: exit with message
err() { echo "ERROR: $*" >&2; exit 1; }

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root (sudo)."
fi

# Create tezos user if it doesn't exist
if ! id "$TEZOS_USER" >/dev/null 2>&1; then
  echo "Creating user '$TEZOS_USER' (system account)..."
  useradd --system --home "$DEST_DIR" --shell /usr/sbin/nologin "$TEZOS_USER"
fi

# Install packages (Debian/Ubuntu)
echo "Installing required packages..."
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y curl jq bc awk
  # Try to install octez-client (Tezos client). Package name may vary.
  if ! command -v octez-client >/dev/null 2>&1; then
    echo "Attempting to install octez-client from official repository..."
    # Best-effort: try common package name, otherwise skip and warn.
    apt-get install -y octez-client || true
  fi
else
  echo "Automatic package installation supported only for Debian/Ubuntu (apt)."
  echo "Please install: curl, jq, bc, awk, and octez-client manually."
fi

# Create destination dir and set ownership/permissions
echo "Preparing $DEST_DIR..."
mkdir -p "$DEST_DIR"
chown root:"$TEZOS_USER" "$DEST_DIR"
chmod 750 "$DEST_DIR"

# Download the script
echo "Downloading payout script to $DEST_PATH..."
curl -fsSL "$SCRIPT_URL" -o "$DEST_PATH" || err "Failed to download script."
chmod 750 "$DEST_PATH"
chown root:"$TEZOS_USER" "$DEST_PATH"

# Ensure state dir exists and owned by tezos
STATE_DIR='/var/lib/tezos'
mkdir -p "$STATE_DIR"
chown "$TEZOS_USER":"$TEZOS_USER" "$STATE_DIR"
chmod 750 "$STATE_DIR"

# Install cron entry if not present
echo "Checking crontab for user $TEZOS_USER..."
# Get existing crontab (ignore errors if none)
if crontab -u "$TEZOS_USER" -l >/tmp/.tezos_cron 2>/dev/null; then
  CRON_EXISTS=$(grep -F -- "$CRONLINE" /tmp/.tezos_cron || true)
  if [ -n "$CRON_EXISTS" ]; then
    echo "Cron line already present; leaving crontab unchanged."
  else
    echo "Adding cron line to existing crontab..."
    { cat /tmp/.tezos_cron; echo "$CRONLINE"; } | crontab -u "$TEZOS_USER" -
    echo "Cron added."
  fi
  rm -f /tmp/.tezos_cron
else
  echo "No crontab for $TEZOS_USER, creating one with cron line..."
  echo "$CRONLINE" | crontab -u "$TEZOS_USER" -
fi

# Ensure log file exists and is writable by owner root and group tezos for append by cron
LOGFILE='/var/log/tez-payouts.log'
touch "$LOGFILE"
chown root:"$TEZOS_USER" "$LOGFILE"
chmod 640 "$LOGFILE"

echo "Install complete."
echo "Script: $DEST_PATH"
echo "Cron: $CRONLINE (for user $TEZOS_USER)"
