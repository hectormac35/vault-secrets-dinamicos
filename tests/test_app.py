import json
from datetime import datetime, timezone

import psycopg
import pytest
from fastapi.testclient import TestClient

import main


class CursorFalso:
    def __init__(self, filas=None, uno=None):
        self.filas, self.uno, self.consultas = filas or [], uno, []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def execute(self, sql, params=None):
        self.consultas.append((sql, params))

    def fetchall(self):
        return self.filas

    def fetchone(self):
        return self.uno


class ConexionFalsa:
    def __init__(self, cursor):
        self._cursor, self.confirmada = cursor, False

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def cursor(self):
        return self._cursor

    def commit(self):
        self.confirmada = True


@pytest.fixture
def secreto(tmp_path, monkeypatch):
    ruta = tmp_path / "secret.json"

    def escribir(usuario="v-approle-app-role-AAA", password="p1", ttl=60):
        ruta.write_text(json.dumps({"username": usuario, "password": password, "ttl": ttl,
                                    "emitido_en": "2026-11-24T14:00:00Z"}))

    monkeypatch.setattr(main, "RUTA_SECRETO", ruta)
    return escribir


@pytest.fixture
def cliente():
    return TestClient(main.app)


def test_salud_no_necesita_secreto(cliente, monkeypatch, tmp_path):
    monkeypatch.setattr(main, "RUTA_SECRETO", tmp_path / "no-existe.json")
    assert cliente.get("/salud").json() == {"ok": True}


def test_estado_sin_secreto_devuelve_503(cliente, monkeypatch, tmp_path):
    monkeypatch.setattr(main, "RUTA_SECRETO", tmp_path / "no-existe.json")
    r = cliente.get("/estado")
    assert r.status_code == 503


def test_estado_con_secreto_incompleto_devuelve_503(cliente, secreto, monkeypatch):
    secreto(usuario="")
    assert cliente.get("/estado").status_code == 503


def test_estado_muestra_usuario_pero_nunca_la_contrasena(cliente, secreto):
    secreto(password="super-secreta")
    r = cliente.get("/estado")
    assert r.status_code == 200
    assert r.json()["usuario_db"] == "v-approle-app-role-AAA"
    assert "super-secreta" not in r.text


def test_cada_peticion_relee_el_secreto_rotado(cliente, secreto, monkeypatch):
    usados = []

    def conectar_falso(**kwargs):
        usados.append(kwargs["user"])
        return ConexionFalsa(CursorFalso(filas=[]))

    monkeypatch.setattr(main.psycopg, "connect", conectar_falso)
    secreto(usuario="v-usuario-1")
    cliente.get("/eventos")
    secreto(usuario="v-usuario-2")          # Vault Agent rota la credencial
    cliente.get("/eventos")
    assert usados == ["v-usuario-1", "v-usuario-2"]


def test_listar_eventos(cliente, secreto, monkeypatch):
    secreto()
    fecha = datetime(2026, 11, 24, 14, 0, tzinfo=timezone.utc)
    cursor = CursorFalso(filas=[(1, "Hola Vault", fecha, "v-approle-app-role-AAA")])
    monkeypatch.setattr(main.psycopg, "connect", lambda **_: ConexionFalsa(cursor))
    r = cliente.get("/eventos")
    assert r.status_code == 200
    assert r.json()[0]["leido_por"] == "v-approle-app-role-AAA"


def test_crear_evento_usa_consulta_parametrizada(cliente, secreto, monkeypatch):
    secreto()
    cursor = CursorFalso(uno=(7, "v-approle-app-role-AAA"))
    conexion = ConexionFalsa(cursor)
    monkeypatch.setattr(main.psycopg, "connect", lambda **_: conexion)
    texto = "'); DROP TABLE eventos; --"
    r = cliente.post("/eventos", json={"mensaje": texto})
    assert r.status_code == 201
    assert r.json() == {"id": 7, "mensaje": texto, "escrito_por": "v-approle-app-role-AAA"}
    sql, params = cursor.consultas[0]
    assert texto not in sql and params == (texto,)
    assert conexion.confirmada


@pytest.mark.parametrize("cuerpo", [{"mensaje": ""}, {"mensaje": "x" * 281}, {}])
def test_crear_evento_valida_el_mensaje(cliente, secreto, cuerpo):
    secreto()
    assert cliente.post("/eventos", json=cuerpo).status_code == 422


def test_error_de_conexion_no_filtra_detalles(cliente, secreto, monkeypatch):
    secreto()

    def falla(**_):
        raise psycopg.OperationalError('password authentication failed for user "v-approle-app-role-AAA"')

    monkeypatch.setattr(main.psycopg, "connect", falla)
    r = cliente.get("/eventos")
    assert r.status_code == 503
    assert "v-approle" not in r.text and "password" not in r.text


def test_credencial_revocada_durante_la_consulta_devuelve_503(cliente, secreto, monkeypatch):
    secreto()

    class CursorQueFalla(CursorFalso):
        def execute(self, sql, params=None):
            raise psycopg.errors.InsufficientPrivilege("permission denied")

    monkeypatch.setattr(main.psycopg, "connect", lambda **_: ConexionFalsa(CursorQueFalla()))
    assert cliente.get("/eventos").status_code == 503
