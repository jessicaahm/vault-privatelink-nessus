export VAULT_NAMESPACE=admin

# Write the policy defined in nessus-policy.hcl for approle
vault policy write --namespace=admin nessus-policy nessus-policy.hcl

# Enable Approle
vault auth enable --namespace=admin approle

# Create an Approle
vault write --namespace=admin auth/approle/role/nessus token_policies="nessus-policy" \
    token_ttl=1h token_max_ttl=4h

# Read Approle
vault read --namespace=admin auth/approle/role/nessus
export ROLE_ID=$(vault read --namespace=admin -field=role_id auth/approle/role/nessus/role-id)
export SECRET_ID=$(vault write --namespace=admin -force -field=secret_id auth/approle/role/nessus/secret-id)

echo "ROLE_ID: $ROLE_ID"
echo "SECRET_ID: $SECRET_ID"

# Test Login
vault write --namespace=admin auth/approle/login role_id="$ROLE_ID" \
    secret_id="$SECRET_ID"
