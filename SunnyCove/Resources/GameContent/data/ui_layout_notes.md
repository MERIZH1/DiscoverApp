# UI-Layout-Hinweise — Sunny Cove (natives iPhone)

Alle UI-Assets liegen unter `ui/` als **SVG ohne eingebauten Text**. Text, Zahlen und
Preise setzt die App zur Laufzeit. Diese Notizen beschreiben Platzierung, Safe Area,
Abstände und die dynamischen Textflächen. Alle Pfade sind relativ zur Paket-Wurzel.

## Grundlagen

- **Vektor, punktbasiert.** SVG beliebig skalierbar. Für SpriteKit/UIKit als
  **PDF-Vektor-Imageset** (Xcode: „Preserve Vector Data", „Single Scale") oder als
  **@1x/@2x/@3x-PNG** exportieren. Immer in **Points (pt)** denken, nicht Pixel.
- **viewBox = Seitenverhältnis.** Die Breite/Höhe im `viewBox` ist das native
  Layout-Verhältnis des Assets (siehe `asset_manifest.json` → `width`/`height`).
  Beim Skalieren Seitenverhältnis beibehalten.

## Safe Area (Portrait, moderne iPhones)

- **Oben:** Dynamic-Island-/Notch-Bereich ~**59 pt** freihalten. Die HUD-Leiste
  `ui/topbar.svg` direkt **unter** dem oberen Safe-Area-Inset ankern, volle Breite.
- **Unten:** Home-Indicator ~**34 pt**. Bottom-Bar / Haupt-Buttons oberhalb dieses
  Insets platzieren, nie dahinter.
- **Seiten:** **16–20 pt** Rand links/rechts für Panels und Karten.
- Sicherheitsregel: Interaktive Elemente und wichtige Grafikmotive nie in die
  Safe-Area-Insets legen.

## Abstände & Trefferflächen

- Raster in **4-pt-Schritten**; übliche Abstände **8 / 12 / 16 / 24 pt**.
- **Minimale Tap-Fläche 44 × 44 pt** (Apple HIG) — auch wenn ein runder Button
  optisch kleiner gerendert wird, die Trefferfläche auf ≥44 pt aufblasen.
- Runde Buttons (`btn_*`, viewBox 256×256) typischerweise **48–60 pt** anzeigen.
- Breite Buttons (`btn_wide_*`, 512×196) typischerweise **56–72 pt** hoch.

## Button-Zustände

Jeder Button existiert in vier Varianten (Suffix im Dateinamen):

| Zustand | Datei-Suffix | Verwendung |
|---|---|---|
| Normal | `_normal` | Ruhezustand |
| Gedrückt | `_pressed` | `touchDown` — gedrückt gezeichnet (kürzerer Schatten) |
| Deaktiviert | `_disabled` | nicht auslösbar (entsättigt) |
| Hervorgehoben | `_highlighted` | CTA / Tutorial-Fokus (Gold-Glow) — pulsieren lassen |

Empfehlung: Bei `touchDown` auf `_pressed` wechseln und den Inhalt ~2–3 pt nach unten
versetzen; bei `touchUpInside` zurück auf `_normal`.

## Panels & 9-Slice

Die Holzrahmen-Panels (`dialog_box`, `panel_settings`, `task_list`, Popups) haben eine
feste Eckenrundung. Wenn sie in der Höhe/Breite variieren müssen:

- **9-Slice** auf den Holzrahmen anwenden. Empfohlene Slice-Insets: **~48 pt** an jeder
  Kante (deckt Rahmen + Eckenradius ab), Mitte streckbar.
- Alternativ Panels in nativer Ratio anzeigen und nur proportional skalieren.

## Dynamische Textflächen (App zeichnet Text/Zahlen hier)

| Asset | Freifläche für App-Text |
|---|---|
| `ui/topbar.svg` | Level-Zahl auf dem runden Badge (links); Energie-Zahl über der Energieleiste; Münz-Zahl in der Münz-Pill; Edelstein-Zahl in der Edelstein-Pill |
| `ui/btn_wide_*_*.svg` | Label horizontal + vertikal **zentriert** im Button |
| `ui/dialog_box.svg` | **Portrait** in den Kreis links (Figur aus `characters/`); Sprechertext + Name in die Zeilenfläche rechts |
| `ui/order_card_*.svg` | Auftraggeber-Portrait in den Kreis oben; benötigte Items in die gestrichelten Slots; „Abgeben"-Label auf den grünen Button unten |
| `ui/popup_reward.svg` | Titel auf das Ribbon; Belohnungsmengen unter die Icons (Münze/Edelstein/Stern); Label auf den Button |
| `ui/popup_levelup.svg` | neue Level-Zahl auf das Badge; Fortschritt/Belohnungen in die Zeilen; Button-Label |
| `ui/daily_reward.svg` | Tagesnummern (1–7) + Belohnungsmengen in die Slots; aktiver Tag = gold umrandeter Slot |
| `ui/panel_settings.svg` | Options-Beschriftungen neben Reglern/Schaltern |
| `ui/shop_card*.svg` | Produktname oben; Menge über/unter dem Bild-Slot; Preis auf den Button |
| `ui/task_list.svg` | Aufgabentexte neben den Checkboxen; Fortschrittszahl an der Leiste unten |

Textempfehlung: abgerundete, fette Schrift (z. B. Nunito/Baloo 2 Bold), weiß mit
dezenter dunkler Kontur (`paint-order: stroke`) — passend zum Logo-Stil.

## HUD-Aufbau (Vorschlag)

1. `ui/topbar.svg` oben, volle Breite, direkt unter dem Safe-Area-Inset.
2. Merge-Board (7×9) mittig; Board-Kacheln/Tokens aus `board/`.
3. Aktiver Auftrag als `order_card_*` unten oder als seitliche Leiste.
4. Runde Utility-Buttons (`btn_settings`, `btn_info`, `btn_audio`) in einer Ecke der
   Top-Zone; `btn_close`/`btn_back` oben in Overlays.
5. Popups (`popup_*`, `daily_reward`) modal zentriert mit abgedunkeltem Hintergrund.
