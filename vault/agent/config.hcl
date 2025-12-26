pid_file = "/tmp/vault-agent.pid"

vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/secrets/role_id"
      secret_id_file_path = "/secrets/secret_id"
    }
  }

  sink "file" {
    config = {
      path = "/secrets/token"
    }
  }
}

template {
  source      = "/vault-agent/template.ctmpl"
  destination = "/secrets/secret.json"
}
