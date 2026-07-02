#!/usr/bin/env bash
#
# Push the freshly-renewed Vault client cert (public.pem) and private key
# (key.pem) to the central HashiCorp Vault managed credential in Tenable
# Vulnerability Management, so scans keep authenticating to Vault after the
# short-lived (ttl=3600) PKI cert rotates.
#
# Invoked from renew-cert.sh, which reads the Nessus API keys from Vault KV
# (using the token in ./vault-token) and passes them in as arguments:
#   ./update-nessus-cred.sh <credential-uuid> <access-key> <secret-key>
# Each also falls back to its matching environment variable.
set -euo pipefail


ate-nessus-cred] $*"; }
die() { echo "[update-nessus-cred] ERROR: $*" >&2; exit 1; }

# --- Configuration ---------------------------------------------------------
NESSUS_CREDENTIAL_UUID="${1:-${NESSUS_CREDENTIAL_UUID:-}}"
NESSUS_ACCESS_KEY="${2:-${NESSUS_ACCESS_KEY:-}}"
NESSUS_SECRET_KEY="${3:-${NESSUS_SECRET_KEY:-}}"
NESSUS_API_URL="${NESSUS_API_URL:-https://cloud.tenable.com}"
CERT_FILE="${NESSUS_CERT_FILE:-public.pem}"
KEY_FILE="${NESSUS_KEY_FILE:-key.pem}"

# Tenable credential field ids for the HashiCorp Vault "Certificates" auth.
CERT_FIELD="${NESSUS_CERT_FIELD:-hashicorp_client_cert}"
KEY_FIELD="${NESSUS_KEY_FIELD:-hashicorp_private_key}"
NESSUS_AUTH_TYPE="${NESSUS_AUTH_TYPE:-Certificates}"
NESSUS_AUTH_URL="${NESSUS_AUTH_URL:-/v1/auth/cert/login}"

# --- Preflight -------------------------------------------------------------
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq   >/dev/null 2>&1 || die "jq is required"

: "${NESSUS_ACCESS_KEY:?NESSUS_ACCESS_KEY is not set}"
: "${NESSUS_SECRET_KEY:?NESSUS_SECRET_KEY is not set}"
: "${NESSUS_CREDENTIAL_UUID:?NESSUS_CREDENTIAL_UUID is not set (pass as first arg)}"
[[ -r "$CERT_FILE" ]] || die "client cert not found/readable: $CERT_FILE"
[[ -r "$KEY_FILE"  ]] || die "private key not found/readable: $KEY_FILE"

AUTH_HEADER="X-ApiKeys: accessKey=${NESSUS_ACCESS_KEY}; secretKey=${NESSUS_SECRET_KEY}"

# api METHOD PATH [curl args...] -> stdout is the response body; non-2xx fails.
api() {
  local method="$1" path="$2"; shift 2
  curl -sf --request "$method" --header "$AUTH_HEADER" "$@" "${NESSUS_API_URL}${path}"
}

# --- 1. Upload the new cert + key ------------------------------------------
# POST /credentials/files?fileType=pem returns {"fileuploaded": "<ref>"}.
upload_file() {
  local path="$1" resp ref
  resp="$(api POST "/credentials/files?fileType=pem" --form "Filedata=@${path}")" \
    || die "upload failed for $path"
  ref="$(printf '%s' "$resp" | jq -r '.fileuploaded // empty')"
  [[ -n "$ref" ]] || die "no fileuploaded ref returned for $path: $resp"
  printf '%s' "$ref"
}

log "uploading client cert ($CERT_FILE)"
cert_ref="$(upload_file "$CERT_FILE")"
log "uploading private key ($KEY_FILE)"
key_ref="$(upload_file "$KEY_FILE")"

# --- 2. Update the managed credential --------------------------------------
# A PUT validates the WHOLE settings object, so fetch current settings and
# merge the new cert/key refs in (otherwise Tenable 400s on required fields
# like auth_method). Drop masked (null) fields the API won't return.
cur_settings="$(api GET "/credentials/${NESSUS_CREDENTIAL_UUID}" | jq '.settings')" \
  || die "GET /credentials/${NESSUS_CREDENTIAL_UUID} failed"

body="$(printf '%s' "$cur_settings" | jq \
  --arg cf "$CERT_FIELD" --arg cr "$cert_ref" \
  --arg kf "$KEY_FIELD"  --arg kr "$key_ref" \
  --arg at "$NESSUS_AUTH_TYPE" --arg au "$NESSUS_AUTH_URL" \
  '{settings: (with_entries(select(.value != null)) + {
      hashicorp_authentication_type: $at,
      hashicorp_auth_url: $au,
      ($cf): $cr,
      ($kf): $kr
    })}')"

log "updating managed credential ${NESSUS_CREDENTIAL_UUID} (auth=$NESSUS_AUTH_TYPE)"
api PUT "/credentials/${NESSUS_CREDENTIAL_UUID}" \
  --header "Content-Type: application/json" \
  --data "$body" >/dev/null \
  || die "PUT /credentials/${NESSUS_CREDENTIAL_UUID} failed"

log "SUCCESS: managed credential updated with renewed cert/key"
