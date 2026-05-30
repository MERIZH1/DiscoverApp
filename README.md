# DiscoverApp (native iOS-Huelle)

Duenne native iOS-App, die die **Discover-Web-App** in einer `WKWebView` laedt —
aber mit **nativer Audio-Session**. Damit laeuft Audio im **Hintergrund + Lock-Screen**
(echte Play/Pause/Next-Steuerung), was eine reine PWA auf iOS nicht darf.

- Beim ersten Start: **Server-Adresse eingeben** (z.B. deine Tailscale-IP `http://100.x.x.x:5555`).
  Aenderbar ueber das Zahnrad oben rechts.
- Background-Audio via `AVAudioSession(.playback)` + `UIBackgroundModes: audio`.
- Lock-Screen-Buttons via `MPRemoteCommandCenter` -> rufen die Web-Funktionen
  (`__nativePlay/Pause/Next/Prev`). Now-Playing-Infos kommen per JS-Bruecke aus der Web-App.

## Bauen OHNE Mac (GitHub Actions, 0 EUR)

1. Diesen Ordner als **GitHub-Repo** pushen (Branch `main`).
2. GitHub baut automatisch (Workflow `.github/workflows/build-ipa.yml`) — oder im
   Tab **Actions** manuell **"Build unsigned IPA" -> Run workflow** starten.
3. Nach ~3-5 Min: im Action-Run unter **Artifacts** die **`DiscoverApp-unsigned-ipa`**
   herunterladen und entpacken -> `DiscoverApp-unsigned.ipa`.

> Der macOS-Runner kompiliert in der Cloud. Du brauchst keinen Mac.

## Aufs iPhone bringen (Sideloadly, gratis Apple-ID)

1. **Sideloadly** (Windows/Mac) installieren: https://sideloadly.io
2. iPhone per USB anstecken, in Sideloadly waehlen.
3. Die `DiscoverApp-unsigned.ipa` reinziehen.
4. Deine **Apple-ID** eintragen (eine kostenlose reicht) -> **Start**.
   Sideloadly signiert + installiert. Beim ersten Start am iPhone unter
   **Einstellungen -> Allgemein -> VPN & Geraeteverwaltung** den Entwickler **vertrauen**.

> Mit gratis Apple-ID laeuft die Signatur **7 Tage** -> danach neu signieren.
> Das automatisiert SideStore (siehe unten).

## Dauerhaft signiert halten (SideStore)

1. **SideStore** einrichten: https://sidestore.io (Anleitung dort).
   Einmaliges Pairing (Pairing-File) noetig.
2. App ueber SideStore installieren bzw. importieren.
3. SideStore **re-signiert automatisch im Hintergrund** (haelt die 7-Tage-Signatur
   frisch), solange es gelegentlich seinen Refresh machen kann.

## Lokal mit Mac bauen (optional)

```bash
brew install xcodegen
xcodegen generate
open DiscoverApp.xcodeproj   # in Xcode signieren + auf Geraet laufen lassen
```

## Struktur

```
project.yml                      # XcodeGen-Spec (erzeugt das .xcodeproj)
Sources/
  DiscoverApp.swift              # @main App, aktiviert AVAudioSession(.playback)
  ContentView.swift              # Server-Adress-Eingabe + Zahnrad
  WebContainerView.swift         # WKWebView + MPRemoteCommandCenter-Bruecke
  Info.plist                     # UIBackgroundModes: audio, ATS (http erlaubt)
.github/workflows/build-ipa.yml  # CI: baut unsignierte .ipa
```

## Hinweise

- **HTTP erlaubt:** `NSAllowsArbitraryLoads` ist an, weil Tailscale-IPs `http` sind.
- **Bundle-ID** `com.discover.app` — bei Bedarf in `project.yml` aendern (z.B. wenn
  die ID schon vergeben ist beim Signieren).
- Die App ist nur eine Huelle — **alle Updates der Web-App** (app.js etc.) kommen
  weiter vom Server, **ohne** die App neu zu bauen. Neu bauen nur bei Aenderung am
  Swift-Code.
