# Política de la aplicación: lo único que puede hacer es pedir
# credenciales temporales de base de datos. Nada más (mínimo privilegio).
path "database/creds/app-role" {
  capabilities = ["read"]
}
