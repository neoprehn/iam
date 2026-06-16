# Datenmodell

Festgelegtes Schema (Labels, Relationship-Typen, Property-Keys). Reproduzierbar hergestellt
über `neo4j-migrations` (AE-02), siehe [Phase 1](phasen/phase-1.md).

## Zwei getrennte Zeitachsen

Das Modell trennt bewusst zwei Dinge, die beide „Zeit" sind, aber Unterschiedliches meinen:

| Achse | Bedeutung | Ort im Modell |
| --- | --- | --- |
| **Gültigkeit** | Wann gilt eine Zuordnung *innerhalb* eines Extrakts (Stichtag) | `validFrom`/`validTo` als `date` auf der Kante (AE-07/AE-08) |
| **Extrakt-/Version** | Welcher Export-Stand: z. B. `2025-12-31` vs. `2026-12-31` | `dataset`-Property an jedem Knoten/jeder Kante |

## Die `dataset`-Dimension (Versionierung & Vergleich)

Ein **`dataset`** ist ein vollständiger, in sich geschlossener SAP-Extrakt (ein Mandant zu
einem Stand), z. B. `acme-2026-12-31`. Jeder Knoten und jede Kante trägt die Property
`dataset`. Damit liegen mehrere Stände parallel in **einer** DB und sind vergleichbar
(Diff-Query über die fachliche `id`); ein Stand lässt sich isoliert per
`DETACH DELETE … WHERE n.dataset = $x` entfernen.

**Abgrenzung zu mehreren Mandanten:** Verschiedene *Mandanten* werden **nicht** über
`dataset` gemischt, sondern in **getrennten Neo4j-Instanzen** gehalten (Vertraulichkeit;
zudem kann Neo4j Community nur eine Nutzdatenbank). `dataset` dient dem Vergleich von
Ständen *desselben* Mandanten. Cross-Mandanten-Benchmarks nur auf anonymisierten Daten.

### Community-Eigenheit: synthetischer Key

Neo4j Community kennt nur **Single-Property-Unique-Constraints** — zusammengesetzte Keys
(`(dataset, id)`) als Constraint sind Enterprise. Lösung: ein synthetischer Schlüssel

```
key = "<dataset>|<id>"
```

mit Single-Property-Unique-Constraint. Darauf wird beim Import ge-`MERGE`-t. Zusätzlich ein
**Composite-Index** auf `(dataset, id)` (Composite-*Indizes* sind in Community erlaubt) für
schnelle, dataset-gefilterte Lookups und den Versionsvergleich.

## Knoten (Labels)

| Label | Fachliche `id` | Quelle | Subtyp-Labels (Schichtung) |
| --- | --- | --- | --- |
| `Dataset` | Extrakt-Name (global eindeutig) | — (Registry/Provenienz) | — |
| `User` | `BNAME` | USR02 | `User:Dialog\|System\|Communication`, `User:Active\|Locked` |
| `Role` | `AGR_NAME` | AGR_DEFINE | `Role:Composite\|Single\|Derived` |
| `Profile` | `PROFN` | USR10/UST10 | `Profile:Single\|Collective\|Critical` |
| `Authorization` | — (kein fachl. Key, AE-03) | AGR_1251 | — |
| `AuthObject` | `OBJECT` (z. B. `S_TCODE`) | TOBJ | `AuthObject:Critical` |
| `Transaction` | `TCODE` | TSTC | `Transaction:Critical` |

Primärlabel + Subtyp + Regelwerks-Markierung (`:Critical`). Org-Werte bleiben **Properties**,
keine eigenen Labels/Knoten (AE-05). `*`/unbeschränkt wird „genommen wie es kommt" und erst in
der Abfragelogik normalisiert (AE-06).

### Authorization: Knoten, nicht Kante (AE-03)

Eine Berechtigung gruppiert UND-verknüpfte Feldwerte (z. B. `ACTVT=01` UND `BUKRS=1000`).
Diese Gruppierung darf nicht in Einzelkanten zerfallen — daher ein eigener `Authorization`-
Knoten, dessen Feldwerte als **Properties** anliegen. Identität entsteht über die Kanten
(`HAS_AUTH`, `FOR_OBJECT`), nicht über einen fachlichen Schlüssel.

## Kanten (Relationship-Typen)

| Typ | Von → Nach | Quelle | Properties |
| --- | --- | --- | --- |
| `ASSIGNED_TO` | `User` → `Role` | AGR_USERS | `validFrom`, `validTo` (`date`, AE-07) |
| `CONTAINS` | `Role`(Composite) → `Role`(Single) | AGR_AGRS | — |
| `DERIVED_FROM` | `Role`(Derived) → `Role`(Master) | AGR_DEFINE | — |
| `HAS_PROFILE` | `User`/`Role` → `Profile` | UST04 / AGR_1016B | ggf. `validFrom`/`validTo` |
| `HAS_AUTH` | `Role`/`Profile` → `Authorization` | AGR_1251 | — |
| `FOR_OBJECT` | `Authorization` → `AuthObject` | AGR_1251 | — |
| `CHECKS` | `Transaction` → `AuthObject` | USOBT_C/USOBX_C (SU24) | — |
| `CONTAINS` | `Profile`(Collective) → `Profile`(Single) | UST10C | — |
| `HAS_REFERENCE` | `User` → `User` (Referenzbenutzer) | USREFUS | — |
| `HAS_MENU` | `Role` → `Transaction` (Rollenmenü, informativ) | AGR_TCODES | — |

**Invariante:** Kanten verlaufen immer *innerhalb* eines `dataset` (beide Endpunkte teilen
denselben `dataset`-Wert). Ein Extrakt ist self-contained.

## Diagramm

```{mermaid}
graph LR
  User(("User"))
  Role(("Role"))
  Profile(("Profile"))
  Auth(("Authorization"))
  AuthObject(("AuthObject"))
  Transaction(("Transaction"))

  User -- "ASSIGNED_TO (validFrom/validTo)" --> Role
  Role -- "CONTAINS" --> Role
  Role -- "DERIVED_FROM" --> Role
  User -- "HAS_PROFILE" --> Profile
  Role -- "HAS_PROFILE" --> Profile
  Role -- "HAS_AUTH" --> Auth
  Profile -- "HAS_AUTH" --> Auth
  Auth -- "FOR_OBJECT" --> AuthObject
  Transaction -- "CHECKS" --> AuthObject
```

*Jeder Knoten trägt zusätzlich `dataset` (+ synthetischen `key`); der `Dataset`-Registry-Knoten
steht ohne Kanten daneben. Can-Do verläuft `User → Role/Profile → Authorization → AuthObject`;
`Transaction → AuthObject` (SU24) ist der Anknüpfungspunkt für Did-Do (AE-12).*

## Gültigkeit über den Pfad (AE-08)

Auswertungen sind stichtagsbezogen (parametrisiert). Bei verschachtelten Sammelrollen muss
das Datumsprädikat auf **jede** relevante Kante des Pfades wirken
(`all(rel IN relationships(p) WHERE …)`), sonst entstehen falsch-positive/-negative Treffer.
`TO_DAT = '99991231'` (unbegrenzt) wird beim Import auf ein fernes Datum bzw. eine
`null`-Konvention gemappt.

## Schema in Migrationen

- `migrations/V001__constraints.cypher` — Unique-Constraints auf `Dataset.id` und den
  synthetischen `key` von `User`, `Role`, `Profile`, `AuthObject`, `Transaction`.
- `migrations/V002__indexes.cypher` — Composite-Lookup-Indizes `(dataset, id)`, ein
  `dataset`-Index für `Authorization` sowie der Range-Index `ASSIGNED_TO(validFrom, validTo)`.

Erweiterungen nach Bedarf: `AuthField`, `ObjectClass`, `OrgValue` (nur falls Pivot nötig),
`Service`/`FioriTile` (S/4) — als weitere Migrationen. `V003__authorization_key.cypher` ergänzt
das Unique-Constraint auf `Authorization.key` (Performance, siehe [Phase 2](phasen/phase-2.md)).

## Auswerte-Schicht (Phase 3)

Über der Can-Do-Schicht liegen drei klar getrennte Bereiche (Details: [Phase 3](phasen/phase-3.md)):

**Ruleset — konstant, ohne `dataset`** (Referenzdaten, je `ruleset`):
- `(:Query)` (Funktionsbaustein) `-[:REQUIRES]->(:AuthReq)` (Objekt/Feld/Werte/`andLogic`).
- `(:SoDRule) -[:USES {var}]-> (:Query)` und die CNF-Klauseln
  `(:SoDRule)-[:HAS_CLAUSE]->(:Clause)-[:NEEDS]->(:Query)`.
- `(:Risk)` (CSI-nativ), je Regel verknüpft.

**Org-Feld-Registry — je `dataset`:** `(:OrgField)` aus USORG (welche Felder org-relevant sind).

**Run-/Snapshot-Schicht — regenerierbar, mit Provenienz** (AE-10):
- Zwischenergebnis „wer kann was": `(:User)-[:MATCHES {ruleset, asOf, runId}]->(:Query)`.
- Findings: `(:User)-[:VIOLATES]->(:SoDConflict {ruleId, ruleset, dataset, asOf, runId,
  criticality, userSleeping})-[:BASED_ON]->(:SoDRule)`. Risiko/Kritikalität stammt aus der
  Regel und wird nur angehängt.

Schlüssel analog zur Can-Do-Schicht über synthetische `key` (`ruleset|id`); die Constraints
(`query_key`, `sodrule_key`, `clause_key`, `sodconflict_key`) legt der Ruleset-Loader bzw. der
Evaluator idempotent an.
