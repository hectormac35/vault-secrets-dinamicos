#!/usr/bin/env bash
# Prueba de extremo a extremo (la usa la CI): levanta todo y comprueba el flujo real.
set -euo pipefail
cd "$(dirname "$0")/.."
API=http://localhost:8081
falla() { echo "✘ $1" >&2; docker compose logs --tail 40 >&2; exit 1; }
usuario() { curl -fs "$API/estado" | sed -nE 's/.*"usuario_db":"([^"]+)".*/\1/p'; }

./levantar.sh

U1="$(usuario)"; [[ "$U1" == v-* ]] || falla "no hay usuario dinámico"
echo "✔ usuario dinámico: $U1"

curl -fs -X POST "$API/eventos" -H 'Content-Type: application/json' -d '{"mensaje":"e2e"}' | grep -q "\"escrito_por\":\"$U1\"" \
  || falla "no se pudo escribir con el usuario dinámico"
echo "✔ escritura con el usuario dinámico"

docker exec vault-postgres psql -At -U admin -d appdb -c "SELECT 1 FROM eventos" >/dev/null
# Se prueba desde otro contenedor (por la red): dentro del propio contenedor de
# PostgreSQL las conexiones locales son "trust" y aceptarían cualquier contraseña.
if docker exec demo-app python -c "import psycopg; psycopg.connect(host='vault-postgres', dbname='appdb', user='admin', password='solo-primer-arranque', connect_timeout=3)" >/dev/null 2>&1; then
  falla "la contraseña inicial del admin sigue funcionando"
fi
echo "✔ contraseña del admin rotada por Vault"

if docker exec demo-app sh -c 'ls /secrets' | grep -qvE '^secret\.json$'; then
  falla "la app ve ficheros que no son suyos"
fi
docker exec demo-app sh -c 'test ! -e /secrets/secret_id && test ! -e /secrets/token' || falla "la app puede leer el secret_id"
echo "✔ la app solo ve secret.json"

docker exec -e VAULT_TOKEN=root vault vault lease revoke -prefix database/creds/app-role >/dev/null
docker exec vault-postgres psql -At -U admin -d appdb -c "SELECT count(*) FROM pg_roles WHERE rolname = '$U1'" | grep -qx 0 \
  || falla "el usuario revocado sigue en PostgreSQL"
echo "✔ revocación: $U1 eliminado de PostgreSQL"

for _ in $(seq 1 40); do
  U2="$(usuario || true)"
  if [[ -n "$U2" && "$U2" != "$U1" ]] && curl -fs "$API/eventos" >/dev/null; then
    echo "✔ Vault Agent entregó un usuario nuevo: $U2"
    exit 0
  fi
  sleep 3
done
falla "el agente no renovó la credencial tras la revocación"
