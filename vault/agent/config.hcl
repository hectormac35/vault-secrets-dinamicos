pid_file = "/tmp/vault-agent.pid"

vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/agent-auth/role_id"
      secret_id_file_path = "/agent-auth/secret_id"
      # El volumen /agent-auth solo lo montan Vault y el agente (nunca la app),
      # así que se conserva el secret_id para que el agente pueda reiniciarse.
      remove_secret_id_file_after_reading = false
    }
  }
  # Sin "sink": el token del agente no se escribe en disco y la app nunca lo ve.
}

template {
  source      = "/vault-agent/template.ctmpl"
  destination = "/app-secrets/secret.json"
  perms       = "0644"
}
