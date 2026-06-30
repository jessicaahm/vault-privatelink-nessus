# Enable KV2 Secret Engine
vault secrets enable --namespace=admin --version=2 --path=secret kv

vault kv put --namespace=admin secret/amazonlinux/nessus nessus_access_key="$NESSUS_ACCESS_KEY" nessus_secret_key="$NESSUS_SECRET_KEY" username="ec2-user" target="ec2-13-214-201-96.ap-southeast-1.compute.amazonaws.com" private_key=@nessus.pem

# Read the secret:
vault kv get --namespace=admin secret/amazonlinux/nessus


