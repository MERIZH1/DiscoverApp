# Sunny Cove

Native SwiftUI-iOS-App für ein datengetriebenes Merge-Spiel.

## Asset-Paket einbinden

Das fertige Paket von Claude liegt standardmäßig unter
`C:\Users\maxgl\Desktop\SunnyCoveAssets`. Vor dem ersten Xcode-Build im Projektordner
ausführen:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\import-assets.ps1
```

Die Dateien sind in diesem Arbeitsstand bereits unter `Resources/GameContent`
übernommen. Das Skript ist für einen erneuten Import nach neuen Claude-Assets
gedacht. Ohne Asset-Import startet die App weiterhin mit den eingebauten
Fallback-Daten und Emoji-Platzhaltern.

## Entwicklung

Das Xcode-Projekt wird mit XcodeGen aus `project.yml` erzeugt. Die CI baut eine
unsignierte IPA für interne Tests:

```bash
brew install xcodegen
xcodegen generate
xcodebuild test -project SunnyCove.xcodeproj -scheme SunnyCove \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO
```

Die Signierung und der App-Store-Upload kommen erst nach echten Playtests.

## Inhalts-Updates

Für einen späteren Live-Kanal wird `ContentManifestURL` in `Supporting/Info.plist`
auf das veröffentlichte `content-manifest.json` gesetzt. Die App lädt daraus nur
versionierte JSON-/SVG-Dateien, prüft echte SHA-256-Hashes und ersetzt die Inhalte
atomar. Ohne gesetzte URL bleibt die Beta offline und verwendet die gebündelten
Inhalte.
