#!/usr/bin/env sh
set -e

export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"

echo "[BOOTSTRAP] Habilitando KV v2"
vault secrets enable -path=kv kv-v2 >/dev/null 2>&1 || true

echo "[BOOTSTRAP] Creando secreto inicial"
vault kv put kv/app version="v1" api_key="KEY-INICIAL-1234"

echo "[BOOTSTRAP] Creando policy"
vault policy write app /vault/policies/app.hcl

echo "[BOOTSTRAP] Habilitando AppRole"
vault auth enable approle >/dev/null 2>&1 || true

echo "[BOOTSTRAP] Creando rol demo-app"
vault write auth/approle/role/demo-app token_policies="app"

ROLE_ID=$(vault read -field=role_id auth/approle/role/demo-app/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/demo-app/secret-id)

echo "$ROLE_ID" > /secrets/role_id
echo "$SECRET_ID" > /secrets/secret_id

echo "[BOOTSTRAP] Completado correctamente"
