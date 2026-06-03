# Changelog

Der oberste Abschnitt wird automatisch in die SideStore-Quelle uebernommen
(`versionDescription`), damit du im SideStore siehst, was neu ist.

## v1.5 — iOS-26-Look ab Werk
- Liquid Glass ist jetzt standardmaessig AN (auf iOS 26) — die App sieht ab Werk nach iOS 26 aus (per Einstellung abschaltbar)
- Such- + Filterfelder (Suche, Bibliothek, Radio) durchgaengig im Glass-Look mit adaptivem Text
- Auf iOS < 26 weiterhin solide Optik (kein Unterschied)

## v1.4 — Alle Playlists + Liquid-Glass-Pass
- Bibliothek laedt jetzt ALLE Playlists (paginiert + inkrementell) — brach vorher nach ~50 ab und lud beim Runterscrollen nicht nach
- Schnelleres Gefuehl: Seite 1 erscheint sofort, der Rest fuellt sich im Hintergrund
- Liquid Glass (iOS 26, optional per Einstellung) auf mehr Flaechen: Bibliotheks-Suche + Radio-Suche

## v1.3 — Suche & Player-Politur
- Suche: YouTube-Funde mit rotem "YT"-Badge gekennzeichnet
- Suche: Pfeil zum Einklappen der Tastatur (wie in der PWA)
- Suche: "Letzte Suchanfragen" jetzt mit Cover + Titel + Typ (wie auf der Webseite)
- Player: "Songtext"-Button symmetrisch zur Mitte ausgerichtet (passend zu AirPlay + Warteschlange)
- Mini-Player: beim Buffern zeigt er jetzt an, ob der Song von YouTube oder aus der Bibliothek laedt

## v1.2 — Radiosender hinzufuegen + EQ-Ruckler-Fix
- Radio: + oben rechts -> Sender suchen & zu den Favoriten hinzufuegen (ging vorher gar nicht)
- Fix: kurzer Ruckler/komischer Klang beim Songwechsel bei aktivem EQ — der Audio-Mix wird jetzt VOR dem Start gesetzt statt mitten rein

## v1.1 — Wiedergabe-Geraet wechseln + Playlist-Cleanup
- Wiedergabe-Geraet wechseln (Connect-Style): im Player aufs Lautsprecher-Symbol tippen -> ein anderes Geraet uebernimmt Song + Warteschlange an der aktuellen Position
- Songs aus Playlists entfernen — im Song-Menue, fuer eigene Spotify-Playlists + YouTube-Funde
- Playback-Fix: nicht-heruntergeladene Songs blieben in der App bei 0:00 haengen (WebM/Opus) -> Server liefert jetzt AAC/m4a

## v1.0 — Audit & Stabilisierung
- Fluessigeres Scrollen: Cover werden zwischengespeichert (kein Neu-Laden)
- Fix: Lockscreen-Cover laedt jetzt auch bei relativen Bild-URLs
- Sync schont Akku/Server (langsamer pollen wenn nichts laeuft)
- Admin-Konsole (Account → Konsole): Status der Dienste, Spotify-Cookie erneuern, Verlauf
- Sicherheits-Audit Backend: Pfad-Traversal-Schutz + Request-Limit
- Sync: Befehle ~1s statt ~5s, Play/Pause zurueck an Remote
- Geraete-Name selbst setzbar (Einstellungen → Geraet)
- Empfangene Songs werden als Toast angezeigt
- Songs an andere Nutzer senden (erreicht auch PWA)
- Synced/Karaoke-Lyrics, Playlist kopieren, Zu Playlist hinzufuegen
- Podcast-Downloads (richtige Endung + Fortschritt)
- Aufgeraeumt: alter WebView-Code entfernt; App nur Hochformat
