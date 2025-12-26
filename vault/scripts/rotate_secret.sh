#!/usr/bin/env sh
set -e

export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"

VERSION="${1:-v$(date +%s)}"
API_KEY="KEY-${VERSION}"

vault kv put kv/app version="$VERSION" api_key="$API_KEY"

echo "[ROTACIÓN] Secreto actualizado a versión $VERSION"
