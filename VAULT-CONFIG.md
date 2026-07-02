# Configure Vault TLS Auth methods


# Push renewed cert to Tenable

Vault Agent rotates the short-lived (`ttl=3600`) PKI client cert to
`public.pem` / `private.pem` and runs `scripts/renew-cert.sh` on each renewal,
which calls `scripts/update-nessus-cred.sh` to push the new cert/key to the
central HashiCorp Vault **managed credential** in Tenable (Tenable One).

Required env vars: `NESSUS_ACCESS_KEY`, `NESSUS_SECRET_KEY`,
`NESSUS_CREDENTIAL_UUID` (optional: `NESSUS_API_URL`, default
`https://cloud.tenable.com`).

Obtaining the UUID once — from the Tenable UI (Settings → Credentials → open the
HashiCorp Vault credential; UUID is in the URL `.../credentials/edit/<UUID>`), or
via the API:

```sh
curl -s "https://cloud.tenable.com/credentials" \
  -H "X-ApiKeys: accessKey=$NESSUS_ACCESS_KEY; secretKey=$NESSUS_SECRET_KEY" \
  | jq '.credentials[] | {uuid, name, type: .category_name}'
```

Example output:
```json
{
  "uuid": "e15e515e-e20e-4e52-94df-e6edb5ab317e",
  "name": "nessus",
  "type": null
}
```


# Trying out SSH / KV2 Secret Engine

scp -i ./keys/nessus.pem ./keys/nessus.pem ec2-user@ec2-13-214-201-96.ap-southeast-1.compute.amazonaws.com:/home/ec2-user/

# Update Tenable credential
Update Tenable Credentials to use certificate
```sh
AUTH="X-ApiKeys: accessKey=$NESSUS_ACCESS_KEY; secretKey=$NESSUS_SECRET_KEY"
UUID=e15e515e-e20e-4e52-94df-e6edb5ab317e

cert_ref=$(curl -s -H "$AUTH" -F "Filedata=@/home/ubuntu/public.pem" \
  "https://cloud.tenable.com/credentials/files?fileType=pem" | jq -r '.fileuploaded')
key_ref=$(curl -s -H "$AUTH" -F "Filedata=@/home/ubuntu/key.pem" \
  "https://cloud.tenable.com/credentials/files?fileType=pem" | jq -r '.fileuploaded')
echo "cert_ref=$cert_ref  key_ref=$key_ref"

curl -s -H "$AUTH" https://cloud.tenable.com/credentials/$UUID \
| jq --arg cr "$cert_ref" --arg kr "$key_ref" \
   '{settings: (.settings
      | with_entries(select(.value != null))
      + {
          hashicorp_authentication_type: "Certificates",
          hashicorp_client_cert: $cr,
          hashicorp_private_key: $kr,
          hashicorp_auth_url: "/v1/auth/cert/login"
        })}' \
| curl -sS -w '\nHTTP %{http_code}\n' -X PUT \
    -H "$AUTH" -H "Content-Type: application/json" --data @- \
    https://cloud.tenable.com/credentials/$UUID
```
Validate if certificates is updated
```sh
curl -s -H "$AUTH" https://cloud.tenable.com/credentials/$UUID \
| jq '.settings.hashicorp_authentication_type'  

curl -s \
  --header "X-ApiKeys: accessKey=${NESSUS_ACCESS_KEY}; secretKey=${NESSUS_SECRET_KEY}" \
  https://cloud.tenable.com/credentials/e15e515e-e20e-4e52-94df-e6edb5ab317e \
  | jq '.settings | {hashicorp_client_cert, hashicorp_private_key}'
```

{
  "hashicorp_client_cert": "public.pem_a204054b-b767-4f65-9e77-eafa4b0a771b",
  "hashicorp_private_key": "key.pem_d51fd612-6fab-43f4-9c8e-4abc9bdf2b97"
}
