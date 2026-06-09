# Changelog

Der oberste Abschnitt wird automatisch in die SideStore-Quelle uebernommen
(`versionDescription`), damit du im SideStore siehst, was neu ist.

## v2.21 — Mehrfachauswahl: Songs zusammen zur Playlist
- In **Suche, Playlist und Empfehlungen** oben rechts den Auswahl-Button (Haken-Symbol) antippen → Songs ankreuzen → unten **„Zu Playlist hinzufuegen (N)"**.
- Funktioniert auch fuer **lokale Navidrome-Songs** (werden beim Hinzufuegen zu Spotify-Treffern aufgeloest, sonst lokal eingefuegt).
- Langer Druck loest die Auswahl NICHT aus — nur der Button.

## v2.20 — Konsole-Feinschliff + 2 Bugfixes
- **Bugfix:** Lokalen (Navidrome-)Song zu einer Playlist hinzufuegen ging schief → wird jetzt automatisch zum passenden Spotify-Track aufgeloest und hinzugefuegt.
- **Bugfix:** Server-Logs blieben leer (das Sekunden-Sync-Polling flutete das Log-Fenster) → jetzt 2000 Zeilen Tiefe, Aktivitaet ist wieder sichtbar.
- **HW-Monitor live:** Ressourcen aktualisieren sich laufend (CPU/RAM in Echtzeit).
- **Speicher:** zeigt jetzt auch externe Platten unter /mnt (sofern in den Container gemountet).
- **Profil zum Admin befoerdern** (Krone) — fehlte komplett.
- **Verlauf erklaert sich:** gruene Eintraege zeigen „✓ Wieder alle Dienste erreichbar".
- **Benachrichtigungen pro Dienst waehlbar** (Spotify/Deezer/Navidrome/YouTube) + Meldung, wenn der **ganze Server wieder online** ist.

## v2.19 — Profile verwalten
- Konsole: Profile **auflisten, anlegen und loeschen** direkt aus der App (Admin).

## v2.18 — Server steuern aus der Konsole
- **Smart-Cache (Auto-Download)** direkt einstellbar: an/aus + Schwellen (ab X Sekunden gehoert / ODER X-mal abgespielt).
- **Server-Konfiguration** als Info-Anzeige (Navidrome/Deemix/Spotify-User + ob Passwort/Webhook gesetzt sind).

## v2.17 — Benachrichtigung bei Server-Problemen
- Die App meldet sich per **lokaler Mitteilung**, wenn ein Dienst ausfaellt (Spotify/Deezer/Navidrome/YouTube) — im Vordergrund sofort, im Hintergrund wann iOS es zulaesst (kein Push-Server noetig).
- Schalter in der Konsole („Benachrichtigungen") zum An-/Abschalten.

## v2.16 — Konsole: Speicher, Notfall, Logs teilen
- **Speicherplatz** mit Balken + Warnfarbe (orange ab 75%, rot ab 90%).
- **Notfall: alle Dienste neustarten** auf einen Knopf (inkl. Discover, mit „wieder online"-Bestaetigung).
- **Server-Logs teilen/exportieren** (Teilen-Symbol in der Log-Ansicht) — fuer wenn du sie mir schicken willst.

## v2.15 — Konsole 2.0
- **Server-Logs in Klartext** — die Konsole zeigt jetzt, was der Server tut, verstaendlich aufbereitet + farbcodiert (gruen ok / orange Warnung / rot Fehler). Debuggen ohne SSH.
- **Alle Playlists synchronisieren** auf Knopfdruck (statt auf den Nacht-Sync zu warten).
- **Statistik**: Abos, Radios, Navidrome-Songs, gecachte Playlists/Empfehlungen.
- **Ressourcen**: CPU/RAM der Kern-Container.
- **Login-Daten-Alter**: zeigt wie alt Spotify-/Deezer-/YouTube-Cookies sind (alt = Vorbote von Aussetzern).
- **Einzelne Caches gezielt leeren** (Playlists / Home / Empfehlungen) statt alles.

## v2.14 — Such-Tastatur + Bibliothek-Refresh
- Suche: Tastatur verschwindet beim Antippen eines Songs (auch bei „letzte Suche" / Genre-Kachel) und beim Scrollen durch die Ergebnisse.
- Bibliothek: Pull-to-Refresh (frische Playlists + Radios runterziehen).

## v2.13 — Pull-to-Refresh + mehr Feedback
- Playlists/Alben: nach unten ziehen laedt frisch von Spotify (umgeht den Cache → stale/Phantom-Eintraege verschwinden) + neue Empfehlungen.
- Mehr sichtbare Rueckmeldung: „Gesendet an X", Empfehlung hinzufuegen / zur Warteschlange melden jetzt Erfolg/Fehler.

## v2.12 — Entfernen-Feedback + Recs neu
- Song aus Playlist entfernen meldet jetzt klar Erfolg/Fehler (globaler Toast) statt stumm.
- Nach erfolgreichem Entfernen werden die Playlist-Empfehlungen neu geladen
  (Server-Empfehlungs-Cache wird bei Add/Remove invalidiert).

## v2.11 — „Gehe zu"-Menue
- Song-Menue: „Künstler anzeigen" + „Album anzeigen" sind jetzt im Untermenue „Gehe zu" gebuendelt (wie „Teilen") → Künstler / Album.

## v2.10 — Kein stilles Scheitern mehr
- Globales Toast-System: Aktionen (Radio erstellen/loeschen/als Playlist speichern, Album/Playlist speichern, synchronisieren, kopieren, Cache-Reset) melden jetzt **Erfolg ODER Fehler** — statt bei einem Problem einfach nichts zu tun.
- Song-Radio auf einem lokalen/YouTube-Treffer sagt jetzt klar „konnte nicht erstellt werden" (Radio braucht einen Spotify-Song).

## v2.9 — Parity mit der Webseite
- Song-Menue: „Auf Spotify oeffnen" + „Falsch gespielt – Cache zuruecksetzen"; bei lokalen Songs jetzt „Kuenstler + Name kopieren" statt der (sinnlosen) Spotify-/YouTube-Links.
- Radio-Menue: Radio loeschen (auch per Langdruck in der Bibliothek) + „Als Spotify-Playlist speichern".
- Navidrome-Album: „Als Playlist speichern" (Reihenfolge bleibt).
- Playlist-Menue: „Link kopieren", „Auf Spotify oeffnen", „Jetzt synchronisieren".
- Suche: Genre-Kacheln (Stoebern) auf der Startseite — Pop, Hip-Hop, Dance, Rock, Latin, R&B.

## v2.8 — Lokale Suche (Navidrome)
- Suche: neue „Lokal"-Pille + Navidrome-Treffer — Songs („Auf dem Server") und Alben („Alben auf dem Server"), in „Alle" und unter „Lokal".
- Lokale Songs streamen direkt aus der Bibliothek (Quellen-Badge im Player zeigt „Bibliothek"); Navidrome-Alben oeffnen sich mit erhaltener Reihenfolge.

## v2.7 — Radios sichtbar + Wiedergabe herholen
- Song-Radios tauchten nicht in der Bibliothek auf (die App lud `/api/radio-playlists` nie) → Filterpille „📻 Radios" blieb leer. Werden jetzt geladen und angezeigt.
- Neu erstelltes Song-Radio erscheint sofort in der Liste und startet mit Namen im Player.
- Remote/Connect: Wiedergabe laesst sich jetzt **aufs eigene Geraet holen** (im Geraete-Picker das eigene Geraet antippen). Vorher ging nur Wegschieben — die Wiedergabe blieb am PC.

## v2.6 — Song-Radio repariert
- „Song-Radio starten" tat in der App nichts: die erzeugte Radio-Playlist (radio-name:/radio-id:/radio:) wurde am falschen Endpoint geladen. Wird jetzt korrekt aufgeloest — Radio aus einem Song (und das Oeffnen gespeicherter Radios) funktioniert.

## v2.5 — Debug-Konsole
- Konsole (Account → Konsole) → neue Sektion „Debug/Wartung": Discover-Server (und andere Dienste wie deemix/navidrome/jellyfin) neustarten + Caches leeren — falls mal was haengt
- Beim Discover-Neustart wartet die App, bis der Server wieder antwortet, und meldet „läuft wieder ✓"

## v2.4 — Einheitliches Playlist-Menue
- Langer Druck auf eine Playlist in der Bibliothek zeigt jetzt dasselbe Menue wie das „…" in der Playlist (Alle herunterladen, Playlist-Radio, kopieren, löschen)

## v2.3 — Songs umbenennen
- YouTube-Songs (auch in importierten Playlists) lassen sich umbenennen: Song-Menue → „Umbenennen" → Titel/Interpret aendern
- Funktioniert ueber beide Wege gleich — langer Druck UND das „…"-Menue nutzen dasselbe Menue

## v2.2 — Quellen-Badge zeigt die echte Quelle
- Das Badge zeigt jetzt, woher gerade gespielt wird: „Gespeichert" (gruen) wenn der Song aus der lokalen Server-Datei laeuft, „YouTube" nur noch beim echten Live-Stream

## v2.1 — YouTube-Wiedergabe robuster
- YT-Songs blieben morgens bei 0:00 haengen (abgelaufene Stream-URL) -> die App holt jetzt automatisch eine frische URL und spielt weiter
- Play musste manchmal 2x gedrueckt werden -> Wiedergabe startet jetzt zuverlaessig beim ersten Druck

## v2.0 — Playlist-Link-Import
- Playlist-Link in die Suche einfuegen + Enter -> wird importiert: Spotify-Playlist folgt deiner Bibliothek, YouTube/YT-Music-Playlist wird als eigene lokale Playlist abgelegt (Name = Quell-Playlist). Funktioniert auch fuer grosse Playlists.
- Einzelne YouTube-Songs landen weiterhin in „YouTube-Funde"

## v1.8 — Spotify-Link in der Suche
- Spotify-Link (Track / Playlist / Album / Künstler) in die Suche einfuegen -> Track spielt direkt, der Rest oeffnet sich in der jeweiligen Ansicht (genau wie der YouTube-Link-Import)

## v1.9 — Playlists loeschen
- Playlists koennen jetzt geloescht werden: Playlist-Ansicht → ⋯-Menue → „Playlist loeschen" (mit Rueckfrage). Wie auf Webseite/PWA. Laeuft serverseitig ueber spclient, am gedrosselten Spotify-Web-API vorbei.

## v1.7 — Ein Player statt zwei (Connect)
- Wenn auf einem anderen Geraet gespielt wird, zeigt jetzt EIN Mini-Player das aktive Geraet — kein zweiter Banner mehr obendrauf
- Connect-Symbol im Mini-Player -> Geraet wechseln (wie Spotify Connect); Play/Pause steuert das aktive Geraet
- Antippen im Remote-Modus oeffnet direkt die Geraete-Auswahl

## v1.6 — Glass-Feinschliff im Player
- Player-Kopf-Icons (Schliessen / Sleep-Timer / Geraet / Menue) jetzt als Glas-Kreise — konsistent zur Playlist-Ansicht (Back/Glocke)

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
