# Vault Agent configuration: authenticate using TLS client certificates
# (public.pem + private.pem) via the cert auth method enabled in vault-tls.sh,
# then keep a freshly-issued cert on disk and run a script whenever it renews.

pid_file = "./pidfile"

vault {
  address   = "https://vault-cluster-private-vault-289b32ee.99820ad2.z1.hashicorp.cloud:8200"
  namespace = "admin"
}

auto_auth {
  method "cert" {
    mount_path = "auth/cert"

    config = {
      # Must match the cert role registered with:
      #   vault write auth/cert/certs/web ... certificate=@public.pem
      name        = "web"
      client_cert = "public.pem"
      client_key  = "key.pem"
    }
  }

  sink "file" {
    config = {
      path = "./vault-token"
    }
  }
}

# Re-issue the client cert from the PKI engine and write the new
# certificate + key to disk. The template re-renders before the cert
# expires (Vault Agent renews based on the lease/TTL), so this keeps
# public.pem / private.pem current ahead of the ttl=3600 expiry.
template {
  contents = <<-EOT
    {{- with secret "pki/issue/example-dot-com" "common_name=scanner1.example.com" "ttl=3600" -}}
    {{ .Data.certificate }}
    {{- end -}}
  EOT
  destination = "public.pem"
}

# Issuing CA, written separately for `nessuscli import-certs --cacert`.
template {
  contents = <<-EOT
    {{- with secret "pki/issue/example-dot-com" "common_name=scanner1.example.com" "ttl=3600" -}}
    {{ .Data.issuing_ca }}
    {{- end -}}
  EOT
  destination = "ca-cert.pem"
}

template {
  contents = <<-EOT
    {{- with secret "pki/issue/example-dot-com" "common_name=scanner1.example.com" "ttl=3600" -}}
    {{ .Data.private_key }}
    {{- end -}}
  EOT
  destination = "key.pem"

  # Run a script every time a fresh cert is rendered (i.e. before the
  # old one expires). Use this to restart/reload whatever consumes the
  # cert, e.g. re-establish the Vault login or reload the scanner.
  exec {
    command     = ["./renew-cert.sh"]
    timeout     = "120s"
  }
}
