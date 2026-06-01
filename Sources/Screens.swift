import SwiftUI
import UIKit

// Wisch-zurueck-Geste IMMER erlauben — auch bei eigenem/verstecktem Back-Button.
extension UINavigationController: UIGestureRecognizerDelegate {
    open override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

// MARK: - Haptik
enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Appearance
func configureAppearance() {
    let nav = UINavigationBarAppearance()
    nav.configureWithOpaqueBackground()
    nav.backgroundColor = .black; nav.shadowColor = .clear
    nav.titleTextAttributes = [.foregroundColor: UIColor.white]
    nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
    // Zurueck-Button: nur Pfeil, kein Text (wie PWA)
    let back = UIBarButtonItemAppearance(style: .plain)
    back.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
    back.highlighted.titleTextAttributes = [.foregroundColor: UIColor.clear]
    back.focused.titleTextAttributes = [.foregroundColor: UIColor.clear]
    back.disabled.titleTextAttributes = [.foregroundColor: UIColor.clear]
    nav.backButtonAppearance = back
    UINavigationBar.appearance().tintColor = .white
    UINavigationBar.appearance().standardAppearance = nav
    UINavigationBar.appearance().scrollEdgeAppearance = nav
    UINavigationBar.appearance().compactAppearance = nav
    let tab = UITabBarAppearance()
    tab.configureWithOpaqueBackground()
    tab.backgroundColor = .black; tab.shadowColor = .clear
    UITabBar.appearance().standardAppearance = tab
    UITabBar.appearance().scrollEdgeAppearance = tab
}

/// Durchschnittsfarbe eines Covers (fuer den Playlist-Hero-Verlauf wie in der PWA).
func averageColor(_ urlStr: String?) async -> Color? {
    guard let s = urlStr, let u = URL(string: s),
          let (d, _) = try? await URLSession.shared.data(from: u),
          let cg = UIImage(data: d)?.cgImage else { return nil }
    var px = [UInt8](repeating: 0, count: 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8,
                              bytesPerRow: 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .low
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return Color(red: Double(px[0]) / 255, green: Double(px[1]) / 255, blue: Double(px[2]) / 255)
}

// MARK: - Main
struct MainView: View {
    @EnvironmentObject var player: PlayerController
    @State private var showPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                HomeView().tabItem { Label("Home", systemImage: "house.fill") }
                SearchView().tabItem { Label("Suchen", systemImage: "magnifyingglass") }
                LibraryView().tabItem { Label("Bibliothek", systemImage: "books.vertical.fill") }
                RadioView().tabItem { Label("Radio", systemImage: "dot.radiowaves.left.and.right") }
            }
            .tint(Theme.text)
            if player.hasContent {
                NowPlayingBar(showPlayer: $showPlayer).padding(.horizontal, 8).padding(.bottom, 50)
            }
        }
        .onAppear(perform: configureAppearance)
        .sheet(isPresented: $showPlayer) { PlayerView() }
    }
}

// MARK: - Pills
struct Pill: View {
    let text: String
    let active: Bool
    var activeBg: Color = .white
    var icon: String? = nil
    let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(text).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(active ? .black : Theme.text)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(active ? activeBg : Theme.input)
            .clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}

// MARK: - Track-Kontextmenue (Long-Press + "…")
struct TrackMenu: View {
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var app: AppState
    let track: Track
    var body: some View {
        Button { player.playNext(track) } label: { Label("Als Nächstes spielen", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { player.addToQueue(track) } label: { Label("Zur Warteschlange", systemImage: "text.badge.plus") }
        Button { startRadio() } label: { Label("Song-Radio starten", systemImage: "dot.radiowaves.left.and.right") }
    }
    private func startRadio() {
        Task {
            guard let r = try? await app.api.startRadio(track: track), r.ok,
                  let puri = r.playlist_uri,
                  let resp = try? await app.api.playlistTracks(puri) else { return }
            player.play(tracks: resp.tracks)
        }
    }
}

// MARK: - Account-Avatar
struct AvatarCircle: View {
    let name: String
    var size: CGFloat = 38
    var body: some View {
        let letter = String(name.prefix(1)).uppercased()
        Circle()
            .fill(LinearGradient(colors: [Color(hex6: 0xCBA552), Color(hex6: 0x7E6326)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Text(letter.isEmpty ? "?" : letter)
                .font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white))
    }
}

// MARK: - Home
struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var home: HomeResponse?
    @State private var recents: [HomeItem] = []
    @State private var filter = "all"
    @State private var showAccount = false

    private var greetingText: String {
        let g = home?.greeting ?? "Hallo"
        let n = home?.user_name ?? app.profile?.name ?? ""
        return n.isEmpty ? g : "\(g) \(n)"
    }
    private var quick: [HomeItem] {
        let q = home?.quick ?? []
        return filter == "all" ? q : q.filter { ($0.type ?? "") == filter }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Header
                    HStack(alignment: .center) {
                        Text(greetingText).font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(Theme.text).lineLimit(2)
                        Spacer(minLength: 8)
                        Button { showAccount = true } label: {
                            AvatarCircle(name: app.profile?.name ?? "?")
                        }.buttonStyle(.plain)
                    }.padding(.horizontal).padding(.top, 8)

                    // Filter-Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([("all","Alle"),("playlist","Playlists"),("artist","Künstler*innen"),("album","Alben")], id: \.0) { f in
                                Pill(text: f.1, active: filter == f.0) { filter = f.0 }
                            }
                        }.padding(.horizontal)
                    }

                    // Quick-Grid (4x2)
                    if home == nil {
                        ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(quick) { item in
                                NavigationLink(value: item) {
                                    HStack(spacing: 12) {
                                        Artwork(url: item.image, size: 56, corner: 0)
                                        Text(item.name).font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(Theme.text).lineLimit(2)
                                            .multilineTextAlignment(.leading).padding(.trailing, 12)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56, alignment: .leading)
                                    .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 6))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal)
                    }

                    // Zuletzt geoeffnet
                    if !recents.isEmpty {
                        HomeRow(title: "Zuletzt geöffnet", subtitle: nil, items: recents)
                    }
                    // Spotify-Home-Sektionen (Fuer dich erstellt, Empfohlene Sender, …)
                    ForEach(home?.sections ?? []) { sec in
                        HomeRow(title: sec.title, subtitle: sec.subtitle, items: sec.items)
                    }
                }.padding(.bottom, 130)
            }
            .scrollContentBackground(.hidden)
            .background(
                ZStack {
                    Theme.bg
                    LinearGradient(stops: [
                        .init(color: Color(red: 70/255, green: 90/255, blue: 120/255).opacity(0.35), location: 0),
                        .init(color: .clear, location: 0.33)],
                        startPoint: .top, endPoint: .bottom)
                }.ignoresSafeArea()
            )
            .navigationBarHidden(true)
            .navigationDestination(for: HomeItem.self) { item in
                if (item.type ?? "") == "show" || item.uri.contains(":show:") {
                    PodcastView(uri: item.uri, title: item.name, image: item.image)
                } else {
                    TrackListView(uri: item.uri, title: item.name, image: item.image, isAlbum: item.type == "album")
                }
            }
        }
        .sheet(isPresented: $showAccount) { AccountSheet() }
        .task {
            // 1) Cache sofort zeigen
            if home == nil { home = app.cacheGet("home", HomeResponse.self) }
            if recents.isEmpty { recents = app.cacheGet("recents", [HomeItem].self) ?? [] }
            // 2) Frisch nachladen + Cache aktualisieren (taucht beim Zurueckkommen auf)
            if let h = try? await app.api.home() { home = h; app.cacheSet("home", h) }
            if let r = try? await app.api.recents() { recents = r; app.cacheSet("recents", r) }
        }
    }
}

/// Horizontale Reihe grosser Cover-Karten (Home-Sektion).
struct HomeRow: View {
    let title: String
    let subtitle: String?
    let items: [HomeItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.sub)
            }.padding(.horizontal)
            if let s = subtitle, !s.isEmpty {
                Text(s).font(.system(size: 13)).foregroundStyle(Theme.sub)
                    .lineLimit(2).padding(.horizontal)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(items) { it in
                        NavigationLink(value: it) { BigCard(item: it) }.buttonStyle(.plain)
                    }
                }.padding(.horizontal)
            }
        }
    }
}

struct BigCard: View {
    let item: HomeItem
    var body: some View {
        let circle = (item.type ?? "") == "artist"
        VStack(alignment: .leading, spacing: 6) {
            Artwork(url: item.image, size: 150, corner: circle ? 75 : 6)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 8)
            Text(item.name).font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.text).lineLimit(1)
            if let sub = item.sub, !sub.isEmpty {
                Text(sub).font(.system(size: 12)).foregroundStyle(Theme.sub).lineLimit(1)
            }
        }.frame(width: 150, alignment: .leading)
    }
}

// MARK: - Account
struct AccountSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var profiles: [Profile] = []
    @State private var showSettings = false

    private var isAdmin: Bool { app.profile?.is_admin == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        AvatarCircle(name: app.profile?.name ?? "?", size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.profile?.name ?? "Profil").font(.title3.bold()).foregroundStyle(Theme.text)
                            Text(isAdmin ? "Admin" : "User").font(.caption).foregroundStyle(Theme.accent)
                        }
                    }.padding(.horizontal).padding(.top, 8).padding(.bottom, 6)

                    if profiles.count > 1 {
                        AccountHeader("PROFIL WECHSELN")
                        ForEach(profiles) { p in
                            Button { app.switchProfile(p); dismiss() } label: {
                                HStack(spacing: 12) {
                                    AvatarCircle(name: p.name, size: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(p.name).font(.system(size: 16)).foregroundStyle(Theme.text)
                                        Text(p.is_admin == true ? "Admin" : "User").font(.caption2).foregroundStyle(Theme.mute)
                                    }
                                    Spacer()
                                    if p.id == app.profile?.id {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }.padding(.vertical, 8).padding(.horizontal).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }

                    Divider().background(Theme.input).padding(.vertical, 8)
                    AccountAction(icon: "gearshape.fill", label: "Einstellungen") { showSettings = true }
                    AccountAction(icon: "person.2.fill", label: "Profil abmelden") { app.clearProfile(); dismiss() }

                    AccountHeader("SERVER")
                    ForEach(app.savedServers, id: \.self) { s in
                        Button { Task { await app.switchServer(s); dismiss() } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "server.rack").frame(width: 24).foregroundStyle(Theme.sub)
                                Text(s).font(.system(size: 14)).foregroundStyle(Theme.text).lineLimit(1)
                                Spacer()
                                if s == app.serverURL { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }.padding(.vertical, 8).padding(.horizontal).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    AccountAction(icon: "plus.circle", label: "Server hinzufügen / ändern") { app.changeServer(); dismiss() }

                    if isAdmin {
                        Divider().background(Theme.input).padding(.vertical, 8)
                        AccountHeader("ADMIN — PROFILE")
                        ForEach(profiles) { p in
                            let canPromote = p.is_admin != true
                            let canDemote = p.is_admin == true && p.id != app.profile?.id
                            if canPromote || canDemote {
                                Menu {
                                    if canPromote { Button { promote(p, true) } label: { Label("Zum Admin machen", systemImage: "crown") } }
                                    if canDemote { Button(role: .destructive) { promote(p, false) } label: { Label("Admin-Rechte entfernen", systemImage: "crown") } }
                                } label: { adminRow(p, showMenu: true) }
                            } else {
                                adminRow(p, showMenu: false)
                            }
                        }
                    }

                    Text("Discover · \(AppInfo.version)").font(.caption2).foregroundStyle(Theme.mute)
                        .frame(maxWidth: .infinity).padding(.top, 24)
                }.padding(.bottom, 30)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }.foregroundStyle(Theme.accent)
            } }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { profiles = (try? await app.api.profiles()) ?? [] }
    }

    @ViewBuilder private func adminRow(_ p: Profile, showMenu: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarCircle(name: p.name, size: 32)
            Text(p.name).font(.system(size: 15)).foregroundStyle(Theme.text)
            Spacer()
            Text(p.is_admin == true ? "Admin" : "User").font(.caption2)
                .foregroundStyle(p.is_admin == true ? Theme.accent : Theme.mute)
            Image(systemName: p.has_spotify_cookie == true ? "checkmark.seal.fill" : "xmark.seal")
                .font(.caption).foregroundStyle(p.has_spotify_cookie == true ? Theme.accent : Theme.mute)
            if showMenu { Image(systemName: "ellipsis").font(.caption).foregroundStyle(Theme.sub) }
        }.padding(.vertical, 6).padding(.horizontal).contentShape(Rectangle())
    }

    private func promote(_ p: Profile, _ admin: Bool) {
        Task {
            try? await app.api.updateProfile(p.id, fields: ["is_admin": admin])
            profiles = (try? await app.api.profiles()) ?? profiles
        }
    }
}

struct AccountHeader: View {
    let t: String; init(_ t: String) { self.t = t }
    var body: some View {
        Text(t).font(.caption2.bold()).foregroundStyle(Theme.mute)
            .padding(.horizontal).padding(.top, 8)
    }
}

// MARK: - Einstellungen
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var country = ""
    @State private var hideForeign = false
    @State private var prebuffer = 5
    @State private var normalize = false
    @State private var bgKeepalive = false
    @State private var scEnabled = true
    @State private var scSec = 45
    @State private var scPct = 0
    @State private var scPlays = 4
    @State private var cookie = ""
    @State private var cookieMsg = ""
    @State private var loaded = false

    private let bufferOptions: [(Int, String)] = [
        (0, "Aus"), (2, "2 Songs (~10 MB)"), (5, "5 Songs (~25 MB)"),
        (10, "10 Songs (~50 MB)"), (20, "20 Songs (~100 MB)"),
    ]
    private func bufferLabel(_ n: Int) -> String { bufferOptions.first { $0.0 == n }?.1 ?? "\(n) Songs" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Profil
                    SettingsGroup("PROFIL") {
                        SettingsField(label: "Name", text: $name) { saveProfile() }
                        SettingsField(label: "Land", text: $country, autoCaps: true) { saveProfile() }
                        Toggle(isOn: $hideForeign) {
                            Text("Fremdsprachige Playlists ausblenden").font(.system(size: 15)).foregroundStyle(Theme.text)
                        }.tint(Theme.accent).onChange(of: hideForeign) { _ in if loaded { saveProfile() } }
                    }
                    // Wiedergabe
                    SettingsGroup("WIEDERGABE") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Offline-Buffer").font(.system(size: 15)).foregroundStyle(Theme.text)
                            Text("Songs vorladen für unterbrochene Verbindung").font(.caption2).foregroundStyle(Theme.mute)
                            Menu {
                                ForEach(bufferOptions, id: \.0) { opt in
                                    Button(opt.1) { prebuffer = opt.0; if loaded { saveSettings() } }
                                }
                            } label: {
                                HStack {
                                    Text(bufferLabel(prebuffer)).foregroundStyle(Theme.text)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.sub)
                                }.padding(10).background(Theme.input).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        Toggle(isOn: $normalize) {
                            Text("Lautstärke normalisieren").font(.system(size: 15)).foregroundStyle(Theme.text)
                        }.tint(Theme.accent).onChange(of: normalize) { _ in if loaded { saveSettings() } }
                    }

                    // Auto-Download (Smart-Cache)
                    SettingsGroup("AUTO-DOWNLOAD (SMART-CACHE)") {
                        Toggle(isOn: $scEnabled) {
                            Text("Oft gehörte Songs automatisch auf den Server laden")
                                .font(.system(size: 15)).foregroundStyle(Theme.text)
                        }.tint(Theme.accent).onChange(of: scEnabled) { _ in if loaded { saveSmartCache() } }
                        SCField(label: "...ab so vielen Sekunden gehört (0 = aus)", value: $scSec) { if loaded { saveSmartCache() } }
                        SCField(label: "...ODER ab so viel % der Songlänge (0 = aus)", value: $scPct) { if loaded { saveSmartCache() } }
                        SCField(label: "...ODER nach so vielen Wiedergaben (0 = aus)", value: $scPlays) { if loaded { saveSmartCache() } }
                    }
                    // Spotify-Cookie
                    SettingsGroup("SPOTIFY-COOKIE (sp_dc)") {
                        Text("Cookie-Status: \(app.profile?.has_spotify_cookie == true ? "✓ gesetzt" : "fehlt / abgelaufen")")
                            .font(.system(size: 14)).foregroundStyle(app.profile?.has_spotify_cookie == true ? Theme.accent : Theme.sub)
                        TextField("sp_dc-Wert einfügen", text: $cookie)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .foregroundStyle(Theme.text).padding(10)
                            .background(Theme.input).clipShape(RoundedRectangle(cornerRadius: 8))
                        Button {
                            guard let id = app.profile?.id, !cookie.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            Task {
                                let ok = await app.api.setSpotifyCookie(id, sp_dc: cookie.trimmingCharacters(in: .whitespaces))
                                cookieMsg = ok ? "Gespeichert ✓ — Spotify neu verbunden" : "Fehler beim Speichern"
                                if ok { cookie = ""; if let p = try? await app.api.profiles().first(where: { $0.id == id }) { app.profile = p } }
                            }
                        } label: {
                            Text("Cookie speichern").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        if !cookieMsg.isEmpty { Text(cookieMsg).font(.caption).foregroundStyle(Theme.sub) }
                        Text("sp_dc holst du im Browser: open.spotify.com → eingeloggt → Entwicklertools → Application → Cookies → sp_dc.")
                            .font(.caption2).foregroundStyle(Theme.mute)
                    }

                    Text("Synchronisiert mit deinem Profil (gleiche Werte wie in der PWA).")
                        .font(.caption2).foregroundStyle(Theme.mute).padding(.horizontal)
                }.padding(.vertical, 16)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Einstellungen").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }.foregroundStyle(Theme.accent)
            } }
        }
        .task {
            name = app.profile?.name ?? ""
            country = app.profile?.country ?? "DE"
            hideForeign = app.profile?.hide_foreign_lang_playlists ?? false
            if let s = try? await app.api.settings() {
                prebuffer = s.prebuffer_count ?? 5
                normalize = s.normalize_volume ?? false
                bgKeepalive = s.bg_keepalive ?? false
                if let sc = s.smart_cache {
                    scEnabled = sc.enabled ?? true
                    scSec = sc.min_listened_sec ?? 45
                    scPct = Int(sc.min_listened_pct ?? 0)
                    scPlays = sc.min_play_count ?? 4
                }
            }
            loaded = true
        }
    }

    private func saveProfile() {
        guard loaded, let id = app.profile?.id else { return }
        let fields: [String: Any] = [
            "name": name, "country": country.uppercased(),
            "hide_foreign_lang_playlists": hideForeign,
        ]
        Task {
            if let p = try? await app.api.updateProfile(id, fields: fields) { app.profile = p }
        }
    }
    private func saveSettings() {
        Task {
            await app.api.saveSettings([
                "prebuffer_count": prebuffer,
                "normalize_volume": normalize,
                "bg_keepalive": bgKeepalive,
            ])
        }
    }
    private func saveSmartCache() {
        Task {
            await app.api.saveSettings(["smart_cache": [
                "enabled": scEnabled,
                "min_listened_sec": scSec,
                "min_listened_pct": scPct,
                "min_play_count": scPlays,
            ]])
        }
    }
}

struct SCField: View {
    let label: String; @Binding var value: Int; let commit: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.sub)
            TextField("0", value: $value, format: .number)
                .keyboardType(.numberPad).foregroundStyle(Theme.text).padding(10)
                .background(Theme.input).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onChange(of: value) { _ in commit() }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String; @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.caption2.bold()).foregroundStyle(Theme.mute)
            content
        }
        .padding(16)
        .background(Theme.elev).clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct SettingsField: View {
    let label: String; @Binding var text: String; var autoCaps = false; let commit: () -> Void
    var body: some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(Theme.text)
            Spacer()
            TextField("", text: $text)
                .multilineTextAlignment(.trailing).foregroundStyle(Theme.sub)
                .textInputAutocapitalization(autoCaps ? .characters : .words)
                .autocorrectionDisabled()
                .onSubmit(commit)
                .frame(maxWidth: 180)
        }
    }
}

struct AccountAction: View {
    let icon: String; let label: String; let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 14) {
                Image(systemName: icon).frame(width: 24).foregroundStyle(Theme.sub)
                Text(label).font(.system(size: 16)).foregroundStyle(Theme.text)
                Spacer()
            }.padding(.vertical, 10).padding(.horizontal).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// MARK: - Suche
struct SearchView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    @State private var query = ""
    @State private var res: SearchResponse?
    @State private var scope = "all"
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.black).font(.system(size: 18, weight: .semibold))
                    TextField("", text: $query, prompt: Text("Songs, Künstler suchen…").foregroundColor(Color.black.opacity(0.55)))
                        .foregroundStyle(.black).tint(.black)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .onSubmit { runSearch() }
                    if !query.isEmpty {
                        Button { query = ""; res = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.black.opacity(0.5)) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["all","tracks","playlists","albums","artists","shows"], id: \.self) { s in
                            Pill(text: label(s), active: scope == s) { scope = s }
                        }
                    }.padding(.horizontal)
                }

                ScrollView {
                    if busy { ProgressView().tint(Theme.accent).padding(.top, 40) }
                    else if let r = res {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            if scope == "all" || scope == "tracks", let tracks = r.tracks, !tracks.isEmpty {
                                SectionHeader("Songs")
                                ForEach(Array(tracks.prefix(scope == "tracks" ? 50 : 6).enumerated()), id: \.element.id) { i, t in
                                    TrackRow(track: t, playing: player.current?.id == t.id) {
                                        player.play(tracks: tracks, startAt: i)
                                    }
                                }
                            }
                            if scope == "all" || scope == "playlists", let pls = r.playlists, !pls.isEmpty {
                                SectionHeader("Playlists"); CardRows(cards: pls, isAlbum: false)
                            }
                            if scope == "all" || scope == "albums", let als = r.albums, !als.isEmpty {
                                SectionHeader("Alben"); CardRows(cards: als, isAlbum: true)
                            }
                            if scope == "all" || scope == "artists", let ars = r.artists, !ars.isEmpty {
                                SectionHeader("Künstler"); CardRows(cards: ars, isAlbum: false)
                            }
                            if scope == "all" || scope == "shows", let shs = r.shows, !shs.isEmpty {
                                SectionHeader("Podcasts"); CardRows(cards: shs, isAlbum: false)
                            }
                        }.padding(.bottom, 130).padding(.top, 4)
                    } else {
                        VStack(spacing: 10) {
                            Circle().fill(Theme.input).frame(width: 84, height: 84)
                                .overlay(Image(systemName: "magnifyingglass").font(.system(size: 32)).foregroundStyle(Theme.sub))
                            Text("Such nach einem Song").font(.title3.bold()).foregroundStyle(Theme.text)
                            Text("Songs, Playlists, Alben, Künstler — der Spotify-Katalog")
                                .font(.system(size: 14)).foregroundStyle(Theme.mute)
                                .multilineTextAlignment(.center).padding(.horizontal, 40)
                        }.frame(maxWidth: .infinity).padding(.top, 70)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .padding(.top, 6)
            .background(Theme.bg)
            .navigationTitle("Suchen")
            .navigationDestination(for: Card.self) { c in
                if c.uri.contains(":show:") {
                    PodcastView(uri: c.uri, title: c.name, image: c.image)
                } else {
                    TrackListView(uri: c.uri, title: c.name, image: c.image, isAlbum: c.uri.contains(":album:"))
                }
            }
        }
    }
    private func label(_ s: String) -> String {
        ["all":"Alle","tracks":"Songs","playlists":"Playlists","albums":"Alben","artists":"Künstler","shows":"Podcasts"][s] ?? s
    }
    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        busy = true
        Task { res = try? await app.api.search(q); busy = false }
    }
}

struct CardRows: View {
    let cards: [Card]; let isAlbum: Bool
    var body: some View {
        ForEach(cards) { c in
            NavigationLink(value: c) {
                HStack(spacing: 12) {
                    Artwork(url: c.image, size: 50, corner: isAlbum || c.uri.contains(":artist:") ? 25 : 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.system(size: 15)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(c.artist ?? c.owner ?? "").font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                    }
                    Spacer()
                }.padding(.horizontal).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

// MARK: - Bibliothek
struct LibraryView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    @State private var playlists: [Playlist] = []
    @State private var subs: Set<String> = []
    @State private var subSync: [String: String] = [:]
    @State private var history: [HistoryEntry] = []
    @State private var filter = ""
    @State private var tab = "all"

    private func isRadioItem(_ uri: String) -> Bool {
        uri.hasPrefix("radio-name:") || uri.hasPrefix("radio:") || uri.hasPrefix("radio-id:")
    }
    private var radioPlaylists: [Playlist] {
        var list = playlists.filter { isRadioItem($0.uri) }
        if !filter.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(filter) } }
        return list
    }

    @State private var loaded = false
    private let tabs: [(String, String)] = [
        ("all", "Alle"), ("subs", "Abos"), ("alpha", "A–Z"),
        ("radios", "📻 Radios"), ("history", "📜 Verlauf"),
    ]

    private var shown: [Playlist] {
        var list = playlists.filter { !isRadioItem($0.uri) }   // Radios haben eigenen Filter
        if tab == "subs" { list = list.filter { subs.contains($0.uri) } }
        if !filter.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(filter) } }
        if tab == "alpha" { list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        // Abo-Playlists immer oben
        return list.filter { subs.contains($0.uri) } + list.filter { !subs.contains($0.uri) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.mute)
                    TextField("In Bibliothek suchen", text: $filter).foregroundStyle(Theme.text)
                }.padding(.horizontal, 14).padding(.vertical, 12).background(Theme.input)
                    .clipShape(RoundedRectangle(cornerRadius: 8)).padding(.horizontal).padding(.top, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs, id: \.0) { f in
                            Pill(text: f.1, active: tab == f.0, activeBg: Theme.accent) { tab = f.0 }
                        }
                    }.padding(.horizontal)
                }.padding(.top, 10)

                LazyVStack(spacing: 2) {
                    if tab == "radios" {
                        ForEach(radioPlaylists) { pl in
                            NavigationLink(value: pl) {
                                LibraryRow(pl: pl, subscribed: false, sync: nil)
                            }.buttonStyle(.plain)
                        }
                    } else if tab == "history" {
                        ForEach(history) { e in
                            if (e.kind ?? "") == "track" {
                                Button {
                                    player.play(tracks: [Track(uri: e.uri, name: e.name, artist: e.artist ?? "", image: e.image)],
                                                contextName: e.context_name ?? "", contextURI: e.context_uri ?? "")
                                } label: { HistoryEntryRow(entry: e) }.buttonStyle(.plain)
                            } else {
                                NavigationLink(value: HomeItem(uri: e.uri, name: e.name, image: e.image, sub: e.context_name, type: e.kind)) {
                                    HistoryEntryRow(entry: e)
                                }.buttonStyle(.plain)
                            }
                        }
                    } else {
                        ForEach(shown) { pl in
                            NavigationLink(value: pl) {
                                LibraryRow(pl: pl, subscribed: subs.contains(pl.uri), sync: subSync[pl.uri])
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(.top, 10).padding(.bottom, 130)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .overlay { if !loaded && playlists.isEmpty { ProgressView().tint(Theme.accent) } }
            .navigationTitle("Meine Bibliothek")
            .navigationDestination(for: Playlist.self) { pl in
                TrackListView(uri: pl.uri, title: pl.name, image: pl.image, isAlbum: false)
            }
            .navigationDestination(for: HomeItem.self) { it in
                if (it.type ?? "") == "show" || it.uri.contains(":show:") {
                    PodcastView(uri: it.uri, title: it.name, image: it.image)
                } else {
                    TrackListView(uri: it.uri, title: it.name, image: it.image, isAlbum: it.type == "album")
                }
            }
            .refreshable { await load() }
        }
        .task(id: app.profile?.id) { await load() }
        .task(id: tab) {
            if tab == "history" { history = (try? await app.api.history()) ?? [] }
        }
    }
    private func load() async {
        // Cache sofort
        if playlists.isEmpty { playlists = app.cacheGet("playlists", [Playlist].self) ?? [] }
        // Sequenziell (nicht parallel) — vermeidet gleichzeitige Spotify-Token-Fetches
        if let p = try? await app.api.playlists() { playlists = p; app.cacheSet("playlists", p) }
        if let s = try? await app.api.subscriptions() {
            subs = Set(s.map { $0.uri })
            subSync = Dictionary(s.compactMap { i in i.last_sync.map { (i.uri, $0) } }) { a, _ in a }
        }
        loaded = true
    }
}

struct LibraryRow: View {
    let pl: Playlist; let subscribed: Bool; let sync: String?
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                Artwork(url: pl.image, size: 56, corner: 6)
                if subscribed {
                    Image(systemName: "bell.fill").font(.system(size: 10)).foregroundStyle(.black)
                        .padding(5).background(Circle().fill(Theme.accent)).offset(x: -3, y: 3)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(pl.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 4) {
                    Text(subscribed ? "Abo" : "Playlist").font(.system(size: 13))
                        .foregroundStyle(subscribed ? Theme.accent : Theme.sub)
                    if let s = sync { Text("· sync \(s)").font(.system(size: 13)).foregroundStyle(Theme.sub) }
                }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 6).padding(.horizontal).contentShape(Rectangle())
    }
}

struct HistoryRow: View {
    let item: HomeItem
    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: item.image, size: 56, corner: (item.type ?? "") == "artist" ? 28 : 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(item.sub ?? (item.type ?? "").capitalized).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 6).padding(.horizontal).contentShape(Rectangle())
    }
}

struct HistoryEntryRow: View {
    let entry: HistoryEntry
    private var isTrack: Bool { (entry.kind ?? "") == "track" }
    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: entry.image, size: 50, corner: isTrack ? 4 : 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text((entry.artist?.isEmpty == false ? entry.artist! : (entry.context_name ?? "")))
                    .font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 6).padding(.horizontal).contentShape(Rectangle())
    }
}

struct RadioRow: View {
    let station: RadioStation
    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: station.favicon, size: 50, corner: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(station.country ?? "Live-Radio").font(.system(size: 13)).foregroundStyle(Theme.sub)
            }
            Spacer()
            Image(systemName: "star.fill").foregroundStyle(Theme.accent)
        }.padding(.vertical, 7).padding(.horizontal).contentShape(Rectangle())
    }
}

// MARK: - Radio
struct RadioView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    @State private var stations: [RadioStation] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(stations) { st in
                        Button { player.playRadio(st) } label: { RadioRow(station: st) }.buttonStyle(.plain)
                    }
                }.padding(.top, 8).padding(.bottom, 130)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Live-Radio")
            .overlay { if stations.isEmpty { ProgressView().tint(Theme.accent) } }
        }
        .task { if stations.isEmpty { stations = (try? await app.api.radioFavorites()) ?? [] } }
    }
}

// MARK: - Track-Liste (Playlist/Album-Detail)
struct TrackListView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    let uri: String; let title: String; let image: String?; let isAlbum: Bool
    @State private var tracks: [Track] = []
    @State private var recs: [Track] = []
    @State private var loading = true
    @State private var hero: Color = Theme.elev
    @State private var reload = 0

    private var metaText: String {
        if isAlbum { return "Album · \(tracks.count) Songs" }
        let total = tracks.reduce(0) { $0 + Int($1.durationSec) }
        var s = "Playlist · \(tracks.count) Songs"
        if total > 0 {
            let h = total / 3600, m = (total % 3600) / 60
            s += " · " + (h > 0 ? "\(h)h \(m)min" : "\(m)min")
        }
        return s
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero
                VStack(spacing: 14) {
                    Artwork(url: image, size: 210, corner: 6).shadow(color: .black.opacity(0.6), radius: 30, y: 8).padding(.top, 12)
                    Text(title).font(.system(size: 26, weight: .black)).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    Text(metaText)
                        .font(.system(size: 13)).foregroundStyle(Theme.sub)
                    // Aktions-Reihe
                    HStack {
                        Image(systemName: "arrow.down.circle").font(.title2).foregroundStyle(Theme.sub)
                        Image(systemName: "ellipsis").font(.title3).foregroundStyle(Theme.sub).padding(.leading, 14)
                        Spacer()
                        Button { if !tracks.isEmpty { player.shuffle = true; player.play(tracks: tracks.shuffled(), contextName: title, contextURI: uri) } } label: {
                            Image(systemName: "shuffle").font(.title2).foregroundStyle(Theme.text)
                        }.padding(.trailing, 18)
                        Button { if !tracks.isEmpty { player.shuffle = false; player.play(tracks: tracks, startAt: 0, contextName: title, contextURI: uri) } } label: {
                            Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(.black)
                                .frame(width: 56, height: 56).background(Theme.accent).clipShape(Circle())
                                .shadow(color: Theme.accent.opacity(0.4), radius: 10)
                        }
                    }.padding(.horizontal).padding(.top, 8)
                }
                .padding(.bottom, 16)
                .background(
                    LinearGradient(stops: [
                        .init(color: hero, location: 0),
                        .init(color: hero, location: 0.30),
                        .init(color: hero.opacity(0.35), location: 0.62),
                        .init(color: Theme.bg, location: 0.95)],
                        startPoint: .top, endPoint: .bottom)
                )
                // Tracks (nummeriert)
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, t in
                        NumberedTrackRow(n: idx + 1, track: t, showCover: !isAlbum, playing: player.current?.id == t.id) {
                            player.shuffle = false; player.play(tracks: tracks, startAt: idx, contextName: title, contextURI: uri)
                        }
                    }
                }.padding(.top, 6)

                // Leer/Fehler -> erneut versuchen
                if tracks.isEmpty && !loading {
                    VStack(spacing: 12) {
                        Text("Konnte nicht geladen werden").foregroundStyle(Theme.sub)
                        Button { reload += 1 } label: {
                            Label("Erneut versuchen", systemImage: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .background(Theme.accent).clipShape(Capsule())
                        }
                    }.frame(maxWidth: .infinity).padding(.top, 40)
                }

                // Empfehlungen ("Discover")
                if !recs.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionHeader("Empfehlungen")
                        Text(isAlbum ? "Ähnliche Songs" : "Basierend auf dieser Playlist")
                            .font(.system(size: 13)).foregroundStyle(Theme.sub)
                            .padding(.horizontal).padding(.bottom, 4)
                        ForEach(Array(recs.enumerated()), id: \.offset) { i, t in
                            TrackRow(track: t, playing: player.current?.id == t.id) {
                                player.shuffle = false; player.play(tracks: recs, startAt: i, contextName: "Empfehlungen", contextURI: uri)
                            }
                        }
                    }.padding(.top, 14)
                }
                Color.clear.frame(height: 130)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
                }
            }
        }
        .overlay { if loading { ProgressView().tint(Theme.accent) } }
        .task(id: reload) {
            loading = true; tracks = []
            let absImg = image.flatMap { app.api.absoluteURL($0)?.absoluteString } ?? image
            if let c = await averageColor(absImg) { hero = c }
            var t = (isAlbum ? try? await app.api.albumTracks(uri) : try? await app.api.playlistTracks(uri, check: true))?.tracks ?? []
            // Fallback: History-Items sind manchmal falsch klassifiziert (Album<->Playlist)
            if t.isEmpty {
                let alt = isAlbum ? try? await app.api.playlistTracks(uri, check: true) : try? await app.api.albumTracks(uri)
                if let alt = alt?.tracks, !alt.isEmpty { t = alt }
            }
            tracks = t; loading = false
        }
        .task(id: reload) { recs = (try? await app.api.recommendations(uri)) ?? [] }
    }
}

// MARK: - Podcast
struct PodcastView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    let uri: String; let title: String; let image: String?
    @State private var resp: PodcastResponse?
    @State private var loading = true
    @State private var hero: Color = Theme.elev

    private var showName: String { resp?.show?.name ?? title }
    private var showImage: String? { resp?.show?.image ?? image }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Artwork(url: showImage, size: 180, corner: 8).shadow(color: .black.opacity(0.5), radius: 24, y: 8).padding(.top, 12)
                    Text(showName).font(.system(size: 22, weight: .black)).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    if let pub = resp?.show?.publisher, !pub.isEmpty {
                        Text(pub).font(.system(size: 13)).foregroundStyle(Theme.sub)
                    }
                    Text("\(resp?.episodes.count ?? 0) Folgen").font(.system(size: 13)).foregroundStyle(Theme.sub)
                }.frame(maxWidth: .infinity).padding(.bottom, 16)
                .background(LinearGradient(stops: [
                    .init(color: hero, location: 0), .init(color: hero, location: 0.3),
                    .init(color: Theme.bg, location: 0.95)], startPoint: .top, endPoint: .bottom))

                LazyVStack(spacing: 0) {
                    ForEach(Array((resp?.episodes ?? []).enumerated()), id: \.element.id) { i, ep in
                        EpisodeRow(ep: ep, playing: player.current?.uri == ep.uri) {
                            let q = (resp?.episodes ?? []).map { $0.track(podcast: showName, fallbackImage: showImage) }
                            player.play(tracks: q, startAt: i, contextName: showName, contextURI: uri)
                        }
                    }
                }.padding(.top, 6)
                Color.clear.frame(height: 130)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text) }
        } }
        .overlay { if loading { ProgressView().tint(Theme.accent) } }
        .task {
            loading = true
            let absImg = image.flatMap { app.api.absoluteURL($0)?.absoluteString } ?? image
            if let c = await averageColor(absImg) { hero = c }
            resp = try? await app.api.podcast(uri)
            loading = false
        }
    }
}

struct EpisodeRow: View {
    let ep: Episode; let playing: Bool; let tap: () -> Void
    private var durText: String {
        let s = (ep.duration_ms ?? 0) / 1000
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h) Std. \(m) Min." : "\(m) Min."
    }
    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Artwork(url: ep.image, size: 56, corner: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ep.name).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(playing ? Theme.accent : Theme.text).lineLimit(2)
                        if let d = ep.description, !d.isEmpty {
                            Text(d).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill").font(.system(size: 30))
                        .foregroundStyle(playing ? Theme.accent : Theme.text)
                    Text(durText).font(.system(size: 12)).foregroundStyle(Theme.sub)
                    Spacer()
                }
            }.padding(.vertical, 12).padding(.horizontal).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .overlay(Rectangle().fill(Theme.input).frame(height: 0.5), alignment: .bottom)
    }
}

struct NumberedTrackRow: View {
    let n: Int; let track: Track; var showCover: Bool = true; let playing: Bool; let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Text("\(n)").font(.system(size: 14).monospacedDigit()).foregroundStyle(playing ? Theme.accent : Theme.sub)
                    .frame(width: 24, alignment: .trailing)
                if showCover { Artwork(url: track.image, size: 50, corner: 4) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).font(.system(size: 16, weight: .regular))
                        .foregroundStyle(playing ? Theme.accent : Theme.text).lineLimit(1)
                    Text(track.artist).font(.system(size: 14)).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer()
                if track.downloaded == true {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                }
                Menu {
                    TrackMenu(track: track)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16)).foregroundStyle(Theme.mute)
                        .frame(width: 34, height: 34).contentShape(Rectangle())
                }
            }.padding(.vertical, 9).padding(.horizontal).contentShape(Rectangle())
                .background(playing ? Theme.accent.opacity(0.08) : .clear)
        }.buttonStyle(.plain)
        .contextMenu { TrackMenu(track: track) }
    }
}

struct TrackRow: View {
    let track: Track; let playing: Bool; let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Artwork(url: track.image, size: 52, corner: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).font(.system(size: 16))
                        .foregroundStyle(playing ? Theme.accent : Theme.text).lineLimit(1)
                    Text(track.artist).font(.system(size: 14)).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer()
                if track.downloaded == true {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.accent.opacity(0.7))
                }
                Menu {
                    TrackMenu(track: track)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16)).foregroundStyle(Theme.mute)
                        .frame(width: 34, height: 34).contentShape(Rectangle())
                }
            }.padding(.vertical, 9).padding(.horizontal).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .contextMenu { TrackMenu(track: track) }
    }
}

struct SectionHeader: View {
    let t: String; init(_ t: String) { self.t = t }
    var body: some View {
        Text(t).font(.title3.bold()).foregroundStyle(Theme.text).padding(.horizontal).padding(.top, 8)
    }
}

// MARK: - Now-Playing-Bar
struct NowPlayingBar: View {
    @EnvironmentObject var player: PlayerController
    @Binding var showPlayer: Bool
    var body: some View {
        if player.hasContent {
            HStack(spacing: 12) {
                Artwork(url: player.displayImage, size: 44, corner: 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.displayTitle).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    HStack(spacing: 5) {
                        if !player.isRadio && !player.source.isEmpty {
                            Circle().fill(player.source == "youtube" ? Color(hex6: 0xFF3B30) : Theme.accent)
                                .frame(width: 6, height: 6)
                        }
                        Text(player.displayArtist).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                    }
                }
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).foregroundStyle(.black)
                        .frame(width: 38, height: 38).background(.white).clipShape(Circle())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex6: 0x282828))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            )
            .onTapGesture { showPlayer = true }
        }
    }
}

// MARK: - Vollbild-Player
struct PlayerView: View {
    @EnvironmentObject var player: PlayerController
    @State private var scrub: Double = 0
    @State private var scrubbing = false
    @State private var page = 0
    @State private var showLyrics = false
    @State private var hero: Color = Theme.elev

    var body: some View {
        let p = player
        ZStack {
            LinearGradient(colors: [hero.opacity(0.85), Theme.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            TabView(selection: $page) {
              VStack(spacing: 22) {
                Spacer()
                Artwork(url: p.displayImage, size: 300, corner: 12).shadow(radius: 24)
                    .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                        if v.translation.height < -60 && abs(v.translation.width) < 60 { showLyrics = true }
                    })
                VStack(spacing: 6) {
                    Text(p.displayTitle).font(.title2.bold()).foregroundStyle(Theme.text).lineLimit(1)
                    Text(p.displayArtist).foregroundStyle(Theme.sub).lineLimit(1)
                    if !p.isRadio && !p.source.isEmpty {
                        SourceBadge(source: p.source).padding(.top, 4)
                    }
                }
                if !p.isRadio {
                    VStack(spacing: 2) {
                        Slider(value: Binding(get: { scrubbing ? scrub : p.currentTime }, set: { scrub = $0 }),
                               in: 0...max(p.duration, 1), onEditingChanged: { e in scrubbing = e; if !e { p.seek(scrub) } })
                            .tint(Theme.accent)
                        HStack {
                            Text(fmt(scrubbing ? scrub : p.currentTime)).font(.caption2).foregroundStyle(Theme.sub)
                            Spacer()
                            Text(fmt(p.duration)).font(.caption2).foregroundStyle(Theme.sub)
                        }
                    }.padding(.horizontal)
                    if p.isEpisode {
                        HStack {
                            Button { p.skip(-10) } label: { Image(systemName: "gobackward.10").font(.title2) }
                            Spacer()
                            Button { p.prev() } label: { Image(systemName: "backward.fill").font(.title2) }
                            Spacer()
                            Button { p.toggle() } label: {
                                Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 72))
                            }
                            Spacer()
                            Button { p.next() } label: { Image(systemName: "forward.fill").font(.title2) }
                            Spacer()
                            Button { p.skip(10) } label: { Image(systemName: "goforward.10").font(.title2) }
                        }.foregroundStyle(Theme.text).padding(.horizontal, 8)
                    } else {
                        HStack {
                            Button { p.toggleShuffle() } label: {
                                Image(systemName: "shuffle").font(.title3).foregroundStyle(p.shuffle ? Theme.accent : Theme.text)
                            }
                            Spacer()
                            Button { p.prev() } label: { Image(systemName: "backward.fill").font(.title) }
                            Spacer()
                            Button { p.toggle() } label: {
                                Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 72))
                            }
                            Spacer()
                            Button { p.next() } label: { Image(systemName: "forward.fill").font(.title) }
                            Spacer()
                            Button { p.cycleRepeat() } label: {
                                Image(systemName: p.repeatMode == .one ? "repeat.1" : "repeat")
                                    .font(.title3).foregroundStyle(p.repeatMode == .off ? Theme.text : Theme.accent)
                            }
                        }.foregroundStyle(Theme.text).padding(.horizontal, 8)
                    }
                    HStack(spacing: 50) {
                        Button { showLyrics = true } label: { Label("Songtext", systemImage: "quote.bubble").font(.system(size: 15, weight: .semibold)) }
                        Button { withAnimation { page = 1 } } label: { Label("Warteschlange", systemImage: "list.bullet").font(.system(size: 15, weight: .semibold)) }
                    }.foregroundStyle(Theme.sub).padding(.top, 4)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Theme.accent)
                        Text("LIVE").font(.caption.bold()).foregroundStyle(Theme.accent)
                    }
                    Button { p.toggle() } label: {
                        Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72)).foregroundStyle(Theme.text)
                    }
                }
                Spacer()
              }.padding().tag(0)
              QueuePage(page: $page).tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showLyrics) { LyricsSheet() }
        .task(id: player.displayImage) { if let c = await averageColor(player.displayImage) { hero = c } }
    }
    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(s)/60, Int(s)%60)
    }
}

// MARK: - Warteschlange (seitliche Player-Seite)
struct QueuePage: View {
    @EnvironmentObject var player: PlayerController
    @Binding var page: Int
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Warteschlange").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                Spacer()
                Button { player.clearUpNext(); Haptics.tap() } label: {
                    Text("Leeren").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent)
                }.opacity(player.upNext.isEmpty ? 0.4 : 1).disabled(player.upNext.isEmpty)
            }.padding(.horizontal).padding(.top, 16).padding(.bottom, 8)

            List {
                if let c = player.current {
                    Section {
                        QueueRow(track: c, playing: true)
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    } header: { QueueHeader("Jetzt läuft") }
                }
                if !player.upNext.isEmpty {
                    Section {
                        ForEach(Array(player.upNext.enumerated()), id: \.element.id) { i, t in
                            QueueRow(track: t, playing: false)
                                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                                .contentShape(Rectangle())
                                .onTapGesture { player.playAt(player.index + 1 + i) }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { player.removeUpNext(at: i) } label: {
                                        Label("Entfernen", systemImage: "trash")
                                    }
                                }
                        }
                        .onMove { src, dst in player.moveUpNext(from: src, to: dst); Haptics.tap(.medium) }
                    } header: { QueueHeader("Als Nächstes") }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

struct QueueHeader: View {
    let t: String; init(_ t: String) { self.t = t }
    var body: some View {
        Text(t).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.sub)
            .textCase(nil).padding(.vertical, 4)
    }
}

struct QueueRow: View {
    let track: Track; let playing: Bool
    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: track.image, size: 48, corner: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name).font(.system(size: 16)).foregroundStyle(playing ? Theme.accent : Theme.text).lineLimit(1)
                Text(track.artist).font(.system(size: 14)).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer()
            Image(systemName: "line.3.horizontal").font(.system(size: 16)).foregroundStyle(Theme.mute)
        }.padding(.vertical, 4)
    }
}

// MARK: - Songtext
struct LyricsSheet: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    @State private var text = "Lade Songtext…"
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                Text(text).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
            }.scrollContentBackground(.hidden)
        }
        .presentationDetents([.large])
        .task {
            guard let t = player.current else { text = "Kein Song"; return }
            if let ly = try? await app.api.lyrics(title: t.name, artist: t.artist, duration: Int(t.durationSec)) {
                text = (ly.lyrics?.isEmpty == false) ? (ly.lyrics ?? "") :
                       (ly.instrumental == true ? "🎵 Instrumental" : "Kein Songtext gefunden")
            } else { text = "Kein Songtext gefunden" }
        }
    }
}

// MARK: - Quellen-Pille (woher kommt der Stream)
struct SourceBadge: View {
    let source: String
    var body: some View {
        let label: String
        let color: Color
        switch source {
        case "youtube":   label = "YouTube";    color = Color(hex6: 0xFF3B30)
        case "navidrome": label = "Bibliothek"; color = Theme.accent
        default:          label = source.capitalized; color = Theme.sub
        }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sub)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.input).clipShape(Capsule())
    }
}

// MARK: - Cover
struct Artwork: View {
    let url: String?
    var size: CGFloat = 48
    var corner: CGFloat = 6
    private var resolved: URL? {
        guard let s = url, !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: ImageBase.url + (s.hasPrefix("/") ? s : "/" + s))
    }
    var body: some View {
        AsyncImage(url: resolved) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: corner).fill(Theme.card)
                .overlay(Image(systemName: "music.note").foregroundStyle(Theme.mute))
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: corner))
    }
}
