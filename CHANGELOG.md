# Changelog

Der oberste Abschnitt wird automatisch in die SideStore-Quelle uebernommen
(`versionDescription`), damit du im SideStore siehst, was neu ist.

## v1.0 — Audit & Stabilisierung
- Admin-Konsole (Account → Konsole): Status der Dienste, Spotify-Cookie erneuern, Verlauf
- Sicherheits-Audit Backend: Pfad-Traversal-Schutz + Request-Limit
- Sync: Befehle ~1s statt ~5s, Play/Pause zurueck an Remote
- Geraete-Name selbst setzbar (Einstellungen → Geraet)
- Empfangene Songs werden als Toast angezeigt
- Songs an andere Nutzer senden (erreicht auch PWA)
- Synced/Karaoke-Lyrics, Playlist kopieren, Zu Playlist hinzufuegen
- Podcast-Downloads (richtige Endung + Fortschritt)
- Aufgeraeumt: alter WebView-Code entfernt; App nur Hochformat
