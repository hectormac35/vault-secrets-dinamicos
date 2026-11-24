#!/usr/bin/env bash
# Para la demo. Con --borrar elimina también los volúmenes (base de datos incluida).
set -euo pipefail
cd "$(dirname "$0")"
if [[ "${1:-}" == "--borrar" ]]; then
  docker compose down -v
else
  docker compose down
fi
