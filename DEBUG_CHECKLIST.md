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
