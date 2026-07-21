# Erwartete Prüf-Ergebnisse der Test-Manifeste

Angenommene laufende App-Version im Test: **1.0.0**.

| Manifest | Prüfschritt, der greift | Ergebnis |
|---|---|---|
| `update_valid.json` | Signatur → Hashes → minAppVersion (1.0.0 ≥ 1.0.0) | **AKZEPTIERT**, atomar aktiviert |
| `update_bad_hash.json` | SHA-256 von `data/generators.json` ≠ Manifest | **ABGELEHNT** — Datei erneut laden/Abbruch, kein Aktivieren |
| `update_incompatible.json` | minAppVersion 2.0.0 > App 1.0.0 | **ABGELEHNT** — Hinweis „App aktualisieren", Rollback auf eingebautes Paket |

Prüfreihenfolge laut `design/content_update_system.md`: Signatur → Datei-Hashes →
minAppVersion → atomare Aktivierung. Bei `update_bad_hash` schlägt die Hash-Stufe fehl,
bei `update_incompatible` die Versions-Stufe.
