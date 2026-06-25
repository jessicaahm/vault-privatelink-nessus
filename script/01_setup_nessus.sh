#!/usr/bin/env bash
#
# Setup script to install the Tenable Nessus scanner on Ubuntu/Debian.
#
set -euo pipefail

# --- Configuration ---------------------------------------------------------
NESSUS_VERSION="10.12.0"
NESSUS_PKG="Nessus-${NESSUS_VERSION}-ubuntu1604_amd64.deb"
NESSUS_URL="https://www.tenable.com/downloads/api/v2/pages/nessus/files/${NESSUS_PKG}"
NESSUS_PORT="8834"

# --- Helpers ---------------------------------------------------------------
log() { echo "[nessus-setup] $*"; }

# Re-run privileged commands with sudo if not already root.
SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    log "This script must be run as root (or install sudo)." >&2
    exit 1
  fi
fi

# --- Download --------------------------------------------------------------
if [[ -f "${NESSUS_PKG}" ]]; then
  log "Package ${NESSUS_PKG} already present, skipping download."
else
  log "Downloading Nessus ${NESSUS_VERSION}..."
  curl --fail --location --request GET \
    --url "${NESSUS_URL}" \
    --output "${NESSUS_PKG}"
fi

# --- Install ---------------------------------------------------------------
log "Installing ${NESSUS_PKG}..."
if ! ${SUDO} dpkg -i "${NESSUS_PKG}"; then
  log "Resolving missing dependencies..."
  ${SUDO} apt-get update
  ${SUDO} apt-get install -f -y
fi

# --- Service ---------------------------------------------------------------
log "Enabling and starting nessusd..."
${SUDO} systemctl enable nessusd
${SUDO} systemctl start nessusd

# Give the daemon a moment to come up, then check status.
sleep 5
${SUDO} systemctl --no-pager status nessusd || true

# --- Verify ----------------------------------------------------------------
log "Verifying Nessus web interface on port ${NESSUS_PORT}..."
if curl -k -s -o /dev/null -w "%{http_code}" "https://localhost:${NESSUS_PORT}" | grep -q "200\|302\|401"; then
  log "Nessus is up. Open https://<host>:${NESSUS_PORT} to complete setup."
else
  log "Nessus may still be initializing. It can take a few minutes on first start."
fi
