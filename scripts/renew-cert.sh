#!/usr/bin/env bash
# Triggered by Vault Agent's template exec block whenever a fresh client
# cert (public.pem / private.pem) is rendered ahead of the ttl=3600 expiry.
# Use it to reload whatever consumes the cert and to re-verify the login.
set -euo pipefail

# Vault cluster address. Vault Agent does not export VAULT_ADDR to template
# exec commands, so set it here. Override via the environment if it differs.
VAULT_ADDR="${VAULT_ADDR:-https://vault-cluster-private-vault-289b32ee.99820ad2.z1.hashicorp.cloud:8200}"
# Passed to update-nessus-cred.sh as its first argument (see below).
NESSUS_CREDENTIAL_UUID="${NESSUS_CREDENTIAL_UUID:-e15e515e-e20e-4e52-94df-e6edb5ab317e}"

# Append a timestamped line to the log file (override path via RENEW_CERT_LOG).
RENEW_CERT_LOG="${RENEW_CERT_LOG:-/home/ubuntu/log/renew-cert.log}"
mkdir -p "$(dirname "$RENEW_CERT_LOG")"
log() { echo "[$(date -u +%FT%TZ)] [renew-cert] $*" >>"$RENEW_CERT_LOG"; }

log "new cert rendered"

# Cert/key files written by the Vault Agent templates. Must match the
# destinations/auto_auth client_key in agent-config.hcl.
CERT_FILE="${CERT_FILE:-public.pem}"
KEY_FILE="${KEY_FILE:-key.pem}"

# Re-login with the freshly issued cert to confirm it is accepted. Capture
# curl's stderr + HTTP status so a failure says *why* in the log, rather than
# a bare "FAILED". (--cacert trusts the issuing CA the template wrote.)
login_err="$(curl -sS \
    --cacert ca-cert.pem \
    --request POST \
    --header "X-Vault-Namespace: admin" \
    --cert "$CERT_FILE" \
    --key "$KEY_FILE" \
    --data '{"name": "web"}' \
    --write-out 'HTTP %{http_code}' \
    --output /dev/null \
    "$VAULT_ADDR/v1/auth/cert/login" 2>&1)" \
  && log "cert login OK ($login_err)" \
  || { log "cert login FAILED: $login_err"; exit 1; }

# Push the renewed cert/key to the central Tenable managed credential so scans
# keep authenticating to Vault. Skipped (not failed) if it isn't configured,
# so cert renewal itself never breaks on an unconfigured host.
# Fetch the Tenable API keys from Vault KV2 using the token Vault Agent
# dropped in ./vault-token (auto_auth sink). update-nessus-cred.sh reads
# them from NESSUS_ACCESS_KEY / NESSUS_SECRET_KEY.
VAULT_KV_PATH="${VAULT_KV_PATH:-secret/amazonlinux/nessus}"
secret_json="$(curl -sS \
    --cacert ca-cert.pem \
    --header "X-Vault-Namespace: admin" \
    --header "X-Vault-Token: $(cat ./vault-token)" \
    "$VAULT_ADDR/v1/${VAULT_KV_PATH/\///data/}" 2>&1)" \
  || { log "failed to read $VAULT_KV_PATH from Vault: $secret_json"; exit 1; }

NESSUS_ACCESS_KEY="$(printf '%s' "$secret_json" | jq -r '.data.data.nessus_access_key')"
NESSUS_SECRET_KEY="$(printf '%s' "$secret_json" | jq -r '.data.data.nessus_secret_key')"

# Point update-nessus-cred.sh at the same cert/key files the agent wrote
# (the key is key.pem here, not its default private.pem).
export NESSUS_CERT_FILE="$CERT_FILE" NESSUS_KEY_FILE="$KEY_FILE"

# Tenable credential field ids for the HashiCorp Vault "Certificates" auth
# (from GET /credentials/types: Authentication Type -> Certificates option).
# Skip auto-discovery by naming them here.
export NESSUS_CERT_FIELD="${NESSUS_CERT_FIELD:-hashicorp_client_cert}"
export NESSUS_KEY_FIELD="${NESSUS_KEY_FIELD:-hashicorp_private_key}"

log "pushing renewed cert/key to Tenable credential $NESSUS_CREDENTIAL_UUID"
if ./update-nessus-cred.sh "$NESSUS_CREDENTIAL_UUID" "$NESSUS_ACCESS_KEY" "$NESSUS_SECRET_KEY" >>"$RENEW_CERT_LOG" 2>&1; then
  log "Tenable credential updated"
else
  log "update-nessus-cred.sh FAILED (see output above)"
  exit 1
fi
