#!/usr/bin/env bash
set -e

cd "/home/hector/Documentos/proyecto portafolio/vault-secrets-demo"

echo "[A] Levantando contenedores..."
docker compose up -d --build

echo "[B] Bootstrapping Vault..."
docker exec -i vault sh -c "sh /vault/bootstrap_vault.sh"

echo "[C] Reiniciando vault-agent..."
docker exec -it vault-agent sh -c "rm -f /secrets/token /secrets/secret.json" || true
docker compose restart agent

echo "[D] Creando tabla (si no existe)..."
docker exec -i vault-postgres psql -U admin -d appdb << SQL
CREATE TABLE IF NOT EXISTS eventos (
  id SERIAL PRIMARY KEY,
  mensaje TEXT NOT NULL,
  creado_en TIMESTAMP DEFAULT now()
);
SQL

echo "[E] OK. Prueba:"
echo "    curl http://localhost:8081/eventos"
