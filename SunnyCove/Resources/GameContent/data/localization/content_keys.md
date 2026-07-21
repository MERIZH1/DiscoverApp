# Localization-Key-Mapping der Content-Dateien

> **Wichtig:** Die bestehenden Content-JSONs (`merge_chains.json`, `generators.json`,
> `orders_campaign_01.json`, `restoration_beachbar.json`, `asset_manifest.json`,
> `tutorial_campaign_01.json`) wurden **bewusst nicht verändert** (harte Vorgabe:
> keine vorhandenen Dateien anfassen). Ihre deutschen `displayName`/`dialog`/`text`-
> Felder bleiben als Autoren-/Fallback-Referenz erhalten. Zur Laufzeit lädt die App die
> Anzeigetexte aus `de.json`/`en.json` über die **hier dokumentierten, aus der jeweiligen
> ID deterministisch ableitbaren Schlüssel**. Bei einer künftigen Content-Version können
> diese Keys zusätzlich als `locKey`-Feld in die Content-Dateien eingebettet werden, ohne
> bestehende Felder zu entfernen.

## Ableitungsregeln (ID → Localization-Key)

| Content-Datei | Feld | Localization-Key | Sektion in de/en.json |
|---|---|---|---|
| `merge_chains.json` | `stages[].displayName` | `item.<stageId>.name` | `item` |
| `orders_campaign_01.json` | `orders[].dialog` | `order.<orderId>.dialog` | `order` |
| `orders_campaign_01.json` | `requiredItems[].displayName` | `item.<itemId>.name` | `item` |
| `generators.json` | `generators[].displayName` | `generator.<genId>.name` | `generator` |
| `restoration_beachbar.json` | `placeableElements[].displayName` | `restorationElement.<elemId>.name` | `restorationElement` |
| `restoration_beachbar.json` | `states[].id` | `restorationState.<stateId>.name` | `restorationState` |
| `tutorial_campaign_01.json` | `steps[].text` | `tutorial.<stepId>.text` | `tutorial` |
| `orders/*`, `tutorial/*` | `character` | `character.<characterId>.name` | `character` |
| `asset_manifest.json` | `assets[].appName` | (Anzeige über obige Item/Generator/Element-Keys) | — |

## Beispiele

- Auftrag `order_06` Dialog → `order.order_06.dialog`
- Item `chain2_bar_5_coconut_drink` Name → `item.chain2_bar_5_coconut_drink.name`
- Generator `gen3_surf_locker` Name → `generator.gen3_surf_locker.name`
- Element `elem_counter` Name → `restorationElement.elem_counter.name`
- Tutorial-Schritt `tut_04` Text → `tutorial.tut_04.text`

## Zahlen & Plurale

Zahlen werden **nie** in die Strings gebacken, sondern als Platzhalter geliefert
(`{count}`, `{max}`, `{amount}`, `{name}`). Zählbare Größen nutzen die Plural-Sektion
`plural.*` mit CLDR-Kategorien (`one`/`other`), z. B. `plural.coins`, `plural.gems`,
`plural.stars`, `plural.days`. Beispiel Laufzeit:

- Belohnung „+150 Münzen": `plural.coins.other` mit `{count}=150` → „150 Münzen" /
  „150 coins".
- „1 Edelstein": `plural.gems.one` mit `{count}=1` → „1 Edelstein" / „1 gem".

## Vollständigkeit

`de.json` und `en.json` enthalten identische Schlüsselmengen: **30** Auftragsdialoge,
**11** Tutorial-Texte, **40** Item-Namen, **5** Generatoren, **9** Restaurierungs-Elemente,
**3** Zustände, **4** Figuren sowie `common`/`plural`/`hud`. Ein CI-Check sollte die
Schlüsselparität beider Dateien erzwingen (fehlende/überzählige Keys = Build-Fehler).
