-- Se ejecuta solo la primera vez que se crea el volumen de datos.
-- La tabla tiene que existir ANTES de que Vault cree usuarios dinámicos,
-- porque cada usuario recibe permisos sobre las tablas que existen en ese momento.
CREATE TABLE IF NOT EXISTS eventos (
  id         SERIAL PRIMARY KEY,
  mensaje    TEXT NOT NULL,
  creado_en  TIMESTAMPTZ NOT NULL DEFAULT now()
);
