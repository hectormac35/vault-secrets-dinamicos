"""API de ejemplo que se conecta a PostgreSQL con credenciales dinámicas de Vault.

La aplicación no conoce ninguna contraseña: Vault Agent escribe en
/secrets/secret.json un usuario temporal y lo sustituye cuando caduca.
Por eso el secreto se vuelve a leer en cada petición.
"""

import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

import psycopg
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# Configuración que NO es secreta: puede venir de variables de entorno.
RUTA_SECRETO = Path(os.getenv("SECRETS_FILE", "/secrets/secret.json"))
DB_HOST = os.getenv("DB_HOST", "vault-postgres")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "appdb")

log = logging.getLogger("demo-app")

app = FastAPI(
    title="Vault · credenciales dinámicas",
    description="La API usa usuarios de PostgreSQL temporales emitidos por Vault.",
    version="2.0.0",
)


class NuevoEvento(BaseModel):
    mensaje: str = Field(min_length=1, max_length=280)


def leer_secreto() -> dict:
    """Lee las credenciales actuales. 503 si el agente aún no las ha escrito."""
    try:
        datos = json.loads(RUTA_SECRETO.read_text(encoding="utf-8"))
        if not datos.get("username") or not datos.get("password"):
            raise ValueError("faltan campos")
        return datos
    except (OSError, ValueError) as exc:
        log.warning("Secreto no disponible: %s", exc)
        raise HTTPException(status_code=503, detail="Credenciales no disponibles todavía") from exc


def conectar() -> psycopg.Connection:
    secreto = leer_secreto()
    try:
        return psycopg.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=secreto["username"],
            password=secreto["password"],
            connect_timeout=3,
        )
    except psycopg.Error as exc:
        # El detalle va al log, nunca al cliente (podría revelar usuarios o hosts).
        log.warning("No se pudo conectar a PostgreSQL: %s", exc)
        raise HTTPException(status_code=503, detail="Base de datos no disponible") from exc


@app.get("/salud")
def salud():
    """Comprobación básica de que el proceso responde (no toca secretos)."""
    return {"ok": True}


@app.get("/estado")
def estado():
    """Muestra QUÉ usuario temporal se está usando, nunca la contraseña."""
    secreto = leer_secreto()
    actualizado = datetime.fromtimestamp(RUTA_SECRETO.stat().st_mtime, tz=timezone.utc)
    return {
        "ok": True,
        "usuario_db": secreto["username"],
        "ttl_segundos": secreto.get("ttl"),
        "emitido_en": secreto.get("emitido_en"),
        "fichero_actualizado": actualizado.isoformat(timespec="seconds"),
    }


@app.get("/eventos")
def listar_eventos():
    try:
        with conectar() as conn, conn.cursor() as cur:
            cur.execute(
                "SELECT id, mensaje, creado_en, current_user FROM eventos ORDER BY id DESC LIMIT 10"
            )
            filas = cur.fetchall()
    except psycopg.Error as exc:
        log.warning("Error en la consulta: %s", exc)
        raise HTTPException(status_code=503, detail="Base de datos no disponible") from exc
    return [
        {"id": f[0], "mensaje": f[1], "creado_en": f[2].isoformat(), "leido_por": f[3]}
        for f in filas
    ]


@app.post("/eventos", status_code=201)
def crear_evento(evento: NuevoEvento):
    try:
        with conectar() as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO eventos (mensaje) VALUES (%s) RETURNING id, current_user",
                (evento.mensaje,),
            )
            nuevo_id, usuario = cur.fetchone()
            conn.commit()
    except psycopg.Error as exc:
        log.warning("Error al insertar: %s", exc)
        raise HTTPException(status_code=503, detail="Base de datos no disponible") from exc
    return {"id": nuevo_id, "mensaje": evento.mensaje, "escrito_por": usuario}
