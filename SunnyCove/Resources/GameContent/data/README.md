# Sunny Cove — Technische Übergabe (`data/`)

Maschinenlesbare Spiel- und Content-Daten zum Asset-Paket. **Alle Pfade sind relativ
zur Paket-Wurzel** (`SunnyCoveAssets/`, z. B. `items/chain1_beach_1_shell_shard.svg`),
alle Dateien **UTF-8**. Es wurden **keine Grafiken erzeugt und keine Dateien umbenannt** —
die JSON-Dateien verweisen nur auf die vorhandenen 173 Assets.

Erzeugt/aktualisiert wird alles reproduzierbar über `_src/gen_data.py` (scannt die echten
Assets, prüft jeden referenzierten Pfad, validiert die JSON-Syntax beim Schreiben).

## Dateien

### `asset_manifest.json`
Vollständiges Verzeichnis aller **173 Assets**. Pro Eintrag: `id`, `path` (relativ),
`category`, `format`, `width`/`height` (aus dem SVG-`viewBox`), `transparent` (false nur
bei vollflächigen Hintergründen: die drei `beachbar_*`, App-Icon, Splash), `purpose` und
`appName` (Anzeigename in der App). Zusätzlich `byCategory` mit Zählern. Kategorien:
`merge_item`, `generator_state`, `board_tile`, `board_token`, `character_pose`, `ui`,
`scene`, `scene_element`, `appstore`.

### `merge_chains.json`
Die **5 Merge-Ketten × 8 Stufen**. Pro Stufe: `stage` (1–8), `id`, `asset`, `displayName`,
`sellValue` (Münzen), `xpValue`, `unlockedByDefault` (nur Stufe 1 = true) und `mergeInto`
(Ziel-Item beim Zusammenlegen; bei Stufe 8 = `null`). Kette trägt `boardColor` und den
zugehörigen `generator`.

### `generators.json`
Die **5 Generatoren**. Pro Generator: `states` mit den vier Zustands-Assets
(`ready`, `producing`, `cooldown`, `upgraded`), `producesChain` sowie `base`/`upgraded`
mit `energyCostPerTap`, `maxCharges`, `rechargeSeconds`, `productionAnimationMs` und
`dropTable` (gewichtete Item-Stufen, Summe der Gewichte = 1.0). `upgraded` = dauerhaft
aufgewerteter Zustand (mehr Ladungen, schneller, höhere Stufen).

### `orders_campaign_01.json`
**30 sequenzielle Aufträge** der ersten Kampagne. Pro Auftrag: `id`, `sequence`,
`character` (`marina`/`kai`/`shelly`/`gull`), `portrait` (Pfad zur Posen-Grafik) +
`portraitPose`, `dialog` (Text), `requiredItems` (Liste `{item, asset, displayName,
count}`), `rewards` (`coins`, optional `gems`/`energy`), `xp` und `restorationActions`
(Liste; `set_state:<id>` schaltet einen Bauzustand, `unlock_element:<id>` ein
platzierbares Element frei). Die Aktionen greifen in `restoration_beachbar.json`.

### `restoration_beachbar.json`
Restaurierungsbereich **Marinas Strandbar**: die **3 Bauzustände** (`damaged` → `partial`
→ `restored`, mit `unlockOrder`) und die **9 platzierbaren Elemente** (`order` =
Einblend-Reihenfolge, `unlockOrder` = Auftrag, der sie freischaltet, `asset`,
`displayName`).

### `content-manifest.example.json`
**Beispiel-Vorlage** für eine später versionierte Content-Auslieferung (OTA/Patch):
`schemaVersion`, `contentVersion`, `minAppVersion`, `generatedAt`, `integrity`
(Algorithmus + Manifest-Hash) sowie `dataFiles`/`assets` mit **Hash- und bytes-
Platzhaltern** (`sha256:<PLATZHALTER>`), die eine echte Build-Pipeline füllt. Dient nur
als Schema-Referenz.

### `ui_layout_notes.md`
Integrationshinweise für die native iPhone-App: Safe Area (oben ~59 pt, unten ~34 pt),
Seitenränder, 4-pt-Raster, 44-pt-Trefferflächen, Button-Zustände, 9-Slice für Panels und
– zentral – die **dynamischen Textflächen** je UI-Asset (die App zeichnet Text, die
Grafiken enthalten keinen).

### `audio_brief.md`
Vollständige Sound- und Musikliste (UI, Merge, Generator, Belohnung, Dialog,
Hintergrundmusik, optionales Ambient) mit **Auslöser, Stimmung und Richtlänge** plus
Umsetzungshinweisen (Loudness, Pitch-Variation, nahtlose Loops).

## Konventionen

- **IDs** sind die Dateinamen ohne Endung und dienen als stabile Schlüssel.
- **Referenz-Integrität:** Jeder `asset`/`portrait`-Pfad in den JSON-Dateien existiert in
  diesem Paket (durch `_src/gen_data.py` beim Erzeugen geprüft).
- **Balancing-Werte** (Verkaufs-/XP-Werte, Produktionszeiten, Belohnungen, Drop-Gewichte)
  sind sinnvolle Startwerte für die Beta und zum Feintuning gedacht.
- **Regenerieren:** `cd _src && python gen_data.py`.
