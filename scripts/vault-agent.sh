#!/usr/bin/env bash
set -euo pipefail

# Run from this script's directory so the agent's relative paths
# (public.pem, key.pem, ca-cert.pem, ./vault-token) resolve correctly.
cd "$(dirname "$0")"

# Tenable managed-credential UUID. renew-cert.sh (run by the agent's template
# exec) pushes the renewed cert/key to this credential when set; if unset, the
# Tenable update is skipped. Obtain the UUID per "Obtaining the UUID" in
# VAULT-CONFIG.md.

vault agent -config=agent-config.hcl
