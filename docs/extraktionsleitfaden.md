# Extraktionsleitfaden (Can-Do / Rohdaten)

Welche SAP-Tabellen, welche **Spalten** und in welchem Format extrahiert werden. Leitlinie:
**Datensparsamkeit** — nur was die Auswertung braucht. Insbesondere werden **keine
Passwort-Hashes** und keine personenbezogenen Klartextdaten extrahiert, die für die Can-Do-
Analyse nicht nötig sind.

:::{admonition} Bitte gegen euer System prüfen
:class: warning
Einige Spalten-/Semantik-Details sind release- und systemabhängig. Mit ⚠️ markierte Punkte
vor dem Produktivlauf einmal gegen das konkrete SAP-System verifizieren (SE11/SE16).
:::

## Format-Konventionen

- **Trennzeichen: Tab** (`\t`), UTF-8, mit Kopfzeile. Der Konverter erzeugt das automatisch aus dem
  SE16-„unkonvertiert"-Export; bei direktem CSV-Export Tab als Trenner wählen (die Load-Skripte lesen
  `FIELDTERMINATOR '\t'`).
- **Spaltenüberschriften = SAP-Feldnamen** (z. B. `BNAME`, `AGR_NAME`). So sind die
  Load-Skripte unabhängig von der Extraktionsmethode (SE16-Export, Tabellen-Download, Report).
- Dateien liegen lokal in `data/import/` und werden in Cypher als `file:///<name>.csv`
  referenziert — **keine** Windows-Absolutpfade (Linux-Container, AE-15).
- **`dataset`**: kein CSV-Feld, sondern ein **Cypher-Parameter** je Lauf (z. B.
  `acme-2026-12-31`). Der Runner setzt ihn; alle Knoten/Kanten erhalten ihn (Versionsdimension).
- **Datumsfelder** (SAP `YYYYMMDD`): Umwandlung in Neo4j-`date` beim Import (AE-07).
  `TO_DAT = '99991231'` (unbegrenzt) → `9999-12-31`; leeres/`00000000` → `1900-01-01`.
- **`*`/unbeschränkt**: wird gespeichert „wie geliefert" (kein Vorab-Mapping); Normalisierung
  erst in der Abfragelogik (AE-06).

## Welche Tabellen herunterladen?

Die SE16-Exporte (eine `.txt`/`.csv` je Tabelle, Dateiname = Tabellenname) gehören in den
Dataset-Ordner. Der Konverter prüft das **Minimalset vor dem Import** (Quelle:
`config/required_tables.json`) — **fehlt eine Pflicht-Tabelle, bricht er ab.** Optionale Tabellen
reichern nur an (es erscheint lediglich ein Hinweis, wenn sie fehlen).

### Pflicht (Minimalset)

| Tabelle | Zweck |
| --- | --- |
| **USR02** | Benutzer-Stammsatz (Typ, Sperre, letzter Logon, Gültigkeit) |
| **AGR_DEFINE** | Rollen-Definition (Sammelrolle über `PARENT_AGR`) |
| **AGR_AGRS** | Sammelrolle → Einzelrollen |
| **AGR_USERS** | Benutzer ↔ Rolle (mit Gültigkeit) |
| **ARG_PROF** | Rolle → generiertes Profil. *SAP-Tabelle ist `AGR_PROF`; in diesem Pipeline-Stand wird die Datei als `ARG_PROF` erwartet (historischer Exportname).* |
| **UST04** | Benutzer → direkt zugewiesenes Profil (z. B. `SAP_ALL`) |
| **AGR_1251** | Rollen-Berechtigungsdaten (Objekt/Feld/Werte je Rolle) |
| **TSTCT** | Transaktionstexte |
| **USOBT_C** | SU24-Vorschlagswerte (TCode → Objekt/Feld; Quelle für `CHECKS`) |
| **UST10S** | Profil-Berechtigungen (Profilinhalte) |
| **UST12** | Berechtigungs-Feldwerte zu den Profilberechtigungen |

### Optional (Anreicherung)

| Tabelle | Ergänzt |
| --- | --- |
| **USR11** | Profiltexte |
| **USR13** | Berechtigungstexte |
| **TOBJT** | Berechtigungsobjekt-Texte |
| **AGR_TEXTS** | Rollentexte (sprachabhängig, `$lang`-Schalter) |
| **V_USERNAME** | Benutzernamen (Vor-/Nachname) |
| **USREFUS** | Referenzbenutzer |
| **UST10C** | Sammelprofile (Profil → enthaltene Profile) |
| **AGR_1252** | Org-Ebenen abgeleiteter Rollen |
| **AGR_TCODES** | Rollenmenü (TCodes der Rolle) |
| **AGR_1016B** | Profil-Generierungsstatus der Rollen |

> Zusätzlich nutzt Loader `23` die Tabelle **USORG** (Registry der org-relevanten
> Berechtigungsfelder, Grundlage der Org-Dimension). Sie ist **nicht** Teil der Minimalset-Prüfung —
> ohne sie entfällt die Org-Feld-Erkennung. Bei Bedarf mit exportieren.

Die genaue Ladereihenfolge ergibt sich aus den Dateinamen unter `load/` (`00…99`); die
benötigten **Spalten je Tabelle** stehen unten.

## Spalten je Tabelle

### 01 — USR02 (Benutzer) → `:User`
| Spalte | Verwendung |
| --- | --- |
| `BNAME` | User-ID (fachliche `id`) |
| `USTYP` | Benutzertyp → Subtyp-Label (`A`=Dialog, `B`=System, `C`=Communication, `S`=Service, `L`=Reference) |
| `UFLAG` | Sperrkennzeichen → Subtyp `Active`/`Locked` **plus** differenzierte Sperrgründe (s. u.) |
| `GLTGV` | gültig von (`date`) |
| `GLTGB` | gültig bis (`date`) |
| `TRDAT` | letzter Logon (`date`, optional) |
| `CLASS` | Benutzergruppe (optional) |

**Sperrgründe aus `UFLAG`** (Bit-Flags, beim Import via `apoc.bitwise.op` zerlegt; ⚠️ Werte
gegen euer System bestätigen): `0` = nicht gesperrt; Bit `32` = durch Fehlanmeldungen; Bit `64`
= durch Administrator (lokal); Bit `128` = durch Administrator (global/ZBV). Kombinationen
möglich (Summe der Bits, z. B. `192` = `64`+`128`). Gespeichert als Property `lockReasons`
(Liste) + `uflag` (Rohwert); Subtyp-Label `Active` (UFLAG = 0) bzw. `Locked` (sonst).

**Bewusst NICHT extrahieren:** `BCODE`, `PASSCODE`, `PWDSALTEDHASH`, `CODVN`, `OCOD*` und alle
weiteren Passwort-/Hash-Felder. Klartextname/Adressdaten (USR21/ADRP) sind für Can-Do nicht
nötig — optional und separat (Did-Do-Phase: Pseudonymisierung beachten).

> **Defense in Depth:** Falls diese Spalten doch mitexportiert wurden, verwirft sie der
> Konverter (`Convert-Se16Export.ps1`, Parameter `-DropColumnsLike`) bereits bei der
> Umwandlung — sie landen in keiner CSV. Die Load-Skripte lesen ohnehin nur die benötigten
> Spalten, sodass Passwort-/Hash-Daten den Graphen nie erreichen.

### 02 — AGR_DEFINE (Rollen) → `:Role`
| Spalte | Verwendung |
| --- | --- |
| `AGR_NAME` | Rollenname (fachliche `id`) |
| `PARENT_AGR` | **Sammelrolle** (bestätigt) — übergeordnete Composite-Rolle; deckungsgleich mit `AGR_AGRS` |

Subtyp `Composite`/`Single` wird **abgeleitet**: Composite = tritt in `AGR_AGRS` als `AGR_NAME`
(bzw. als `PARENT_AGR` in AGR_DEFINE) auf, sonst `Single`. Der Subtyp `Derived` und die Kante
`DERIVED_FROM` (abgeleitete Rolle → Master) haben in den aktuell extrahierten Tabellen **keine
bestätigte Quelle** (`PARENT_AGR` = Sammelrolle, nicht Ableitungsvorlage) → **zurückgestellt**,
bis die Ableitungs-Information vorliegt.

### 21 — AGR_TEXTS (Rollentexte) → `:Role.text`
| Spalte | Verwendung |
| --- | --- |
| `AGR_NAME` | Rollenname (Join auf `:Role`) |
| `SPRAS` *(bzw. `SPRSL`)* | Sprachschlüssel → `$lang`-Schalter; Loader liest robust beide |
| `TEXT` | Rollenbeschreibung → `r.text` |

Kanonische, **sprachabhängige** Quelle für Rollentexte (`AGR_DEFINE.TEXT` in `02` ist
einsprachig und lückenhaft). Läuft nach `02`: bevorzugte Sprache aus `$lang` überschreibt,
sonst bleibt der erste vorhandene Text. Siehe `load/21_role_texts.cypher`.

### 22 — AGR_1016B (Profil-Generierungsstatus) → `:Role`-Properties
| Spalte | Verwendung |
| --- | --- |
| `AGR_NAME` | Rollenname (Join auf `:Role`) |
| `GENERATED` | `'X'` = Profil generiert → `r.profileGenerated` (true, wenn **alle** Profile der Rolle) |
| `PSTATE` | Profilstatus (roh, ohne Interpretation) → `r.profileState` (Liste distinct) |

Verlustfrei/konzeptunabhängig: hält fest, ob die generierten Profile einer Rolle vorhanden/aktiv
sind. In Konzepten mit nicht generierten/veralteten Rollen sind deren AGR_1251-Berechtigungen
zur Laufzeit nicht (vollständig) aktiv — das **Finding** dazu (betroffene Rollen) gehört in die
Auswertung (Phase 3, AE-10), hier nur das Rohfaktum. Eine Rolle kann mehrere Profile haben
(`COUNTER`>1, Split bei >150 Objekten) → Aggregation je Rolle. Siehe `load/22_role_profile_status.cypher`.

### 03 — AGR_AGRS (Rollenhierarchie) → `CONTAINS`
| Spalte | Verwendung |
| --- | --- |
| `AGR_NAME` | Sammelrolle (Composite) |
| `CHILD_AGR` | enthaltene Einzelrolle |

### 04 — AGR_USERS (User-Rollen-Zuordnung) → `ASSIGNED_TO`
| Spalte | Verwendung |
| --- | --- |
| `UNAME` | User-ID |
| `AGR_NAME` | Rolle |
| `FROM_DAT` | Gültig-von der Zuordnung (`validFrom`, `date`) |
| `TO_DAT` | Gültig-bis der Zuordnung (`validTo`, `date`; `99991231`→`9999-12-31`) |

### 05 — AGR_PROF (Rolle → Profil) → `HAS_PROFILE`
| Spalte | Verwendung |
| --- | --- |
| `AGR_NAME` | Rolle |
| `PROFILE` | generiertes Berechtigungsprofil der Rolle |

`AGR_PROF` (Spalten `AGR_NAME`, `PROFILE`) genügt für `HAS_PROFILE` — `AGR_1016B` ist **nicht**
zusätzlich nötig.

### 06 — UST04 (User → Profil direkt) → `HAS_PROFILE`
| Spalte | Verwendung |
| --- | --- |
| `BNAME` | User-ID |
| `PROFILE` | direkt zugewiesenes Profil (z. B. `SAP_ALL`) |

### 07 — USR11 (Profiltexte) → `:Profile`-Properties
| Spalte | Verwendung |
| --- | --- |
| `PROFN` | Profilname (fachliche `id`) |
| `PTEXT` | Profiltext |
| `LANGU` | Sprache (Filter, z. B. `D`/`E`) |

Profil-Knoten entstehen aus den referenzierenden Quellen (AGR_PROF, UST04) und werden hier um
den Text angereichert.

### 08 — AGR_1251 (Berechtigungsdaten) → `:Authorization`, `HAS_AUTH`, `FOR_OBJECT`
| Spalte | Verwendung |
| --- | --- |
| `AGR_NAME` | Rolle (Träger der Berechtigung) |
| `OBJECT` | Berechtigungsobjekt (→ `:AuthObject`, z. B. `S_TCODE`) |
| `AUTH` | Auth-Instanz-Name (Gruppierungsschlüssel) |
| `FIELD` | Berechtigungsfeld (z. B. `ACTVT`, `BUKRS`, `TCD`) |
| `LOW` | Wert/Von-Wert |
| `HIGH` | Bis-Wert (bei Bereichen) |
| `DELETED` | Kennzeichen — Zeilen mit `X` ausfiltern |

**Gruppierung (AE-03):** ein `:Authorization`-Knoten je (`AGR_NAME`, `OBJECT`, `AUTH`) innerhalb
eines `dataset`. Feldwerte als Properties am Knoten: pro Feld `f_<FELD>` als Liste; Bereiche als
`"LOW..HIGH"`. `*` bleibt erhalten (AE-06).

### 09 — TSTC (Transaktions-Katalog) → `:Transaction`
| Spalte | Verwendung |
| --- | --- |
| `TCODE` | Transaktionscode (fachliche `id`) |
| `PGMNA` | Programmname (optional) |

### 10 — USOBT_C (SU24: Vorschlagswerte) → `CHECKS`
| Spalte | Verwendung |
| --- | --- |
| `NAME` | Transaktionscode |
| `OBJECT` | Berechtigungsobjekt (SU24-Vorschlag) |
| `FIELD` | Berechtigungsfeld (optional, Vorschlagswert) |
| `LOW` | Vorschlags-Von-Wert (optional) |
| `HIGH` | Vorschlags-Bis-Wert (optional) |

Kante `(:Transaction)-[:CHECKS]->(:AuthObject)` aus den eindeutigen (`NAME`, `OBJECT`)-Paaren.
`USOBT_C` enthält die SU24-Vorschlagsobjekte einer Transaktion (mit Default-Feldwerten); das
genügt für `CHECKS`. Die Unterscheidung „Prüfung aktiv/unterdrückt" (`USOBX_C.OKFLAG`) fehlt
damit — bei Bedarf später über das optionale `USOBX_C` präzisieren.

## Validierung (AE: Importvalidierung)

Nach dem Import werden Zähler je Knoten-/Kantentyp gegen die Quell-Rowcounts der CSVs
geprüft (Skript `load/99_validate.cypher`, Phase-2-Abschluss). Stichproben gegen SAP
(einzelne User/Rollen) sichern die fachliche Nachvollziehbarkeit (DoD).

## Was hier (noch) NICHT abgebildet ist

- **Profil-Eigenwerte** (manuell gepflegte Profile via `UST12`/`USR12`, Profil-Inhalte
  `UST10S`): der rollenbasierte Pfad über `AGR_1251` ist abgedeckt; reine Profil-Auth-Werte
  außerhalb von Rollen bei Bedarf in einem Folgeschritt.
- **`DERIVED_FROM` / abgeleitete Rollen**: keine bestätigte Quelle in den extrahierten
  Tabellen (`PARENT_AGR` = Sammelrolle). Nachrüstbar, sobald die Ableitungsvorlage vorliegt.
- **Prüfkennzeichen** (`USOBX_C.OKFLAG`): nicht extrahiert; `CHECKS` basiert auf den
  USOBT_C-Vorschlagsobjekten. Präzisierung „aktiv/unterdrückt" später möglich.
- **Fiori/OData-Ebene** (S/4): bewusst zurückgestellt (siehe [Datenmodell](datamodel.md)).
- **Org-Ebenen-Pivot** (`AGR_1252`, `OrgValue`-Knoten): optional, nur falls benötigt.
