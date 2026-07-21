# Sunny Cove – Beta-Prüfung

Stand: 21. Juli 2026

## Claude-Paket

- 173 SVG-Assets in 8 Kategorien
- 40 Merge-Items in 5 Ketten
- 5 Generatoren
- 30 Kampagnen-Aufträge
- 11 Tutorial-Schritte
- 8 Content-JSON-Dateien
- XML-/JSON-Prüfung: erfolgreich
- Semantischer Validator: Exit 0
- Hinweis: Die optionale `jsonschema`-Bibliothek war in der Prüf-Umgebung nicht installiert; die semantischen Prüfungen liefen trotzdem vollständig.

## Balancing-Simulation

10.000 Läufe mit der gelieferten Konfiguration:

- erste Belohnung: Median 8,5 Sekunden
- erste Restaurierung: Median 0,92 Minuten
- Kampagne: Median 59,2 Minuten
- längster Auftrag: Median 8,2 Minuten
- Energieblockaden: 0 %
- Sackgassen: 0 %

Die erste Restaurierung ist bewusst sehr früh und dient als Onboarding. Das sollte im
ersten Playtest bestätigt werden.

## Noch vor einer TestFlight-Beta

1. Auf macOS `xcodegen generate` und den GitHub-Actions-Workflow ausführen.
2. Die IPA auf mindestens zwei iPhone-Größen testen.
3. App-Icon im Xcode-Asset-Catalog und Sounds/Musik auf dem Gerät prüfen.
