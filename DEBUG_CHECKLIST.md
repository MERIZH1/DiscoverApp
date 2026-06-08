# Discover — Debug-/Parity-Merkliste

Laufende Liste: was gefixt ist und was noch offen. ASCII (keine Umlaute).

## ✅ Erledigt — App (alles in main, Build gruen bis ca95d07)
- Debug-Konsole: Docker-Container neustarten + Caches leeren; Discover-Selbstneustart
  mit Polling + "laeuft wieder"-Toast.
- Song-Radio repariert: radio-name:/radio-id:/radio: werden auf die Radio-Endpoints
  geroutet (vorher generisches /api/playlist -> leer -> tat nichts).
- Radios in der Bibliothek: App lud /api/radio-playlists nie -> Filterpille leer.
  Jetzt geladen + nach Erstellen sofort sichtbar + spielt mit Namen.
- Remote/Connect: Wiedergabe aufs EIGENE Geraet holen (pullPlaybackHere) -
  vorher nur wegschieben moeglich (blieb am PC).
- Lokale Suche: "Lokal"-Pille + Navidrome-Songs ("Auf dem Server") + -Alben;
  navidromeId -> direktes Navidrome-Streaming; Badge "Bibliothek".
- Parity-Menues:
  - Song: "Auf Spotify oeffnen", "Cache zuruecksetzen", lokale Songs
    "Kuenstler + Name kopieren" statt sinnloser Links.
  - Radio: loeschen (+ Langdruck in Library) + "Als Spotify-Playlist speichern".
  - Navidrome-Album: "Als Playlist speichern".
  - Playlist: "Link kopieren", "Auf Spotify oeffnen", "Jetzt synchronisieren".
  - Suche-Startseite: Genre-Kacheln (Pop/Hip-Hop/Dance/Rock/Latin/R&B).
- Globales Toast-System (AppState.flash + Overlay): kein stilles Scheitern mehr -
  alle Menue-Aktionen melden Erfolg/Fehler.

## ✅ Erledigt — Backend (Server, live nach Restart)
- Empfehlungen ~5x schneller: Deezer-Anreicherung parallel (Semaphore 6) statt
  seriell + sleep(0.15); + 30-Min-Cache fuer die 1. Seite (Playlist erneut oeffnen = instant).
- v1-Audit: Suche (Pathfinder) + Playlist-erstellen (spclient) schon "v2";
  restliche /v1 sind Fallbacks/selten -> bewusst als Sicherheitsnetz behalten.

## ✅ Erledigt — diese Runde nachgezogen
- PWA-Bug: Kuenstler-Link war am Desktop tot (Touch-Sperre galt faelschlich auch
  fuer Maus) -> jetzt am Desktop ueberall klickbar (app.js, SW v97).
- App: "Gehe zu"-Untermenue (Kuenstler/Album) im Song-Menue (d666e3b).
- Backend: Empfehlungen ~5x schneller (parallel + Cache) — bestaetigt schneller.

## ✅ Erledigt — Playlist-Song entfernen (Backend)
- Ursache war ein "Phantom"-Track: beim Hinzufuegen optimistisch in den persistenten
  _playlist_cache geschrieben, aber auf Spotify nie angekommen (Vertipper) -> blieb
  haengen, GQL-Resolve fand die uid nicht -> /v1-Fallback 429.
- Fix: (a) GQL-Resolve mit Retry gehaertet, (b) /v1-Fallback entschaerft (2x/8s statt
  5x/35s), (c) "uid nicht gefunden" = Phantom -> aus lokalem Cache entfernen + ok
  melden (kein sinnloses /v1), (d) aktuellen Phantom per force-refresh bereinigt.
- App: Entfernen meldet jetzt sichtbar + laedt Recs neu (schon committed, bee9fb0).

## ✅ Erledigt — autonome Bug-Runde
- Player- + Sync-Flows Zeile-fuer-Zeile gelesen: solide gebaut, keine echten Bugs.
  (Notiz: Sync nutzt device_name statt device_id zur Self-Erkennung -> Edge-Case
  bei gleichnamigen Geraeten, bewusst nicht geaendert ohne Testmoeglichkeit.)
- Pull-to-Refresh fuer Playlists/Alben (force=1 -> stale/Phantome wegziehbar).
- Toast-Feedback nachgeruestet: Senden-an-Profil, Empfehlung hinzufuegen/Warteschlange.
- Empfehlungen ~5x schneller (parallel + Cache, Invalidierung bei Add/Remove).
- PWA: Kuenstler-Link am Desktop repariert.

## ✅ Erledigt — autonome Runde 2 (Vollgas)
- Pull-to-Refresh ueberall: Playlists, Alben, Bibliothek, Home (+ nocache fuer echte frische Empfehlungen).
- Offene Playlist aktualisiert sich nach Aenderung (Umbenennen etc.) automatisch.
- Such-Tastatur schliesst beim Song-/Top-Treffer-/Recent-/Genre-Tap + beim Scrollen.
- Lueckenloses Aktions-Feedback (Toast): Senden, Hinzufuegen, Warteschlange, Radio,
  Entfernen, Cache-Reset, Alle-herunterladen, Abo, Umbenennen, YT-Match.
- Backend: Empfehlungs-Cache konsistent (Invalidierung bei Add/Remove, in clear-cache, nocache-Param).
- Player/Sync/DownloadManager: Zeile-fuer-Zeile reviewed -> exzellent, keine Bugs.

## 🔲 Offen / als Naechstes
- [ ] Build d666e3b+ signieren (rustsign) + durchtesten: Radios, lokale Suche,
      Toasts, Remote-Transfer, "Gehe zu", alle neuen Menues.
- [ ] Player- + Sync-Flows Zeile-fuer-Zeile auf Bugs pruefen (LAEUFT als Naechstes).
- [ ] "Senden an Profil" (Song an User): Toast-Feedback noch nicht verdrahtet.
- [ ] Home-Feed: Genre/Mood-Browse auf der Home-Startseite (PWA?) nicht verglichen.
- [ ] Optional/niedrige Prio: Radio->als-Playlist nutzt noch /v1 direkt
      (koennte spclient_create_playlist nutzen).

## ⏭️ Bewusst weggelassen
- Parity #1: "Songtext anzeigen" direkt im Song-Menue (App hat Lyrics im Player).
- Parity #10: Replace-Modus (Song aus Playlist heraus ersetzen) — App deckt das
  Beduerfnis ueber "YouTube-Match fixen" ab.
- Automix/DJ-Drops (eigener Prototyp, verworfen — zu komplex).
