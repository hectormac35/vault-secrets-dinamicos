#!/usr/bin/env sh
# Configura Vault (modo dev) para emitir credenciales dinámicas de PostgreSQL.
# Lo lanza levantar.sh dentro del contenedor "vault". Es idempotente.
set -eu

export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="${VAULT_TOKEN:-root}"

: "${PG_ADMIN_PASSWORD:?Falta PG_ADMIN_PASSWORD (la genera levantar.sh)}"
DB_TTL="${DB_TTL:-1m}"
DB_MAX_TTL="${DB_MAX_TTL:-2m}"

echo "[1/6] Database secrets engine"
vault secrets enable database >/dev/null 2>&1 || true

echo "[2/6] Conexión con PostgreSQL"
vault write database/config/postgres-app \
  plugin_name=postgresql-database-plugin \
  allowed_roles="app-role" \
  connection_url="postgresql://{{username}}:{{password}}@vault-postgres:5432/appdb?sslmode=disable" \
  username="admin" \
  password="$PG_ADMIN_PASSWORD" >/dev/null

echo "[3/6] Rotando la contraseña del administrador (desde ahora solo la conoce Vault)"
vault write -f database/rotate-root/postgres-app >/dev/null

echo "[4/6] Rol dinámico app-role (TTL ${DB_TTL}, máximo ${DB_MAX_TTL})"
vault write database/roles/app-role \
  db_name=postgres-app \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
    GRANT CONNECT ON DATABASE appdb TO \"{{name}}\";
    GRANT USAGE ON SCHEMA public TO \"{{name}}\";
    GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";
  " \
  default_ttl="$DB_TTL" \
  max_ttl="$DB_MAX_TTL" >/dev/null

echo "[5/6] Política 'app' y AppRole demo-app"
vault policy write app /bootstrap/policies/app.hcl >/dev/null
vault auth enable approle >/dev/null 2>&1 || true
vault write auth/approle/role/demo-app \
  token_policies="app" \
  token_ttl="5m" \
  token_max_ttl="30m" \
  secret_id_ttl="24h" >/dev/null

echo "[6/6] Entregando role_id y secret_id SOLO al Vault Agent"
umask 077
vault read -field=role_id auth/approle/role/demo-app/role-id > /agent-auth/role_id
vault write -f -field=secret_id auth/approle/role/demo-app/secret-id > /agent-auth/secret_id

echo "OK: Vault listo"
