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

// MARK: - Konsole 2.0 (Logs / Ressourcen / Statistik / Token-Alter)
struct LogItem: Codable, Identifiable {
    let time: String; let level: String; let text: String
    var id: String { time + "|" + text }
}
struct LogsResponse: Codable { let items: [LogItem] }
struct ContainerStat: Codable, Identifiable {
    let name: String; let cpu: String; let mem: String
    var id: String { name }
}
struct ResourcesResponse: Codable { let containers: [ContainerStat] }
struct TokenInfo: Codable, Identifiable {
    let name: String; let age_days: Double?
    var id: String { name }
}
struct TokensResponse: Codable { let tokens: [TokenInfo] }
struct StatsResponse: Codable { let stats: [String: Int] }
struct DiskInfo: Codable, Identifiable {
    let name: String; let free_gb: Double; let total_gb: Double; let used_pct: Int
    var id: String { name }
}
struct DiskResponse: Codable { let disks: [DiskInfo] }

// MARK: - Admin-/Wartungs-Konsole (nur fuer Admins der eigenen Instanz)
struct AdminConsoleView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var status: SystemStatus?
    @State private var logItems: [StatusLogItem] = []
    @State private var loading = true
    @State private var busy = false
    @State private var toast = ""
    @State private var showLogs = false
    @State private var logs: [LogItem] = []
    @State private var resources: [ContainerStat] = []
    @State private var stats: [String: Int] = [:]
    @State private var tokens: [TokenInfo] = []
    @State private var disks: [DiskInfo] = []
    @AppStorage("serverAlerts") private var serverAlerts = true

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
                        Text("Bei Haengern hilft meist Discover neustarten. Caches leeren erzwingt frische Daten.")
                            .font(.caption2).foregroundStyle(Theme.mute)
                    }

                    SettingsGroup("SERVER-LOGS") {
                        debugButton("Logs anzeigen (Klartext)", icon: "doc.text.magnifyingglass") { await loadAndShowLogs() }
                        Text("Was der Server gerade tut — verstaendlich aufbereitet.")
                            .font(.caption2).foregroundStyle(Theme.mute)
                    }

                    SettingsGroup("SYNC & CACHE") {
                        debugButton("Alle Playlists synchronisieren", icon: "arrow.triangle.2.circlepath") { await doSyncAll() }
                        Text("Einzelne Caches leeren:").font(.caption2).foregroundStyle(Theme.mute).padding(.top, 2)
                        HStack(spacing: 8) {
                            cacheChip("Playlists", "playlists")
                            cacheChip("Home", "home")
                            cacheChip("Empfehlungen", "recs")
                        }
                    }

                    if !stats.isEmpty {
                        SettingsGroup("STATISTIK") {
                            statRow("Abos (Playlists)", stats["abos"])
                            statRow("Radios", stats["radios"])
                            statRow("Navidrome-Songs", stats["navidrome_songs"])
                            statRow("Playlists gecacht", stats["playlists_gecacht"])
                            statRow("Empfehlungen gecacht", stats["empfehlungen_gecacht"])
                        }
                    }

                    if !resources.isEmpty {
                        SettingsGroup("RESSOURCEN") {
                            ForEach(resources) { c in
                                HStack {
                                    Text(c.name).font(.system(size: 13)).foregroundStyle(Theme.text).lineLimit(1)
                                    Spacer()
                                    Text("CPU \(c.cpu)").font(.system(size: 12)).foregroundStyle(Theme.sub)
                                    Text(c.mem).font(.system(size: 11)).foregroundStyle(Theme.mute).lineLimit(1)
                                }.padding(.vertical, 2)
                            }
                        }
                    }

                    if !tokens.isEmpty {
                        SettingsGroup("LOGIN-DATEN (Alter)") {
                            ForEach(tokens) { t in
                                HStack {
                                    Text(t.name).font(.system(size: 14)).foregroundStyle(Theme.text)
                                    Spacer()
                                    Text(tokenAge(t.age_days)).font(.system(size: 13, weight: .semibold)).foregroundStyle(tokenColor(t.age_days))
                                }.padding(.vertical, 3)
                            }
                            Text("Alte Cookies sind oft der Vorbote von Aussetzern — bei Problemen erneuern.")
                                .font(.caption2).foregroundStyle(Theme.mute)
                        }
                    }

                    if !disks.isEmpty {
                        SettingsGroup("SPEICHER") {
                            ForEach(disks) { d in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(d.name).font(.system(size: 13)).foregroundStyle(Theme.text)
                                        Spacer()
                                        Text("\(String(format: "%.0f", d.free_gb)) frei / \(String(format: "%.0f", d.total_gb)) GB")
                                            .font(.system(size: 12)).foregroundStyle(Theme.sub)
                                    }
                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Theme.input).frame(height: 6)
                                            Capsule().fill(diskColor(d.used_pct))
                                                .frame(width: max(4, g.size.width * CGFloat(d.used_pct) / 100), height: 6)
                                        }
                                    }.frame(height: 6)
                                }.padding(.vertical, 3)
                            }
                        }
                    }

                    SettingsGroup("NOTFALL") {
                        debugButton("Alle Dienste neustarten", icon: "exclamationmark.arrow.circlepath") { await restartAll() }
                        Text("Startet deemix, navidrome, jellyfin, bot, sabnzbd + Discover neu.")
                            .font(.caption2).foregroundStyle(Theme.mute)
                    }

                    SettingsGroup("BENACHRICHTIGUNGEN") {
                        Toggle(isOn: $serverAlerts) {
                            Text("Bei Server-Problemen benachrichtigen")
                                .font(.system(size: 15)).foregroundStyle(Theme.text)
                        }.tint(Theme.accent)
                        Text("Lokale Mitteilung, wenn ein Dienst ausfaellt — im Vordergrund sofort, im Hintergrund wann iOS es zulaesst (kein Push-Server noetig).")
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
        .sheet(isPresented: $showLogs) { LogsSheet(items: logs) }
    }

    private func reload() async {
        loading = true
        status = await app.api.systemStatus()
        logItems = await app.api.statusLog()
        loading = false
        // Konsolen-Daten im Hintergrund nachladen (blockieren den Status nicht)
        resources = await app.api.adminResources()
        stats = await app.api.adminStats()
        tokens = await app.api.adminTokens()
        disks = await app.api.adminDisk()
    }
    private func restartAll() async {
        busy = true
        for svc in ["deemix", "navidrome", "jellyfin", "gallienbot", "sabnzbd"] {
            _ = await app.api.adminRestart(service: svc)
        }
        toast = "Dienste neugestartet — Discover folgt…"
        _ = await app.api.adminRestart(service: "gallien-discover")
        let back = await app.api.waitUntilUp()
        toast = back ? "Alles neugestartet ✓" : "Neugestartet — Status unklar"
        busy = false
        try? await Task.sleep(nanoseconds: 2_500_000_000); toast = ""
    }
    private func diskColor(_ pct: Int) -> Color {
        pct >= 90 ? Color(hex6: 0xFF3B30) : (pct >= 75 ? Color(hex6: 0xFF9500) : Theme.accent)
    }
    private func doSyncAll() async {
        busy = true
        let n = await app.api.adminSyncAll()
        toast = n >= 0 ? "\(n) Playlists werden synchronisiert…" : "Sync fehlgeschlagen"
        busy = false
        try? await Task.sleep(nanoseconds: 2_000_000_000); toast = ""
    }
    private func loadAndShowLogs() async {
        logs = await app.api.adminLogs()
        showLogs = true
    }
    private func clearOne(_ label: String, _ key: String) {
        Task {
            _ = await app.api.adminClearCache(which: [key])
            toast = "\(label)-Cache geleert ✓"
            try? await Task.sleep(nanoseconds: 1_500_000_000); toast = ""
        }
    }
    private func tokenAge(_ d: Double?) -> String {
        guard let d = d else { return "—" }
        return d < 1 ? "heute" : "vor \(Int(d)) Tagen"
    }
    private func tokenColor(_ d: Double?) -> Color {
        guard let d = d else { return Theme.sub }
        return d > 25 ? Color(hex6: 0xFF9500) : Theme.sub
    }
    @ViewBuilder private func cacheChip(_ label: String, _ key: String) -> some View {
        Button { clearOne(label, key) } label: {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.input).clipShape(Capsule())
        }.buttonStyle(.plain)
    }
    @ViewBuilder private func statRow(_ label: String, _ v: Int?) -> some View {
        if let v = v {
            HStack {
                Text(label).font(.system(size: 14)).foregroundStyle(Theme.text)
                Spacer()
                Text("\(v)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
            }.padding(.vertical, 3)
        }
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
        if svc == "gallien-discover" {
            // Selbst-Neustart: Verbindung bricht ab -> warten bis der Server wieder antwortet
            toast = "Discover startet neu…"
            let back = await app.api.waitUntilUp()
            toast = back ? "Discover läuft wieder ✓" : "Neustart angestossen — Status unklar"
            if back { await reload() }
        } else {
            toast = ok ? "\(svc) wird neugestartet…" : "Neustart fehlgeschlagen"
        }
        busy = false
        try? await Task.sleep(nanoseconds: 2_500_000_000); toast = ""
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

// MARK: - Server-Logs (Klartext, farbcodiert nach Schwere)
struct LogsSheet: View {
    let items: [LogItem]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if items.isEmpty {
                        Text("Keine Eintraege.").font(.system(size: 14)).foregroundStyle(Theme.mute)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    ForEach(items.reversed()) { it in   // neueste oben
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(color(it.level)).frame(width: 8, height: 8).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(it.text).font(.system(size: 14)).foregroundStyle(Theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !it.time.isEmpty {
                                    Text(it.time).font(.caption2).foregroundStyle(Theme.mute)
                                }
                            }
                            Spacer(minLength: 0)
                        }.padding(.horizontal).padding(.vertical, 7)
                        Divider().background(Theme.input)
                    }
                }.padding(.vertical, 8)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Server-Logs").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: items.map { "[\($0.level)] \($0.time) \($0.text)" }.joined(separator: "\n")) {
                        Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.accent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
    }
    private func color(_ lvl: String) -> Color {
        switch lvl {
        case "err":  return Color(hex6: 0xFF3B30)
        case "warn": return Color(hex6: 0xFF9500)
        case "ok":   return Theme.accent
        default:     return Theme.sub
        }
    }
}
