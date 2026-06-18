# TP Data Lake — Guide de mise en œuvre

## Architecture retenue

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker network: datalake_net             │
│                                                             │
│  ┌──────────────┐   ┌──────────────────────────────────┐   │
│  │  PostgreSQL  │   │             MinIO                │   │
│  │  :5432       │   │  :9000 (API S3) :9001 (Console)  │   │
│  │              │   │                                  │   │
│  │  pokemons    │   │  Bucket: raw-pokemon             │   │
│  │  pokemon_    │   │  Bucket: pokemon-images          │   │
│  │   files      │   │  Bucket: reports                 │   │
│  │  file_       │   │                                  │   │
│  │   ingestion_ │   └──────────────────────────────────┘   │
│  │   log        │                                          │
│  └──────────────┘   ┌──────────────────────────────────┐   │
│                     │            n8n                   │   │
│                     │  :5678                           │   │
│                     │  Workflow d'ingestion PokéAPI    │   │
│                     └──────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Partie A — Démarrage de l'environnement

```bash
# Lancer tous les services
docker compose up -d

# Vérifier que tout est démarré
docker compose ps

# Logs MinIO
docker compose logs minio

# Logs PostgreSQL
docker compose logs postgres
```

### Accès aux interfaces

| Service    | URL                        | Identifiants              |
|------------|----------------------------|---------------------------|
| MinIO UI   | http://localhost:9001      | minioadmin / minioadmin123 |
| n8n        | http://localhost:5678      | admin / admin123          |
| PostgreSQL | localhost:5432             | pokemon_user / pokemon_pass / pokemon_db |

---

## Partie A — Organisation des buckets MinIO

Le service `minio-init` crée automatiquement 3 buckets au démarrage :

| Bucket           | Contenu                                              |
|------------------|------------------------------------------------------|
| `raw-pokemon`    | Réponses JSON brutes de la PokéAPI (non transformées) |
| `pokemon-images` | Sprites et images officielles des Pokémon (PNG)      |
| `reports`        | Rapports CSV/JSON générés (analyses, anomalies…)     |

**Justification du choix de 3 buckets distincts** : séparer les zones par nature de données (brut / médias / rapports) facilite la gestion des droits d'accès (les images sont en lecture publique, le brut reste privé) et reflète les couches Bronze/Silver/Gold d'une architecture Lakehouse.

---

## Partie B — Schéma SQL

Fichier : [sql/init.sql](sql/init.sql)

### Table `pokemon_files`

| Colonne        | Type           | Description                              |
|----------------|----------------|------------------------------------------|
| `file_id`      | UUID (PK)      | Identifiant unique généré automatiquement |
| `pokemon_id`   | INTEGER (FK)   | Référence vers `pokemons`                |
| `bucket_name`  | VARCHAR(100)   | Nom du bucket MinIO                      |
| `object_key`   | TEXT           | Chemin complet de l'objet dans le bucket |
| `file_name`    | VARCHAR(255)   | Nom du fichier                           |
| `file_type`    | VARCHAR(50)    | Extension : json, png, csv…              |
| `mime_type`    | VARCHAR(100)   | Type MIME complet                        |
| `file_size`    | BIGINT         | Taille en octets                         |
| `checksum`     | VARCHAR(64)    | SHA-256 optionnel                        |
| `internal_url` | TEXT (généré)  | URL MinIO calculée automatiquement       |
| `created_at`   | TIMESTAMPTZ    | Date d'insertion                         |

### Table `file_ingestion_log`

| Colonne         | Type          | Description                              |
|-----------------|---------------|------------------------------------------|
| `log_id`        | SERIAL (PK)   | Identifiant auto-incrémenté              |
| `file_name`     | VARCHAR(255)  | Nom du fichier traité                    |
| `bucket_name`   | VARCHAR(100)  | Bucket cible                             |
| `object_key`    | TEXT          | Chemin dans le bucket                    |
| `source`        | VARCHAR(100)  | Origine : pokeapi, n8n, manual…          |
| `status`        | VARCHAR(20)   | success \| error \| skipped             |
| `error_message` | TEXT          | Message d'erreur si applicable           |
| `file_size`     | BIGINT        | Taille du fichier                        |
| `processed_at`  | TIMESTAMPTZ   | Horodatage du traitement                 |
| `file_id`       | UUID (FK)     | Lien vers `pokemon_files` si succès      |

---

## Partie C — Workflow n8n

Fichier à importer : [workflows/pokemon_datalake_workflow.json](workflows/pokemon_datalake_workflow.json)

### Étapes du workflow

```
[Scheduler 1h] → [Code: ID aléatoire 1-151]
              → [HTTP: GET pokeapi.co/api/v2/pokemon/{id}]
              → [Code: construire JSON enrichi]
              → [Code: encoder en base64]
              → [HTTP PUT: MinIO raw-pokemon/{name}_{id}.json]
              → [Postgres: UPSERT pokemons]
              → [Postgres: INSERT pokemon_files + file_ingestion_log]
```

### Import du workflow

1. Ouvrir n8n sur http://localhost:5678
2. Menu **Workflows** → **Import from file**
3. Sélectionner `workflows/pokemon_datalake_workflow.json`
4. Configurer la credential PostgreSQL (host: `postgres`, user: `pokemon_user`, pass: `pokemon_pass`, db: `pokemon_db`)
5. Activer le workflow

---

## Vérification rapide

```bash
# Lister les objets dans MinIO
docker compose exec minio mc ls local/raw-pokemon

# Vérifier les métadonnées en base
docker compose exec postgres psql -U pokemon_user -d pokemon_db \
  -c "SELECT file_name, bucket_name, file_type, file_size, created_at FROM pokemon_files LIMIT 10;"

# Voir le log d'ingestion
docker compose exec postgres psql -U pokemon_user -d pokemon_db \
  -c "SELECT file_name, source, status, processed_at FROM file_ingestion_log ORDER BY processed_at DESC LIMIT 10;"
```

---

## Partie D — Réponse rédigée

Voir [partie_D_reponse.md](partie_D_reponse.md)
