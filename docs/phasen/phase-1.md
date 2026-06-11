# Phase 1 — Datenmodell

**Ziel:** Festgelegtes Schema (Labels, Relationship-Typen, Property-Keys) als versionierte
Migrationen. **DoD:** `neo4j-migrations` stellt das vollständige Schema reproduzierbar her.

Das fachliche Modell (Labels, Kanten, Properties, `dataset`-Dimension) ist in
[Datenmodell](../datamodel.md) beschrieben. Diese Seite dokumentiert das **Tooling** und den
**Ablauf**.

## Migrations-Tooling (AE-02)

Schema-Änderungen laufen über [neo4j-migrations](https://github.com/michael-simons/neo4j-migrations)
(Flyway-artig: versionierte Dateien `V001__…`, idempotent, in der DB als erledigt vermerkt).

Da es kein gepflegtes offizielles Container-Image gibt, wird ein **gepinntes** Image selbst
gebaut (AE-14/AE-15): Eclipse Temurin 21 (JRE) + neo4j-migrations 4.1.0 (JVM-Distribution),
siehe `docker/neo4j-migrations.Dockerfile`. Es läuft als Compose-Service `migrations` mit
`profiles: ["tools"]`, startet also **nicht** bei `docker compose up`.

```yaml
  migrations:
    build:
      context: ./docker
      dockerfile: neo4j-migrations.Dockerfile
    image: iam-neo4j-migrations:4.1.0
    profiles: ["tools"]
    depends_on:
      neo4j:
        condition: service_healthy
    environment:
      NEO4J_PASSWORD: ${NEO4J_PASSWORD}
    volumes:
      - ./migrations:/migrations
```

Ein Entrypoint-Skript setzt die Verbindungs-Flags aus der Umgebung
(`--address=bolt://neo4j:7687`, `--username`, `--password`, `--location=file:/migrations`),
sodass nur das Subkommando übergeben wird. Das Passwort kommt aus `.env`, steht nie im Image.

## Migrationsdateien

```text
migrations/
├─ V001__constraints.cypher   # Unique-Constraints (Community: single-property)
└─ V002__indexes.cypher       # Composite-Lookups + ASSIGNED_TO-Validity (Range)
```

Zur Schlüsselstrategie (`dataset`, synthetischer `key`, Community-Limitierung) siehe
[Datenmodell](../datamodel.md#community-eigenheit-synthetischer-key).

## Anwenden & Prüfen

```powershell
# Image einmalig bauen
docker compose build migrations

# Status der Migrationen
docker compose run --rm migrations info

# Schema anwenden
docker compose run --rm migrations

# (Verifikation direkt in der DB)
docker exec -i iam-neo4j cypher-shell -u neo4j -p "$env:NEO4J_PASSWORD" "SHOW CONSTRAINTS;"
docker exec -i iam-neo4j cypher-shell -u neo4j -p "$env:NEO4J_PASSWORD" "SHOW INDEXES;"
```

:::{note}
`migrate` ist idempotent: neo4j-migrations vermerkt angewandte Versionen in der DB
(`__Neo4jMigration`-Knoten) und überspringt sie beim nächsten Lauf. Ein zweiter Aufruf meldet
„nothing to migrate".
:::

### Ergebnis beim Aufbau dieser Phase

`migrate` meldete *„Database migrated to version 002."*. `SHOW CONSTRAINTS`/`SHOW INDEXES`
bestätigen:

- Unique-Constraints: `dataset_id`, `user_key`, `role_key`, `profile_key`, `authobject_key`,
  `transaction_key`.
- Composite-Lookup-Indizes `(dataset, id)` für User/Role/Profile/AuthObject/Transaction,
  `dataset`-Index für Authorization.
- Relationship-Range-Index `assigned_to_validity` auf `ASSIGNED_TO(validFrom, validTo)`.

Damit ist die DoD von Phase 1 erfüllt — das Schema ist aus dem Repo reproduzierbar.

## Neue Migration hinzufügen

Nächste Datei nach Schema `V003__<beschreibung>.cypher` in `migrations/` ablegen
(LF-Zeilenenden, von `.gitattributes` erzwungen), dann `docker compose run --rm migrations`.
Bereits angewandte Migrationen **nicht** nachträglich ändern (Checksum-Prüfung) — stattdessen
eine neue Version anlegen.
