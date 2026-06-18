-- ============================================================
-- TP Data Lake — Initialisation de la base PostgreSQL
-- ============================================================

-- Schéma n8n (créé séparément pour ne pas polluer le schéma public)
CREATE SCHEMA IF NOT EXISTS n8n;

-- ============================================================
-- Table principale : informations sur les Pokémon
-- (données issues de la PokéAPI ou saisie manuelle)
-- ============================================================
CREATE TABLE IF NOT EXISTS pokemons (
    pokemon_id   SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL UNIQUE,
    pokeapi_id   INTEGER UNIQUE,
    types        TEXT[],               -- ex : ARRAY['fire','flying']
    height       INTEGER,              -- en décimètres
    weight       INTEGER,              -- en hectogrammes
    sprite_url   TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Quelques Pokémon de référence pour les tests
INSERT INTO pokemons (name, pokeapi_id, types, height, weight, sprite_url) VALUES
    ('bulbasaur',  1,  ARRAY['grass','poison'], 7,  69,  'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/1.png'),
    ('charmander', 4,  ARRAY['fire'],           6,  85,  'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/4.png'),
    ('squirtle',   7,  ARRAY['water'],          5,  90,  'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/7.png'),
    ('pikachu',    25, ARRAY['electric'],       4,  60,  'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/25.png'),
    ('mewtwo',     150, ARRAY['psychic'],       20, 1220,'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/150.png')
ON CONFLICT (name) DO NOTHING;

-- ============================================================
-- Partie B — Table pokemon_files
-- Référence chaque fichier stocké dans MinIO et son Pokémon
-- ============================================================
CREATE TABLE IF NOT EXISTS pokemon_files (
    file_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pokemon_id   INTEGER REFERENCES pokemons(pokemon_id) ON DELETE SET NULL,
    bucket_name  VARCHAR(100) NOT NULL,        -- raw-pokemon | pokemon-images | reports
    object_key   TEXT NOT NULL,                -- chemin complet dans le bucket
    file_name    VARCHAR(255) NOT NULL,
    file_type    VARCHAR(50),                  -- json | png | csv | txt …
    mime_type    VARCHAR(100),                 -- application/json | image/png …
    file_size    BIGINT,                       -- taille en octets
    checksum     VARCHAR(64),                  -- SHA-256 si disponible
    internal_url TEXT GENERATED ALWAYS AS
                     ('http://localhost:9000/' || bucket_name || '/' || object_key) STORED,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- Partie B — Table file_ingestion_log
-- Trace toutes les tentatives d'ingestion (succès ou échec)
-- ============================================================
CREATE TABLE IF NOT EXISTS file_ingestion_log (
    log_id          SERIAL PRIMARY KEY,
    file_name       VARCHAR(255) NOT NULL,
    bucket_name     VARCHAR(100) NOT NULL,
    object_key      TEXT NOT NULL,
    source          VARCHAR(100) NOT NULL,      -- 'pokeapi' | 'n8n_workflow' | 'manual' …
    status          VARCHAR(20) NOT NULL        -- 'success' | 'error' | 'skipped'
                        CHECK (status IN ('success','error','skipped')),
    error_message   TEXT,                       -- renseigné si status = 'error'
    file_size       BIGINT,
    processed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    file_id         UUID REFERENCES pokemon_files(file_id) ON DELETE SET NULL
);

-- ============================================================
-- Index utiles
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_pokemon_files_pokemon  ON pokemon_files(pokemon_id);
CREATE INDEX IF NOT EXISTS idx_pokemon_files_bucket   ON pokemon_files(bucket_name);
CREATE INDEX IF NOT EXISTS idx_ingestion_log_status   ON file_ingestion_log(status);
CREATE INDEX IF NOT EXISTS idx_ingestion_log_source   ON file_ingestion_log(source);
CREATE INDEX IF NOT EXISTS idx_ingestion_log_date     ON file_ingestion_log(processed_at);

-- ============================================================
-- Vue pratique : dernier fichier par Pokémon
-- ============================================================
CREATE OR REPLACE VIEW v_latest_file_per_pokemon AS
SELECT DISTINCT ON (pf.pokemon_id)
    p.name          AS pokemon_name,
    pf.file_id,
    pf.bucket_name,
    pf.object_key,
    pf.file_type,
    pf.internal_url,
    pf.created_at
FROM pokemon_files pf
JOIN pokemons p ON p.pokemon_id = pf.pokemon_id
ORDER BY pf.pokemon_id, pf.created_at DESC;

-- ============================================================
-- Vue : statistiques d'ingestion par source et statut
-- ============================================================
CREATE OR REPLACE VIEW v_ingestion_stats AS
SELECT
    source,
    status,
    COUNT(*)                             AS nb_fichiers,
    SUM(file_size)                       AS total_octets,
    MIN(processed_at)                    AS premiere_ingestion,
    MAX(processed_at)                    AS derniere_ingestion
FROM file_ingestion_log
GROUP BY source, status
ORDER BY source, status;
