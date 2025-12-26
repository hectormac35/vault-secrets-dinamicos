#!/usr/bin/env sh
set -e

export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"

echo "[1/6] Habilitando database secrets engine (si no existe)..."
vault secrets enable database >/dev/null 2>&1 || true

echo "[2/6] Configurando conexión Postgres..."
vault write database/config/postgres-app \
  plugin_name=postgresql-database-plugin \
  allowed_roles="app-role" \
  connection_url="postgresql://{{username}}:{{password}}@vault-postgres:5432/appdb?sslmode=disable" \
  username="admin" \
  password="adminpassword" >/dev/null

echo "[3/6] Creando role dinámico DB..."
vault write database/roles/app-role \
  db_name=postgres-app \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}';
    GRANT CONNECT ON DATABASE appdb TO \"{{name}}\";
    GRANT USAGE ON SCHEMA public TO \"{{name}}\";
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";
  " \
  default_ttl="1m" \
  max_ttl="5m" >/dev/null

echo "[4/6] Subiendo policy app..."
cat > /tmp/app.hcl << 'POL'
path "database/creds/app-role" {
  capabilities = ["read"]
}
POL
vault policy write app /tmp/app.hcl >/dev/null

echo "[5/6] Habilitando AppRole (si no existe)..."
vault auth enable approle >/dev/null 2>&1 || true

echo "[6/6] Creando role demo-app y escribiendo role_id/secret_id..."
vault write auth/approle/role/demo-app \
  token_policies="app" \
  token_ttl="5m" \
  token_max_ttl="30m" >/dev/null

ROLE_ID=$(vault read -field=role_id auth/approle/role/demo-app/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/demo-app/secret-id)

echo "$ROLE_ID" > /secrets/role_id
echo "$SECRET_ID" > /secrets/secret_id

echo "OK: role_id y secret_id escritos en /secrets"
