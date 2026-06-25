# Architecture

Prerequisites:
1. AWS Account
2. Nessus Tenable One license

## Create Private Link

1. Make sure you have all the prerequisites, then load env vars:

```sh
set -a && source .env && set +a
```

2. Create the PrivateLink service:
```sh
curl --location "https://api.cloud.hashicorp.com/network/2020-09-07/organizations/$HCP_ORG_ID/projects/$HCP_PROJ_ID/networks/$HCP_NETWORK_ID/private-link-services" \
 --request POST \
 --header 'Content-Type: application/json' \
 --header "Authorization: Bearer $HCP_API_TOKEN" \
 --data "{
     \"private_link_service\": {
         \"id\": \"privatelink-service\",
         \"vault_cluster_id\": \"vault-cluster\",
         \"consumer_accounts\": [\"$CONSUMER_ACCOUNT\"],
         \"consumer_ip_ranges\": [\"$CONSUMER_IP_RANGES\"],
         \"hvn\": {
             \"location\": {
                 \"region\": {
                     \"region\": \"$AWS_REGION\",
                     \"provider\": \"aws\"
                 }
             }
         }
     }
 }" | jq
```

3. Get the external service name (used when creating the AWS VPC endpoint):
```sh
export PRIVATELINKID="privatelink-service"

EXTERNAL_NAME=$(curl --location "https://api.cloud.hashicorp.com/network/2020-09-07/organizations/$HCP_ORG_ID/projects/$HCP_PROJ_ID/networks/$HCP_NETWORK_ID/private-link-services/$PRIVATELINKID" \
  --header "Authorization: Bearer $HCP_API_TOKEN" | jq -r '.private_link_service.external_name')

echo "$EXTERNAL_NAME"
```

4. Poll until the service `state` is `AVAILABLE`:
```sh
until [ "$(curl --location "https://api.cloud.hashicorp.com/network/2020-09-07/organizations/$HCP_ORG_ID/projects/$HCP_PROJ_ID/networks/$HCP_NETWORK_ID/private-link-services/$PRIVATELINKID" \
  --header "Authorization: Bearer $HCP_API_TOKEN" | jq -r '.private_link_service.state')" = "AVAILABLE" ]; do
  sleep 5
done
```

5. Create the consumer-side VPC endpoint in AWS, pointing at `$EXTERNAL_NAME`:
```sh
aws ec2 create-vpc-endpoint \
  --vpc-endpoint-type Interface \
  --vpc-id "$CONSUMER_VPC_ID" \
  --subnet-ids $CONSUMER_SUBNET_IDS \
  --service-name "$EXTERNAL_NAME"
```

