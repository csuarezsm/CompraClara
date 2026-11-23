-- Esquema de CompraClara (se aplica al arrancar; es idempotente).

CREATE TABLE IF NOT EXISTS users (
  id            BIGSERIAL PRIMARY KEY,
  email         TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS backups (
  user_id    BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  data       JSONB NOT NULL,
  size_bytes INTEGER NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Supermercados de la comunidad (identificados por nombre y ubicación).
CREATE TABLE IF NOT EXISTS stores (
  id         BIGSERIAL PRIMARY KEY,
  name       TEXT NOT NULL,
  name_norm  TEXT NOT NULL,
  lat        DOUBLE PRECISION NOT NULL,
  lng        DOUBLE PRECISION NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS stores_latlng ON stores (lat, lng);

-- Productos de la comunidad por código de barras.
CREATE TABLE IF NOT EXISTS products (
  ean        TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  brand      TEXT NOT NULL DEFAULT '',
  size       TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Aportaciones anónimas: sin user_id; solo una clave derivada (HMAC) para
-- contar personas distintas y aplicar límites, que no permite saber quién es.
CREATE TABLE IF NOT EXISTS contributions (
  id              BIGSERIAL PRIMARY KEY,
  ean             TEXT NOT NULL,
  store_id        BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  price           NUMERIC(10,2) NOT NULL CHECK (price > 0),
  is_offer        BOOLEAN NOT NULL DEFAULT FALSE,
  valid_until     DATE,
  observed_on     DATE NOT NULL,
  source          TEXT NOT NULL DEFAULT 'manual',
  contributor_key TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending', -- pending | validated | rejected
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (ean, store_id, observed_on, contributor_key)
);
CREATE INDEX IF NOT EXISTS contributions_lookup ON contributions (ean, store_id, observed_on DESC);

CREATE TABLE IF NOT EXISTS reports (
  id              BIGSERIAL PRIMARY KEY,
  contribution_id BIGINT NOT NULL REFERENCES contributions(id) ON DELETE CASCADE,
  contributor_key TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (contribution_id, contributor_key)
);

-- ---------------------------------------------------------------- v2: catálogo único
-- Cadenas (Mercadona, HiperDino…): se eligen de una lista, nunca se escriben.
CREATE TABLE IF NOT EXISTS chains (
  key  TEXT PRIMARY KEY,
  name TEXT NOT NULL
);

-- Cada supermercado se identifica por cadena + ubicación (y su id de OpenStreetMap si viene de allí).
ALTER TABLE stores ADD COLUMN IF NOT EXISTS chain_key   TEXT REFERENCES chains(key);
ALTER TABLE stores ADD COLUMN IF NOT EXISTS osm_id      TEXT;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS address     TEXT NOT NULL DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS city        TEXT NOT NULL DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS source      TEXT NOT NULL DEFAULT 'user'; -- osm | user
ALTER TABLE stores ADD COLUMN IF NOT EXISTS merged_into BIGINT REFERENCES stores(id);
ALTER TABLE stores ADD COLUMN IF NOT EXISTS updated_at  TIMESTAMPTZ NOT NULL DEFAULT now();
CREATE UNIQUE INDEX IF NOT EXISTS stores_osm ON stores (osm_id) WHERE osm_id IS NOT NULL;

-- Pares revisados que NO son el mismo súper (no se vuelven a proponer).
CREATE TABLE IF NOT EXISTS store_distinct (
  a BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  b BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  PRIMARY KEY (a, b)
);

-- Avisos de usuarios: «este súper es el mismo que aquel».
CREATE TABLE IF NOT EXISTS store_same_as (
  store_id        BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  other_id        BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  contributor_key TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, other_id, contributor_key)
);
