# Mount the AppRole auth method
path "sys/auth/approle" {
  capabilities = [ "create", "read", "update", "delete", "sudo" ]
}

# Configure the AppRole auth method
path "sys/auth/approle/*" {
  capabilities = [ "create", "read", "update", "delete" ]
}

# Create and manage roles
path "auth/approle/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

# Write ACL policies
path "sys/policies/acl/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

# Read/write the Nessus secret. This is a KV v2 mount, so data lives under
# secret/data/... (renew-cert.sh reads secret/data/amazonlinux/nessus).
path "secret/data/amazonlinux/nessus" {
  capabilities = [ "create", "read", "update", "delete" ]
}
path "secret/metadata/amazonlinux/nessus" {
  capabilities = [ "read", "list" ]
}

# Issue client certs from the PKI engine so the cert-auth token can
# re-issue public.pem / private.pem ahead of expiry (matches the
# template in agent-config.hcl).
path "pki/issue/example-dot-com" {
  capabilities = [ "create", "update" ]
}
