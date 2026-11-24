#!/usr/bin/env bash
# Demo de respuesta a un incidente: "se ha filtrado la credencial de la base de datos".
# 1) la app trabaja con un usuario temporal, 2) revocamos TODAS sus credenciales en Vault,
# 3) PostgreSQL borra el usuario al instante y 4) Vault Agent entrega uno nuevo sin reiniciar la app.
set -euo pipefail

API="${API:-http://localhost:8081}"
titulo() { printf '\n\033[1;33m── %s\033[0m\n' "$1"; }
usuario() { curl -fs "$API/estado" 2>/dev/null | sed -nE 's/.*"usuario_db":"([^"]+)".*/\1/p'; }
roles_vault() {
  docker exec vault-postgres psql -At -U admin -d appdb \
    -c "SELECT rolname || '  (caduca ' || to_char(rolvaliduntil AT TIME ZONE 'UTC','HH24:MI:SS') || ' UTC)' FROM pg_roles WHERE rolname LIKE 'v-%' ORDER BY rolname"
}

titulo "1. La app usa un usuario temporal de PostgreSQL"
curl -fs "$API/estado"; echo
ANTES="$(usuario)"

titulo "2. Escribe y lee datos con ese usuario"
curl -fs -X POST "$API/eventos" -H 'Content-Type: application/json' -d '{"mensaje":"antes de la revocación"}'; echo

titulo "3. Usuarios dinámicos que existen ahora en PostgreSQL"
roles_vault

titulo "4. Incidente: revocamos todas las credenciales emitidas para la app"
docker exec -e VAULT_TOKEN=root vault vault lease revoke -prefix database/creds/app-role

titulo "5. PostgreSQL ya no tiene ese usuario"
roles_vault | grep -q "$ANTES" && echo "¡$ANTES sigue existiendo!" || echo "$ANTES eliminado ✔"
printf 'Petición con la credencial revocada → HTTP %s\n' "$(curl -s -o /dev/null -w '%{http_code}' "$API/eventos")"

titulo "6. Esperando a que Vault Agent entregue una credencial nueva (sin reiniciar la app)"
INICIO=$(date +%s)
for _ in $(seq 1 60); do
  AHORA="$(usuario || true)"
  if [[ -n "$AHORA" && "$AHORA" != "$ANTES" ]] && curl -fs "$API/eventos" >/dev/null; then
    printf 'Nuevo usuario: %s  (tras %ss)\n' "$AHORA" "$(( $(date +%s) - INICIO ))"
    break
  fi
  sleep 3
done

titulo "7. La app sigue funcionando con el usuario nuevo"
curl -fs -X POST "$API/eventos" -H 'Content-Type: application/json' -d '{"mensaje":"después de la revocación"}'; echo
curl -fs "$API/eventos"; echo
