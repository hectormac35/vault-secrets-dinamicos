#!/usr/bin/env bash
# Levanta la demo completa: PostgreSQL + Vault + Vault Agent + API.
# Se puede ejecutar varias veces: cada vez reconfigura Vault desde cero.
set -euo pipefail
cd "$(dirname "$0")"

paso() { printf '\n\033[1;33m▶ %s\033[0m\n' "$1"; }

paso "1/5  Arrancando PostgreSQL y Vault"
docker compose up -d --build --wait postgres vault

paso "2/5  Comprobando el esquema de la base de datos"
docker exec -i -e PGOPTIONS="--client-min-messages=warning" vault-postgres \
  psql -q -v ON_ERROR_STOP=1 -U admin -d appdb < postgres/init/01-esquema.sql

paso "3/5  Configurando Vault (credenciales dinámicas + AppRole)"
# Contraseña de un solo uso para que Vault pueda conectarse; acto seguido Vault la rota.
PG_ADMIN_PASSWORD="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
docker exec -i vault-postgres psql -q -v ON_ERROR_STOP=1 -U admin -d appdb \
  -c "ALTER ROLE admin PASSWORD '${PG_ADMIN_PASSWORD}';"
docker exec -e PG_ADMIN_PASSWORD="$PG_ADMIN_PASSWORD" vault sh /bootstrap/bootstrap_vault.sh
unset PG_ADMIN_PASSWORD

paso "4/5  Arrancando Vault Agent y la API"
docker compose up -d --build --force-recreate agent app

paso "5/5  Esperando a que la API reciba sus primeras credenciales"
for _ in $(seq 1 30); do
  if curl -fs http://localhost:8081/estado >/dev/null 2>&1; then
    curl -s http://localhost:8081/estado; echo
    printf '\n\033[1;32m✔ Todo listo.\033[0m  Prueba:  curl http://localhost:8081/eventos\n'
    printf '   Demo de rotación y revocación:  ./scripts/demo.sh\n'
    printf '   UI de Vault: http://localhost:8200  (token: root)\n'
    exit 0
  fi
  sleep 2
done

echo "La API no ha recibido credenciales. Logs del agente:" >&2
docker logs --tail 30 vault-agent >&2
exit 1
