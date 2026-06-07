import SwiftUI

// MARK: - Status-Modelle (/api/status, /api/status-log)
struct ServiceStatus: Codable, Hashable {
    let ok: Bool
    let error: String?
}
struct SystemStatus: Codable {
    let spotify: ServiceStatus
    let deezer: ServiceStatus
    let navidrome: ServiceStatus
    let youtube: ServiceStatus
}
struct StatusLogItem: Codable, Identifiable {
    let ts: Int
    let sp: Bool?; let dz: Bool?; let nv: Bool?; let yt: Bool?
    let sp_err: String?; let dz_err: String?; let nv_err: String?; let yt_err: String?
    var id: Int { ts }
}
struct StatusLogResponse: Codable { let items: [StatusLogItem] }

// MARK: - Admin-/Wartungs-Konsole (nur fuer Admins der eigenen Instanz)
struct AdminConsoleView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var status: SystemStatus?
    @State private var logItems: [StatusLogItem] = []
    @State private var loading = true
    @State private var busy = false
    @State private var toast = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Dienst-Status
                    SettingsGroup("STATUS") {
                        if let s = status {
                            statusRow("Spotify", "spotify", s.spotify)
                            statusRow("Deezer", "deezer", s.deezer)
                            statusRow("Navidrome", "navidrome", s.navidrome)
                            statusRow("YouTube", "youtube", s.youtube)
                        } else if loading {
                            LoadingView()
                        } else {
                            Text("Status nicht abrufbar.").font(.system(size: 14)).foregroundStyle(Theme.mute)
                        }
                    }

                    // Befehle
                    SettingsGroup("BEFEHLE") {
                        Button {
                            Task {
                                busy = true
                                let ok = await app.api.refreshCookies()
                                toast = ok ? "Cookie-Erneuerung gestartet ✓" : "Fehlgeschlagen"
                                busy = false
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                await reload()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if busy { ProgressView().tint(.black) }
                                else { Image(systemName: "key.horizontal") }
                                Text("Spotify-Cookie erneuern").font(.system(size: 15, weight: .semibold))
                                Spacer()
                            }.foregroundStyle(.black).padding(.vertical, 11).padding(.horizontal, 14)
                                .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(busy)
                        Text("Stößt die sp_dc-Erneuerung auf DIESEM Server an (cookie-keeper).")
                            .font(.caption2).foregroundStyle(Theme.mute)
                    }

                    // Debug / Wartung
                    SettingsGroup("DEBUG / WARTUNG") {
                        debugButton("Discover-Server neustarten", icon: "arrow.clockwise.circle") { await doRestart("gallien-discover") }
                        debugButton("Caches leeren", icon: "trash") { await doClearCache() }
                        Menu {
                            ForEach(["deemix", "navidrome", "jellyfin", "gallienbot", "sabnzbd"], id: \.self) { svc in
                                Button(svc) { Task { await doRestart(svc) } }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "square.stack.3d.up")
                                Text("Anderen Dienst neustarten").font(.system(size: 15, weight: .semibold))
                                Spacer()
                            }.foregroundStyle(Theme.text).padding(.vertical, 11).padding(.horizontal, 14)
                                .background(Theme.input).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Text("Bei Haengern hilft meist „Discover neustarten". „Caches leeren" erzwingt frische Daten.")
                            .font(.caption2).foregroundStyle(Theme.mute)
                    }

                    // Log (letzte Statusaenderungen)
                    SettingsGroup("VERLAUF (letzte Änderungen)") {
                        if logItems.isEmpty {
                            Text("Keine Einträge.").font(.system(size: 14)).foregroundStyle(Theme.mute)
                        } else {
                            ForEach(logItems.prefix(20)) { it in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tsText(it.ts)).font(.caption2).foregroundStyle(Theme.mute)
                                    HStack(spacing: 10) {
                                        logDot("SP", it.sp); logDot("DZ", it.dz)
                                        logDot("NV", it.nv); logDot("YT", it.yt)
                                    }
                                    if let e = firstErr(it) {
                                        Text(e).font(.caption2).foregroundStyle(Color(hex6: 0xFF6B6B)).lineLimit(1)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                                Divider().background(Theme.input)
                            }
                        }
                    }
                }.padding(.vertical, 16)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Konsole").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.foregroundStyle(Theme.accent) }
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() }.foregroundStyle(Theme.accent) }
            }
            .overlay(alignment: .bottom) {
                if !toast.isEmpty {
                    Text(toast).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.accent).clipShape(Capsule()).padding(.bottom, 24)
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        status = await app.api.systemStatus()
        logItems = await app.api.statusLog()
        loading = false
    }
    @ViewBuilder private func debugButton(_ title: String, icon: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
            }.foregroundStyle(Theme.text).padding(.vertical, 11).padding(.horizontal, 14)
                .background(Theme.input).clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(busy)
    }
    private func doRestart(_ svc: String) async {
        busy = true
        let ok = await app.api.adminRestart(service: svc)
        toast = ok ? "\(svc) wird neugestartet…" : "Neustart fehlgeschlagen"
        busy = false
        try? await Task.sleep(nanoseconds: 1_800_000_000); toast = ""
    }
    private func doClearCache() async {
        busy = true
        let ok = await app.api.adminClearCache()
        toast = ok ? "Caches geleert ✓" : "Fehlgeschlagen"
        busy = false
        try? await Task.sleep(nanoseconds: 1_500_000_000); toast = ""
    }
    @ViewBuilder private func statusRow(_ name: String, _ key: String, _ s: ServiceStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Circle().fill(s.ok ? Theme.accent : Color(hex6: 0xFF3B30)).frame(width: 10, height: 10)
                Text(name).font(.system(size: 15)).foregroundStyle(Theme.text)
                Spacer()
                Text(s.ok ? "OK" : (s.error ?? "Fehler")).font(.system(size: 12))
                    .foregroundStyle(s.ok ? Theme.sub : Color(hex6: 0xFF6B6B)).lineLimit(1)
            }
            if !s.ok {
                Text(fixHint(key)).font(.system(size: 12)).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20).padding(.trailing, 4)
            }
        }.padding(.vertical, 4)
    }
    /// Was tun, wenn ein Dienst rot ist (für Selfhoster — so einfach wie möglich).
    private func fixHint(_ key: String) -> String {
        switch key {
        case "spotify":
            return "→ sp_dc-Cookie erneuern: bei open.spotify.com einloggen, Entwicklertools (F12) → Application → Cookies → 'sp_dc' kopieren → in Discover unter Einstellungen → Spotify-Cookie einfügen. (Oder unten 'Cookie erneuern'.)"
        case "deezer":
            return "→ Deezer-ARL abgelaufen: bei deezer.com einloggen, Cookie 'arl' kopieren und serverseitig hinterlegen."
        case "navidrome":
            return "→ Navidrome nicht erreichbar: läuft der Navidrome-Container? NAVIDROME_URL/USER/PASS prüfen."
        case "youtube":
            return "→ YouTube-Cookies abgelaufen: cookies.txt neu exportieren (Browser-Erweiterung) und als YT_COOKIE_FILE hinterlegen."
        default: return ""
        }
    }
    @ViewBuilder private func logDot(_ l: String, _ ok: Bool?) -> some View {
        HStack(spacing: 3) {
            Circle().fill((ok ?? true) ? Theme.accent : Color(hex6: 0xFF3B30)).frame(width: 7, height: 7)
            Text(l).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.sub)
        }
    }
    private func firstErr(_ it: StatusLogItem) -> String? {
        for e in [it.sp_err, it.dz_err, it.nv_err, it.yt_err] { if let e, !e.isEmpty { return e } }
        return nil
    }
    private func tsText(_ ts: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "d. MMM HH:mm"
        return f.string(from: d)
    }
}
