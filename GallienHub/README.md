# Gallien Hub für iOS

Native SwiftUI-Hülle für das Gallien Hub. Die App verwendet eine normale `WKWebView` und benötigt keine privaten oder ungewöhnlichen Entitlements.

## Anmeldung

Der zentrale Login wird in Apples sicherem System-Anmeldedialog geöffnet. Dort werden Benutzername und Passwort eingegeben. Nach erfolgreicher Anmeldung erhält die App nur ein kurzlebiges Einmal-Ticket; das Passwort ist für die App niemals sichtbar. Die `WKWebView` verwendet einen dauerhaften Datenspeicher, damit Hub- und App-Sitzungen auch nach einem Neustart der App erhalten bleiben.

## Lockscreen-Mitteilungen

Die App meldet neue kritische Hinweise und Warnungen lokal auf dem Sperrbildschirm. Die Aktion „Im Kontrollzentrum öffnen“ springt direkt zur passenden Hub-Ansicht. Im Vordergrund übernimmt die Web-App die aktuellen Ereignisse; im Hintergrund bittet die App iOS regelmäßig um ein kurzes Aktualisierungsfenster. iOS bestimmt den genauen Zeitpunkt dieser Hintergrundprüfungen, daher sind sie nicht sekundengenau.

Die Lösung benötigt keine Push-, Widget- oder Live-Activity-Erweiterung und bleibt dadurch mit einer sideloaded Signulous-App kompatibel. Beim ersten Start müssen Mitteilungen erlaubt werden.

## Adressen

- Tailscale: `https://gallien.tail24f6af.ts.net:8443/`
- Heimnetz: `http://192.168.2.14:1111/`

Tailscale ist der Standard. Falls es nicht erreichbar ist, bietet die Fehleransicht den Heimnetz-Zugang an.

## Build

GitHub Actions erzeugt eine unsignierte `GallienHub.ipa`. Diese wird anschließend mit dem vorhandenen Signulous-Zertifikat und einem Profil für die Bundle-ID `com.gallien.hub` signiert.

