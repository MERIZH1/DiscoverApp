# Gallien Hub für iOS

Native SwiftUI-Hülle für das Gallien Hub. Die App verwendet eine normale `WKWebView` und benötigt keine privaten oder ungewöhnlichen Entitlements.

## Anmeldung

Der zentrale Login wird in Apples sicherem System-Anmeldedialog geöffnet. Authentik kann dort Passkeys/Face ID und seine vorhandene SSO-Sitzung verwenden. Nach erfolgreicher Anmeldung erhält die App nur ein kurzlebiges Einmal-Ticket; das Passwort und der Passkey sind für die App niemals sichtbar.

## Adressen

- Tailscale: `https://gallien.tail24f6af.ts.net:8443/`
- Heimnetz: `http://192.168.2.14:1111/`

Tailscale ist der Standard. Falls es nicht erreichbar ist, bietet die Fehleransicht den Heimnetz-Zugang an.

## Build

GitHub Actions erzeugt eine unsignierte `GallienHub.ipa`. Diese wird anschließend mit dem vorhandenen Signulous-Zertifikat und einem Profil für die Bundle-ID `com.gallien.hub` signiert.

