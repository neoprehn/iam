# Sphinx-Konfiguration — IAM-Doku (Read the Docs)
# Markdown-Quellen über MyST. Build: sphinx-build -b html docs docs/_build/html

project = "IAM — SAP-Berechtigungsanalyse mit Neo4j"
author = "Mirko Prehn"
copyright = "2026, Mirko Prehn"
release = "0.1"

language = "de"

extensions = [
    "myst_parser",
]

# MyST-Erweiterungen: Doppelpunkt-Fences (```{note}), Definitionslisten
myst_enable_extensions = [
    "colon_fence",
    "deflist",
]

# Tiefe der automatisch erzeugten Anker-Slugs für Querverweise auf Überschriften
myst_heading_anchors = 3

exclude_patterns = [
    "_build",
    "Thumbs.db",
    ".DS_Store",
    "legacy",
]

html_theme = "furo"
html_title = "IAM-Doku"
