# Audio-Brief — Sunny Cove

Benötigte Sounds und Musik für die erste Beta. Stil durchgängig: **warm, tropisch,
freundlich, „juicy"** (satte, weiche Casual-Game-Sounds). Formatvorschlag: kurze SFX als
**.wav/.caf** (44.1 kHz, mono), Musik als **.m4a/AAC** (stereo, nahtlos loopbar).
Längen sind Richtwerte.

## 1. UI-Sounds

| ID | Auslöser | Stimmung | Länge |
|---|---|---|---|
| `ui_tap` | normaler Button-Tap | weich, hell, „pop" | 80–150 ms |
| `ui_tap_primary` | Haupt-/CTA-Button | voller, bestätigend | 120–200 ms |
| `ui_back` | Zurück/Schließen | absteigend, leicht | 100–180 ms |
| `ui_toggle` | Schalter/Regler | kurzer Klick | 60–120 ms |
| `ui_error` | ungültige Aktion, gesperrt | sanftes „Nope", nicht hart | 150–250 ms |
| `ui_popup_open` | Popup/Modal öffnet | aufsteigendes Whoosh | 200–350 ms |
| `ui_popup_close` | Popup schließt | absteigendes Whoosh | 150–300 ms |

## 2. Merge & Board

| ID | Auslöser | Stimmung | Länge |
|---|---|---|---|
| `merge_pick` | Item aufnehmen | leichtes „Pluck" | 60–120 ms |
| `merge_drop` | Item ablegen (gültig) | weiches „Tap" | 80–150 ms |
| `merge_success` | zwei Gleiche verschmelzen | saftiges „Blubb", befriedigend | 200–350 ms |
| `merge_tier_up` | neue, höhere Stufe entsteht | aufsteigendes Glitzer-Motiv | 350–600 ms |
| `merge_invalid` | ungültiges Ablageziel | sehr kurzes, weiches „Doff" | 100–180 ms |
| `board_unlock_tile` | Feld/Sand/Spinnwebe entfernt | knirschend + befreiend | 250–450 ms |

## 3. Generatoren

| ID | Auslöser | Stimmung | Länge |
|---|---|---|---|
| `gen_produce` | Generator antippen → Item | kurzes „Plopp/Spawn" | 120–250 ms |
| `gen_ready` | Generator wieder aufgeladen | freundliches „Ding" | 200–350 ms |
| `gen_empty` | angetippt, aber im Cooldown | leeres, sanftes „Klick" | 100–180 ms |
| `gen_upgrade` | dauerhaft aufgewertet | glänzendes Aufwerten, festlich | 500–800 ms |

## 4. Belohnungen

| ID | Auslöser | Stimmung | Länge |
|---|---|---|---|
| `reward_coin` | Münzen gutgeschrieben | heller Münz-Klimper (stapelbar) | 120–250 ms |
| `reward_gem` | Edelstein erhalten | kristallines „Pling" | 200–350 ms |
| `reward_xp` | Erfahrung gutgeschrieben | weiches Aufsteigen | 150–300 ms |
| `reward_energy` | Energie aufgefüllt | elektrisches „Zap", freundlich | 200–350 ms |
| `chest_open` | Truhe/Geschenk öffnet | Deckel + Glitzer-Schauer | 400–700 ms |
| `order_complete` | Auftrag abgegeben | zufriedenes Fanfärchen | 500–900 ms |
| `level_up` | Levelaufstieg | freudige kleine Fanfare | 800–1400 ms |
| `daily_reward` | tägliche Belohnung abgeholt | einladendes „Ta-da" | 500–900 ms |
| `star_earn` | Stern/Meilenstein | funkelnd, aufsteigend | 300–500 ms |

## 5. Dialog / Figuren

Kurze, nonverbale „Voice-Blip"-Loops pro Figur (à ~1–2 Silben, während Text tippt),
plus Öffnen/Schließen der Dialogbox. Stimmung passend zur Figur:

| ID | Auslöser | Stimmung | Länge |
|---|---|---|---|
| `dialog_open` | Dialogbox erscheint | sanftes Einblenden | 150–300 ms |
| `dialog_close` | Dialogbox verschwindet | sanftes Ausblenden | 150–300 ms |
| `voice_marina` | Marina spricht (Text-Blip) | hell, warm, jung | 80–150 ms/Blip |
| `voice_kai` | Kai spricht | entspannt, sonnig | 80–150 ms/Blip |
| `voice_shelly` | Shelly spricht | ruhig, weich, tief | 80–150 ms/Blip |
| `voice_gull` | Gull spricht | kess, zwitschernd | 80–150 ms/Blip |

Optional je Figur eine Stimmungs-Variante (fröhlich/überrascht/traurig) für stärkere
Betonung — nicht Beta-kritisch.

## 6. Hintergrundmusik (nahtlose Loops)

| ID | Kontext | Stimmung | Länge (Loop) |
|---|---|---|---|
| `music_main_theme` | Hauptspiel / Merge-Board | entspannt tropisch, Ukulele/Marimba/leichte Steel-Drums | 60–120 s |
| `music_restoration` | Restaurierungsansicht Strandbar | wärmer, hoffnungsvoll aufbauend | 60–120 s |
| `music_shop` | Shop / Menüs | verspielt, leicht | 30–60 s |
| `music_title` | Startbildschirm/Titel | einladend, sommerlich, mit Wellen-Ambient | 30–60 s |

## Ambient (optional, Beta-nice-to-have)

| ID | Kontext | Stimmung | Länge |
|---|---|---|---|
| `amb_waves` | leiser Dauerloop unter Musik | sanfte Brandung + Möwen | 30–60 s |

## Umsetzungshinweise

- **Loudness** einheitlich normalisieren (z. B. ~-16 LUFS SFX-Bus), damit gestapelte
  Belohnungssounds nicht clippen.
- `reward_coin`/`merge_success` mit leichter **Pitch-Variation** (±2–3 %) pro Auslösung,
  damit Serien nicht monoton klingen.
- Alle Sounds **respect Mute-Toggle** (`btn_audio_*`) und iOS-Silent-Switch beachten.
- Musik-Loops **click-frei** schneiden (Zero-Crossing / kleines Crossfade).
