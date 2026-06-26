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

# Configure it with trusted cert 
vault write --namespace=admin auth/cert/certs/web \
    display_name=web \
    policies=default \
    certificate=@public.pem \
    ttl=3600

# login
curl \
    --request POST \
    --header "X-Vault-Namespace: admin" \
    --cacert vault-ca.pem \
    --cert public.pem \
    --key key.pem \
    --data '{"name": "web"}' \
    $VAULT_ADDR/v1/auth/cert/login
