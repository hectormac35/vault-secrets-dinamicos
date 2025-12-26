import json
import psycopg
from fastapi import FastAPI, HTTPException

RUTA_SECRETO = "/secrets/secret.json"
DB_HOST = "vault-postgres"
DB_NAME = "appdb"
DB_PORT = 5432

app = FastAPI(title="Vault + Postgres (Credenciales Dinámicas - Conexión Real)")

def leer_secreto():
    try:
        with open(RUTA_SECRETO, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        raise HTTPException(status_code=503, detail="Secreto no disponible")

def get_conn():
    s = leer_secreto()
    try:
        return psycopg.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=s["username"],
            password=s["password"],
            connect_timeout=3,
        )
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Error conectando a DB: {e}")

@app.get("/estado")
def estado():
    s = leer_secreto()
    return {
        "ok": True,
        "usuario_db": s.get("username"),
        "ttl": s.get("ttl"),
    }

@app.get("/eventos")
def listar_eventos():
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, mensaje, creado_en FROM eventos ORDER BY id DESC LIMIT 10;")
            rows = cur.fetchall()
    return [
        {"id": r[0], "mensaje": r[1], "creado_en": r[2].isoformat()}
        for r in rows
    ]

@app.post("/eventos")
def crear_evento(mensaje: str):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO eventos (mensaje) VALUES (%s) RETURNING id;", (mensaje,))
            new_id = cur.fetchone()[0]
            conn.commit()
    return {"id": new_id, "mensaje": mensaje}
