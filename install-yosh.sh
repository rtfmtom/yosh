#!/bin/bash
#
# Install yosh from the deployment archive.
# Run as root (or with sudo) on the target Debian 12 system.
#
# Usage: sudo ./install-yosh.sh
#
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE="$SCRIPT_DIR/yosh-debian12-x86_64.tar.gz"

if [ ! -f "$ARCHIVE" ]; then
    echo "ERROR: Archive not found: $ARCHIVE"
    echo "Place yosh-debian12-x86_64.tar.gz in the same directory as this script."
    exit 1
fi

if [ -d /opt/fil/lib ] && [ "$(ls -A /opt/fil/lib 2>/dev/null)" ]; then
    echo "WARNING: /opt/fil/lib already exists and is not empty."
    echo "Existing files may be overwritten. Continue? [y/N]"
    read -r response
    if [ "$response" != "y" ] && [ "$response" != "Y" ]; then
        echo "Aborted."
        exit 1
    fi
fi

echo "Installing yosh..."

# Extract archive
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
tar xzf "$ARCHIVE" -C "$TMPDIR"

# Install runtime libraries
mkdir -p /opt/fil/lib
cp -a "$TMPDIR/opt/fil/lib/"* /opt/fil/lib/
echo "  Installed Fil-C runtime to /opt/fil/lib/"

# Install yosh binary
install -m 755 "$TMPDIR/yosh" /usr/local/bin/yosh
echo "  Installed yosh to /usr/local/bin/yosh"

# Ensure CA certificates are present (needed for HTTPS API calls)
if [ ! -d /etc/ssl/certs ] || [ -z "$(ls /etc/ssl/certs/*.pem 2>/dev/null)" ]; then
    echo "  Installing ca-certificates (needed for HTTPS)..."
    apt-get update -qq && apt-get install -y -qq ca-certificates > /dev/null 2>&1
fi

echo
echo "Done! yosh is installed at /usr/local/bin/yosh"
echo
echo "To use the 'yo' feature, create ~/.yoshkey with your Anthropic API key:"
echo "  echo 'sk-ant-...' > ~/.yoshkey && chmod 600 ~/.yoshkey"
