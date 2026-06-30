# Enable PKI Secret Engine to generate certificate
vault secrets enable -namespace=admin pki
vault secrets tune -max-lease-ttl=8760h -namespace=admin pki

# Generate Root CA
vault write -namespace=admin pki/root/generate/internal \
    common_name=example.com \
    ttl=8760h

# Update CRL Location and Issuing Certificates URLs
vault write -namespace=admin pki/config/urls \
    issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
    crl_distribution_points="$VAULT_ADDR/v1/pki/crl"

# Configure a role that allows for certificate issuance
vault write -namespace=admin pki/roles/example-dot-com \
    allowed_domains=example.com \
    allow_subdomains=true \
    max_ttl=72h

# Write a certificate
vault write -namespace=admin pki/issue/example-dot-com \
    common_name=scanner1.example.com

# Enable Auth Method for Certs
vault auth enable -namespace=admin cert

# Load the policy that grants PKI issuance + KV access for the scanner token.
vault policy write -namespace=admin nessus nessus-policy.hcl

# Configure it with trusted cert. Attach the nessus policy (not just default)
# so the cert-auth token can re-issue certs from pki/issue/example-dot-com;
# otherwise Vault Agent's template gets 403 permission denied.
vault write -namespace=admin auth/cert/certs/web \
    display_name=web \
    policies=nessus \
    certificate=@ca-cert.pem \
    allowed_common_names=scanner1.example.com \
    ttl=3600

# login
curl \
    --request POST \
    --header "X-Vault-Namespace: admin" \
    --cert public.pem \
    --key key.pem \
    --data '{"name": "web"}' \
    $VAULT_ADDR/v1/auth/cert/login
