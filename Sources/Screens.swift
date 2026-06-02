import SwiftUI
import Combine
import UIKit
import AVKit
import CoreSpotlight
import UniformTypeIdentifiers

/// Playlists in der iOS-Suche (Spotlight) indexieren.
func indexPlaylistsInSpotlight(_ pls: [Playlist]) {
    let items = pls.prefix(150).map { pl -> CSSearchableItem in
        let attr = CSSearchableItemAttributeSet(contentType: .content)
        attr.title = pl.name
        attr.contentDescription = "Discover-Playlist"
        return CSSearchableItem(uniqueIdentifier: pl.uri, domainIdentifier: "discover.playlist", attributeSet: attr)
    }
    CSSearchableIndex.default().indexSearchableItems(items)
}

/// AirPlay-Routen-Button (HomePod, AppleTV, AirPlay-Boxen).
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(white: 1, alpha: 0.85)
        v.activeTintColor = UIColor(red: 0.12, green: 0.84, blue: 0.38, alpha: 1)
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

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
    @EnvironmentObject var sync: SyncManager
    @State private var showPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                HomeView().tabItem { Label("Home", systemImage: "house.fill") }
                SearchView().tabItem { Label("Suchen", systemImage: "magnifyingglass") }
                LibraryView().tabItem { Label("Bibliothek", systemImage: "books.vertical.fill") }
                RadioView().tabItem { Label("Radio", systemImage: "antenna.radiowaves.left.and.right") }
            }
            .tint(Theme.text)
            VStack(spacing: 8) {
                SyncBanner()   // sichtbar nur wenn ein anderes Geraet spielt
                if player.hasContent {
                    NowPlayingBar(showPlayer: $showPlayer)
                }
            }.padding(.horizontal, 8).padding(.bottom, 50)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .overlay(alignment: .top) {
            if !sync.injectToast.isEmpty {
                Text(sync.injectToast)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.accent).clipShape(Capsule())
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: sync.injectToast)
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
    @Environment(\.liquidGlass) private var glass
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(text).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(active ? .black : Theme.text)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .glassSurface(active ? false : glass, shape: Capsule(), fallback: active ? activeBg : Theme.input)
            .clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}

// MARK: - Lade-Anzeige (Spinner + "Lädt" mit animierten Punkten, wie PWA)
struct LoadingView: View {
    var text = "Lädt"
    @State private var dots = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Theme.accent).scaleEffect(1.3)
            HStack(spacing: 0) {
                Text(text)
                Text(String(repeating: ".", count: dots)).frame(width: 16, alignment: .leading)
            }
            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.sub)
            .frame(height: 16)
        }
        .frame(maxWidth: .infinity)
        .onReceive(timer) { _ in dots = (dots + 1) % 4 }
    }
}

// MARK: - Track-Kontextmenue (Long-Press + "…")
struct TrackMenu: View {
    let track: Track
    var onShowArtist: (() -> Void)? = nil
    var onShowAlbum: (() -> Void)? = nil
    var onAddToPlaylist: (() -> Void)? = nil
    var onSendToUser: (() -> Void)? = nil
    // WICHTIG: NICHT beobachten (kein @EnvironmentObject), sonst zeichnet das
    // offene Menue bei jedem Player-Tick neu (Flackern). Referenz nur lesen.
    private var app: AppState? { DiscoverServices.app }

    private var others: [Profile] {
        (app?.allProfiles ?? []).filter { $0.id != app?.profile?.id }
    }
    private func sendTo(_ p: Profile) {
        guard let api = app?.api else { return }
        Haptics.tap()
        Task { _ = await api.pushToProfile(p.id, track: track) }
    }

    var body: some View {
        // Quick-Actions als Icon-Reihe oben — alle drei sind Controls (ShareLink + Buttons)
        // -> ControlGroup rendert sie gleich gross. ShareLink = natives Teilen-Menue.
        ControlGroup {
            Menu {
                Button { copySpotify() } label: { Label("Spotify-Link kopieren", systemImage: "link") }
                Button { Task { await copyYouTube() } } label: { Label("YouTube-Link kopieren", systemImage: "play.rectangle") }
            } label: { Label("Teilen", systemImage: "square.and.arrow.up") }
            Button { app?.player.playNext(track); Haptics.tap() } label: { Label("Als Nächstes", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Menu {
                if others.isEmpty {
                    Text("Keine anderen Profile")
                } else {
                    ForEach(others) { p in
                        Button { sendTo(p) } label: { Label(p.name, systemImage: "person.crop.circle") }
                    }
                }
            } label: { Label("Senden", systemImage: "paperplane") }
        }
        // restliche Optionen als Liste darunter
        Button { app?.player.addToQueue(track); Haptics.tap() } label: { Label("Zur Warteschlange", systemImage: "text.badge.plus") }
        if let onAdd = onAddToPlaylist {
            Button { onAdd() } label: { Label("Zu Playlist hinzufügen", systemImage: "plus.circle") }
        }
        Button { app?.downloads.toggle(track) } label: {
            let dl = app?.downloads.isDownloaded(track.uri) ?? false
            Label(dl ? "Aus Offline entfernen" : "Herunterladen", systemImage: dl ? "trash" : "arrow.down.circle")
        }
        if let onArtist = onShowArtist, track.artists?.first?.uri != nil {
            Button { onArtist() } label: { Label("Künstler anzeigen", systemImage: "person") }
        }
        if let onAlbum = onShowAlbum, track.album_uri != nil {
            Button { onAlbum() } label: { Label("Album anzeigen", systemImage: "square.stack") }
        }
        Button { startRadio() } label: { Label("Song-Radio starten", systemImage: "dot.radiowaves.left.and.right") }
    }
    private func copySpotify() {
        if let id = track.uri.split(separator: ":").last {
            UIPasteboard.general.string = "https://open.spotify.com/track/\(id)"; Haptics.tap()
        }
    }
    private func copyYouTube() async {
        guard let api = app?.api else { return }
        if let vid = await api.ytVideoId(for: track) {
            UIPasteboard.general.string = "https://www.youtube.com/watch?v=\(vid)"; Haptics.tap()
        }
    }
    private func startRadio() {
        guard let api = app?.api, let player = app?.player else { return }
        Task {
            guard let r = try? await api.startRadio(track: track), r.ok,
                  let puri = r.playlist_uri,
                  let resp = try? await api.playlistTracks(puri) else { return }
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
        let filtered = filter == "all" ? q : q.filter { ($0.type ?? "") == filter }
        return Array(filtered.prefix(8))
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
                        LoadingView().padding(.top, 60)
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

                    // Zuletzt (aus eigenem Verlauf — zuverlaessig)
                    if !recents.isEmpty {
                        HomeRow(title: "Zuletzt", subtitle: nil, items: recents)
                    }
                    // Spotify-Home-Sektionen — kaputte "Zuletzt"-Sektion + Items ohne Cover rausfiltern
                    ForEach((home?.sections ?? []).filter { $0.title != "Zuletzt" && $0.title != "Zuletzt gespielt" }) { sec in
                        let items = sec.items.filter { !($0.image ?? "").isEmpty }
                        if !items.isEmpty {
                            HomeRow(title: sec.title, subtitle: sec.subtitle, items: items)
                        }
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
                } else if (item.type ?? "") == "artist" || item.uri.contains(":artist:") {
                    ArtistView(uri: item.uri, name: item.name, image: item.image)
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
            // Offline ohne Cache: leeren Zustand setzen statt ewig "Lädt..."
            if home == nil { home = HomeResponse(greeting: nil, user_name: nil, country: nil, quick: [], sections: []) }
            // Recents: zuerst Spotify-recents, sonst aus dem lokalen Verlauf bauen (zuverlaessig)
            if let r = try? await app.api.recents(), !r.isEmpty {
                recents = r; app.cacheSet("recents", r)
            } else if let hist = try? await app.api.history(), !hist.isEmpty {
                recents = recentsFromHistory(hist); app.cacheSet("recents", recents)
            }
        }
    }

    /// Baut "Zuletzt geoeffnet" aus dem Verlauf: zuletzt geoeffnete Playlists/Alben/Kuenstler/Podcasts.
    private func recentsFromHistory(_ hist: [HistoryEntry]) -> [HomeItem] {
        var seen = Set<String>(); var out: [HomeItem] = []
        for e in hist {
            let uri = (e.context_uri?.isEmpty == false) ? e.context_uri! : e.uri
            guard !seen.contains(uri),
                  uri.contains(":playlist:") || uri.contains(":album:") || uri.contains(":artist:") || uri.contains(":show:")
            else { continue }
            seen.insert(uri)
            let type = uri.contains(":album:") ? "album" : uri.contains(":artist:") ? "artist"
                     : uri.contains(":show:") ? "show" : "playlist"
            let name = (e.context_name?.isEmpty == false) ? e.context_name! : e.name
            out.append(HomeItem(uri: uri, name: name, image: e.image, sub: nil, type: type))
            if out.count >= 15 { break }
        }
        return out
    }
}

/// Horizontale Reihe grosser Cover-Karten (Home-Sektion).
struct HomeRow: View {
    let title: String
    let subtitle: String?
    let items: [HomeItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
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
    @State private var showConsole = false

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
                    if isAdmin {
                        AccountAction(icon: "wrench.and.screwdriver.fill", label: "Konsole (Status & Befehle)") { showConsole = true }
                    }
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
        .sheet(isPresented: $showConsole) { AdminConsoleView() }
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
    @AppStorage("syncDeviceName") private var syncDeviceName = ""
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
                    // Darstellung
                    SettingsGroup("DARSTELLUNG") {
                        Toggle(isOn: $app.liquidGlass) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Liquid Glass").font(.system(size: 15)).foregroundStyle(Theme.text)
                                Text("Durchscheinendes Glas-Design (iOS 26)").font(.caption2).foregroundStyle(Theme.mute)
                            }
                        }.tint(Theme.accent)
                    }
                    // Sync / Geraete-Name
                    SettingsGroup("GERÄT (SYNC)") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Geräte-Name").font(.system(size: 15)).foregroundStyle(Theme.text)
                            Text("So erscheint dieses Gerät bei anderen (Fernsteuerung/Senden).")
                                .font(.caption2).foregroundStyle(Theme.mute)
                            TextField(UIDevice.current.name, text: $syncDeviceName)
                                .foregroundStyle(Theme.text).padding(10)
                                .background(Theme.input).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
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
    @State private var debounce: Task<Void, Never>?
    @AppStorage("recentSearches") private var recentRaw = ""

    private var recentList: [String] { recentRaw.split(separator: "\n").map(String.init) }
    private func saveRecent() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        var list = recentList.filter { $0.lowercased() != q.lowercased() }
        list.insert(q, at: 0)
        recentRaw = list.prefix(10).joined(separator: "\n")
    }
    private func removeRecent(_ q: String) {
        recentRaw = recentList.filter { $0 != q }.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.black).font(.system(size: 18, weight: .semibold))
                    TextField("", text: $query, prompt: Text("Songs, Künstler suchen…").foregroundColor(Color.black.opacity(0.55)))
                        .foregroundStyle(.black).tint(.black)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { runSearch(); saveRecent() }
                        .onChange(of: query) { _ in debounceSearch() }
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
                    if busy { LoadingView().padding(.top, 40) }
                    else if let r = res {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            if scope == "all", let hit = r.top_hit, !hit.realURI.isEmpty {
                                SectionHeader("Top-Ergebnis")
                                TopHitCard(hit: hit)
                            }
                            if scope == "all" || scope == "tracks", let tracks = r.tracks, !tracks.isEmpty {
                                SectionHeader("Songs")
                                ForEach(Array(tracks.prefix(scope == "tracks" ? 50 : 6).enumerated()), id: \.offset) { i, t in
                                    TrackRow(track: t, playing: player.current?.id == t.id) {
                                        player.play(tracks: tracks, startAt: i, contextName: "Suche", contextURI: "")
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
                    } else if !recentList.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("Letzte Suchen").font(.title3.bold()).foregroundStyle(Theme.text)
                                Spacer()
                                Button("Löschen") { recentRaw = "" }.font(.system(size: 14)).foregroundStyle(Theme.sub)
                            }.padding(.horizontal).padding(.top, 8).padding(.bottom, 4)
                            ForEach(recentList, id: \.self) { q in
                                Button { query = q; runSearch() } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.sub).frame(width: 28)
                                        Text(q).font(.system(size: 16)).foregroundStyle(Theme.text).lineLimit(1)
                                        Spacer()
                                        Button { removeRecent(q) } label: {
                                            Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Theme.mute).frame(width: 30, height: 30)
                                        }
                                    }.padding(.vertical, 8).padding(.horizontal).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }.padding(.top, 6)
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
                } else if c.uri.contains(":artist:") {
                    ArtistView(uri: c.uri, name: c.name, image: c.image)
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
    /// Tippen -> nach kurzer Pause automatisch suchen (wie PWA).
    private func debounceSearch() {
        debounce?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { res = nil; busy = false; return }
        debounce = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            busy = true
            let r = try? await app.api.search(q)
            if Task.isCancelled { return }
            res = r; busy = false
        }
    }
}

struct TopHitCard: View {
    @EnvironmentObject var player: PlayerController
    let hit: TopHit
    var body: some View {
        Group {
            if hit.type == "track" {
                Button {
                    player.play(tracks: [Track(uri: hit.realURI, name: hit.name ?? "", artist: hit.artist ?? "", image: hit.image)])
                } label: { card }.buttonStyle(.plain)
            } else {
                NavigationLink(value: Card(uri: hit.realURI, name: hit.name ?? "", image: hit.image, artist: hit.artist, owner: nil, desc: nil)) {
                    card
                }.buttonStyle(.plain)
            }
        }
    }
    private var card: some View {
        HStack(spacing: 14) {
            Artwork(url: hit.image, size: 92, corner: hit.type == "artist" ? 46 : 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(hit.name ?? "").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text).lineLimit(2)
                Text(hit.typeLabel).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elev).clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
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

// MARK: - Künstler/Album-Navigation aus dem Track-Menue (Modal-Sheets)
private struct TrackNavSheets: ViewModifier {
    let track: Track
    @Binding var showArtist: Bool
    @Binding var showAlbum: Bool
    @Binding var showAddPlaylist: Bool
    @Binding var showSendUser: Bool
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showArtist) {
                NavigationStack {
                    if let u = track.artists?.first?.uri {
                        ArtistView(uri: u, name: track.artists?.first?.name ?? track.artist, image: track.image)
                    }
                }
            }
            .sheet(isPresented: $showAlbum) {
                NavigationStack {
                    if let u = track.album_uri {
                        TrackListView(uri: u, title: track.album ?? "Album", image: track.image, isAlbum: true)
                    }
                }
            }
            .sheet(isPresented: $showAddPlaylist) { AddToPlaylistSheet(track: track) }
            .sheet(isPresented: $showSendUser) { SendToUserSheet(track: track) }
    }
}
extension View {
    func trackNavSheets(track: Track, showArtist: Binding<Bool>, showAlbum: Binding<Bool>, showAddPlaylist: Binding<Bool>, showSendUser: Binding<Bool>) -> some View {
        modifier(TrackNavSheets(track: track, showArtist: showArtist, showAlbum: showAlbum, showAddPlaylist: showAddPlaylist, showSendUser: showSendUser))
    }
}

// MARK: - "An Nutzer senden" — Profil-Auswahl (cross-user queue_inject, erreicht auch PWA)
struct SendToUserSheet: View {
    let track: Track
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var profiles: [Profile] = []
    @State private var status = ""
    private var others: [Profile] { profiles.filter { $0.id != app.profile?.id } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Artwork(url: track.image, size: 44, corner: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(track.artist).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1)
                    }
                    Spacer()
                }.padding()
                if others.isEmpty {
                    Text("Keine anderen Profile gefunden.").font(.system(size: 14)).foregroundStyle(Theme.mute).padding(.top, 40)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(others) { p in
                            Button { send(p) } label: {
                                HStack(spacing: 12) {
                                    AvatarCircle(name: p.name, size: 40)
                                    Text(p.name).font(.system(size: 16)).foregroundStyle(Theme.text)
                                    Spacer()
                                    Image(systemName: "paperplane").foregroundStyle(Theme.sub)
                                }.padding(.horizontal).padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.top, 4)
                }
                Spacer()
            }
            .background(Theme.bg)
            .navigationTitle("An Nutzer senden").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Abbrechen") { dismiss() }.foregroundStyle(Theme.accent) } }
            .overlay(alignment: .bottom) {
                if !status.isEmpty {
                    Text(status).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.accent).clipShape(Capsule()).padding(.bottom, 30)
                }
            }
        }
        .task { profiles = (try? await app.api.profiles()) ?? [] }
    }
    private func send(_ p: Profile) {
        Task {
            let ok = await app.api.pushToProfile(p.id, track: track)
            status = ok ? "An \(p.name) gesendet ✓" : "Senden fehlgeschlagen"
            Haptics.tap()
            try? await Task.sleep(nanoseconds: 900_000_000)
            if ok { dismiss() } else { status = "" }
        }
    }
}

// MARK: - "Zu Playlist hinzufügen" — Auswahl-Sheet
struct AddToPlaylistSheet: View {
    let track: Track
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [Playlist] = []
    @State private var filter = ""
    @State private var newName = ""
    @State private var showNew = false
    @State private var status = ""
    private var shown: [Playlist] {
        let base = playlists.filter { $0.uri.hasPrefix("spotify:playlist:") }
        return filter.isEmpty ? base : base.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Artwork(url: track.image, size: 44, corner: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(track.artist).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1)
                    }
                    Spacer()
                }.padding()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.mute)
                    TextField("Playlist suchen…", text: $filter).foregroundStyle(Theme.text)
                        .autocorrectionDisabled()
                }.padding(10).background(Theme.input).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.horizontal)
                Button { newName = ""; showNew = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44).background(Theme.input)
                            .clipShape(RoundedRectangle(cornerRadius: 6)).foregroundStyle(Theme.text)
                        Text("Neue Playlist").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                        Spacer()
                    }.padding(.horizontal).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown) { pl in
                            Button { Task { await doAdd(pl.uri, pl.name) } } label: {
                                HStack(spacing: 12) {
                                    Artwork(url: pl.image, size: 44, corner: 4)
                                    Text(pl.name).font(.system(size: 16)).foregroundStyle(Theme.text).lineLimit(1)
                                    Spacer()
                                }.padding(.horizontal).padding(.vertical, 6).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.top, 4)
                }
            }
            .background(Theme.bg)
            .navigationTitle("Zu Playlist hinzufügen").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Abbrechen") { dismiss() }.foregroundStyle(Theme.accent) } }
            .alert("Neue Playlist", isPresented: $showNew) {
                TextField("Name", text: $newName)
                Button("Erstellen") { createAndAdd() }
                Button("Abbrechen", role: .cancel) {}
            }
            .overlay(alignment: .bottom) {
                if !status.isEmpty {
                    Text(status).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.accent).clipShape(Capsule()).padding(.bottom, 30)
                }
            }
        }
        .task { playlists = (try? await app.api.playlists()) ?? [] }
    }
    private func doAdd(_ uri: String, _ name: String) async {
        let ok = await app.api.addTrack(playlistURI: uri, track: track, playlistName: name)
        status = ok ? "Hinzugefügt ✓" : "Fehler – erneut versuchen"
        Haptics.tap()
        try? await Task.sleep(nanoseconds: 800_000_000)
        if ok { dismiss() } else { status = "" }
    }
    private func createAndAdd() {
        let n = newName.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
        Task {
            guard let uri = await app.api.createPlaylist(name: n) else { status = "Fehler beim Erstellen"; return }
            await doAdd(uri, n)
        }
    }
}

// MARK: - Bibliothek
struct LibraryView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var downloads: DownloadManager
    @State private var playlists: [Playlist] = []
    @State private var subs: Set<String> = []
    @State private var subSync: [String: String] = [:]
    @State private var history: [HistoryEntry] = []
    @State private var filter = ""
    @State private var tab = "all"

    private func isRadioItem(_ uri: String) -> Bool {
        uri.hasPrefix("radio-name:") || uri.hasPrefix("radio:") || uri.hasPrefix("radio-id:")
    }
    private func isLiked(_ uri: String) -> Bool { uri.contains("collection:tracks") }
    private var radioPlaylists: [Playlist] {
        var list = playlists.filter { isRadioItem($0.uri) }
        if !filter.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(filter) } }
        return list
    }

    @State private var loaded = false
    private let tabs: [(String, String)] = [
        ("all", "Alle"), ("subs", "Abos"), ("alpha", "A–Z"),
        ("radios", "📻 Radios"), ("history", "📜 Verlauf"), ("offline", "⬇️ Offline"),
    ]

    private var shown: [Playlist] {
        var list = playlists.filter { !isRadioItem($0.uri) && !isLiked($0.uri) }   // Radios + Liked Songs raus
        if tab == "subs" { list = list.filter { subs.contains($0.uri) } }
        if !filter.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(filter) } }
        if tab == "alpha" { list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        // Abo-Playlists immer oben
        return list.filter { subs.contains($0.uri) } + list.filter { !subs.contains($0.uri) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Meine Bibliothek").font(.system(size: 28, weight: .heavy)).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top, 6)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.mute)
                    TextField("In Bibliothek suchen", text: $filter).foregroundStyle(Theme.text)
                }.padding(.horizontal, 14).padding(.vertical, 12).background(Theme.input)
                    .clipShape(RoundedRectangle(cornerRadius: 8)).padding(.horizontal).padding(.top, 10)

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
                    } else if tab == "offline" {
                        if downloads.tracks.isEmpty {
                            Text("Noch nichts heruntergeladen.\nIm Song-Menue (…) auf Herunterladen tippen.")
                                .font(.system(size: 14)).foregroundStyle(Theme.mute)
                                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 50)
                        }
                        ForEach(Array(downloads.tracks.enumerated()), id: \.offset) { i, t in
                            TrackRow(track: t, playing: player.current?.id == t.id) {
                                player.play(tracks: downloads.tracks, startAt: i, contextName: "Offline", contextURI: "")
                            }
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
            .overlay { if !loaded && playlists.isEmpty { LoadingView() } }
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Playlist.self) { pl in
                TrackListView(uri: pl.uri, title: pl.name, image: pl.image, isAlbum: false)
            }
            .navigationDestination(for: HomeItem.self) { it in
                if (it.type ?? "") == "show" || it.uri.contains(":show:") {
                    PodcastView(uri: it.uri, title: it.name, image: it.image)
                } else if (it.type ?? "") == "artist" || it.uri.contains(":artist:") {
                    ArtistView(uri: it.uri, name: it.name, image: it.image)
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
        // Cache sofort (Playlists + Abos) -> Sortierung gleich korrekt, kein Hochschnellen
        if playlists.isEmpty { playlists = app.cacheGet("playlists", [Playlist].self) ?? [] }
        if subs.isEmpty, let cs = app.cacheGet("subs", [SubItem].self) { applySubs(cs) }
        // Sequenziell (nicht parallel) — vermeidet gleichzeitige Spotify-Token-Fetches
        if let p = try? await app.api.playlists() {
            playlists = p; app.cacheSet("playlists", p)
            indexPlaylistsInSpotlight(p)   // iOS-Suche
        }
        if let s = try? await app.api.subscriptions() { applySubs(s); app.cacheSet("subs", s) }
        loaded = true
    }
    private func applySubs(_ s: [SubItem]) {
        subs = Set(s.map { $0.uri })
        subSync = Dictionary(s.compactMap { i in i.last_sync.map { (i.uri, $0) } }) { a, _ in a }
    }
}

struct LibraryRow: View {
    let pl: Playlist; let subscribed: Bool; let sync: String?
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                Artwork(url: pl.image, size: 56, corner: 4)
                if subscribed {
                    Image(systemName: "bell.fill").font(.system(size: 10)).foregroundStyle(.black)
                        .padding(5).background(Circle().fill(Theme.accent)).offset(x: -3, y: 3)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pl.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 4) {
                    Text(subscribed ? "Abo" : "Playlist").font(.system(size: 13))
                        .foregroundStyle(subscribed ? Theme.accent : Theme.sub)
                    if let s = sync { Text("· sync \(s)").font(.system(size: 13)).foregroundStyle(Theme.sub) }
                }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8).padding(.horizontal).contentShape(Rectangle())
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
                Text("Live-Radio").font(.system(size: 28, weight: .heavy)).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top, 6)
                LazyVStack(spacing: 4) {
                    ForEach(stations) { st in
                        Button { player.playRadio(st) } label: { RadioRow(station: st) }.buttonStyle(.plain)
                    }
                }.padding(.top, 10).padding(.bottom, 130)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .overlay { if stations.isEmpty { LoadingView() } }
        }
        .task { if stations.isEmpty { stations = (try? await app.api.radioFavorites()) ?? [] } }
    }
}

// MARK: - Artist-Seite
struct ArtistView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    let uri: String; let name: String; let image: String?
    @State private var resp: ArtistResponse?
    @State private var loading = true
    @State private var hero: Color = Theme.elev

    private var top: [Track] { resp?.top_tracks ?? [] }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Artwork(url: resp?.image ?? image, size: 170, corner: 85)
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 8).padding(.top, 24)
                    Text(resp?.name ?? name).font(.system(size: 26, weight: .black))
                        .foregroundStyle(Theme.text).multilineTextAlignment(.center).padding(.horizontal)
                    if let f = resp?.followers, f > 0 {
                        Text("\(f.formatted()) Hörer*innen monatlich").font(.system(size: 13)).foregroundStyle(Theme.sub)
                    }
                    Button {
                        if !top.isEmpty { player.shuffle = false; player.play(tracks: top, startAt: 0, contextName: resp?.name ?? name, contextURI: uri) }
                    } label: {
                        Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(.black)
                            .frame(width: 56, height: 56).background(Theme.accent).clipShape(Circle())
                            .shadow(color: Theme.accent.opacity(0.4), radius: 10)
                    }.padding(.top, 4)
                }.frame(maxWidth: .infinity).padding(.bottom, 16)

                if !top.isEmpty {
                    SectionHeader("Beliebt")
                    LazyVStack(spacing: 0) {
                        ForEach(Array(top.prefix(10).enumerated()), id: \.offset) { i, t in
                            NumberedTrackRow(n: i + 1, track: t, playing: player.current?.id == t.id) {
                                player.shuffle = false; player.play(tracks: top, startAt: i, contextName: resp?.name ?? name, contextURI: uri)
                            }
                        }
                    }.padding(.top, 4)
                }
                if let albums = resp?.albums, !albums.isEmpty {
                    SectionHeader("Alben")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(albums) { c in
                                NavigationLink { TrackListView(uri: c.uri, title: c.name, image: c.image, isAlbum: true) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Artwork(url: c.image, size: 150, corner: 6)
                                        Text(c.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                                            .lineLimit(1).frame(width: 150, alignment: .leading)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal)
                    }
                }
                Color.clear.frame(height: 130)
            }
        }
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(stops: [
                .init(color: hero, location: 0),
                .init(color: hero, location: 0.16),
                .init(color: hero.opacity(0.32), location: 0.34),
                .init(color: Theme.bg, location: 0.52)],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text) }
        } }
        .overlay { if loading { LoadingView() } }
        .task {
            loading = true
            let absImg = image.flatMap { app.api.absoluteURL($0)?.absoluteString } ?? image
            if let c = await averageColor(absImg) { hero = c }
            resp = try? await app.api.artist(uri)
            loading = false
        }
    }
}

// MARK: - Track-Liste (Playlist/Album-Detail)
struct TrackListView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    let uri: String; let title: String; let image: String?; let isAlbum: Bool
    @State private var tracks: [Track] = []
    @State private var recs: [Track] = []
    @State private var loading = true
    @State private var hero: Color = Theme.elev
    @State private var reload = 0
    @State private var moreLoading = false
    @State private var isSubscribed = false
    @State private var addedRecs: Set<String> = []
    @State private var copyMsg = ""

    private func copyAsOwn() {
        guard !tracks.isEmpty else { return }
        copyMsg = "Kopiere \(tracks.count) Songs…"
        Task {
            let res = await app.api.copyPlaylist(sourceURI: uri, name: title + " (Kopie)")
            copyMsg = res != nil ? "Kopiert ✓ (\(res!.count) Songs)" : "Fehler beim Kopieren"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copyMsg = ""
        }
    }

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

    private func toggleSub() {
        let was = isSubscribed
        isSubscribed.toggle(); Haptics.tap()
        Task { was ? await app.api.unsubscribe(uri: uri) : await app.api.subscribe(uri: uri, name: title) }
    }

    private func startPlaylistRadio() {
        Task {
            guard let r = await app.api.startPlaylistRadio(uri: uri, name: title), r.ok,
                  let puri = r.playlist_uri,
                  let resp = try? await app.api.playlistTracks(puri) else { return }
            player.play(tracks: resp.tracks, contextName: r.name ?? "Radio", contextURI: puri)
        }
    }

    /// "+" auf einer Empfehlung -> Song in die Playlist (wie PWA: /api/add-track).
    private func addRec(_ t: Track) {
        if isAlbum { player.addToQueue(t); Haptics.tap(); return }
        Task {
            if await app.api.addTrack(playlistURI: uri, track: t, playlistName: title) {
                addedRecs.insert(t.uri); Haptics.tap()
                if !tracks.contains(where: { $0.uri == t.uri }) { tracks.append(t) }   // ans Ende wie PWA
            }
        }
    }

    private func loadMoreRecs() {
        guard !moreLoading else { return }
        moreLoading = true
        Task {
            // Alte ueberspringen + komplett durch neue ersetzen (wie PWA-Refresh)
            let skip = recs.compactMap { $0.uri.split(separator: ":").last.map(String.init) }
            let fresh = (try? await app.api.recommendations(uri, n: 15, skip: skip)) ?? []
            recs = fresh.isEmpty ? ((try? await app.api.recommendations(uri, n: 15)) ?? recs) : fresh
            moreLoading = false
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero
                VStack(spacing: 14) {
                    Artwork(url: image, size: 210, corner: 6).shadow(color: .black.opacity(0.6), radius: 30, y: 8).padding(.top, 24)
                    Text(title).font(.system(size: 26, weight: .black)).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    HStack(spacing: 5) {
                        Text(metaText).font(.system(size: 13)).foregroundStyle(Theme.sub)
                        if isSubscribed && !isAlbum {
                            Text("· 🔔 Abo").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                        }
                    }
                    // Aktions-Reihe
                    HStack {
                        Button {
                            Task { for t in tracks { await downloads.download(t) } }
                        } label: {
                            let all = !tracks.isEmpty && tracks.allSatisfy { downloads.isDownloaded($0.uri) }
                            Image(systemName: all ? "arrow.down.circle.fill" : "arrow.down.circle")
                                .font(.title2).foregroundStyle(all ? Theme.accent : Theme.sub)
                        }
                        Menu {
                            Button { Task { for t in tracks { await downloads.download(t) } } } label: {
                                Label("Alle herunterladen", systemImage: "arrow.down.circle")
                            }
                            if !isAlbum {
                                Button { startPlaylistRadio() } label: {
                                    Label("Playlist-Radio starten", systemImage: "dot.radiowaves.left.and.right")
                                }
                                Button { copyAsOwn() } label: {
                                    Label("Als eigene Playlist kopieren", systemImage: "plus.square.on.square")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(.title3).foregroundStyle(Theme.sub)
                                .frame(width: 46, height: 46).contentShape(Rectangle())
                        }.padding(.leading, 4)
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

                // Empfehlungen ("Discover") — wie PWA: Refresh-Icon + "+"-Reihen
                if !recs.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Empfehlungen").font(.title3.bold()).foregroundStyle(Theme.text)
                            Spacer()
                            if moreLoading { ProgressView().tint(Theme.accent) }
                            else {
                                Button { loadMoreRecs() } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.text)
                                }
                            }
                        }.padding(.horizontal).padding(.top, 8)
                        Text(isAlbum ? "Ähnliche Songs" : "Basierend auf den Songs deiner Playlist")
                            .font(.system(size: 13)).foregroundStyle(Theme.sub)
                            .padding(.horizontal).padding(.bottom, 4)
                        ForEach(Array(recs.enumerated()), id: \.offset) { i, t in
                            RecRow(track: t, playing: player.current?.id == t.id,
                                   added: addedRecs.contains(t.uri),
                                   add: { addRec(t) },
                                   play: { player.shuffle = false; player.play(tracks: recs, startAt: i, contextName: "Empfehlungen", contextURI: uri) })
                        }
                    }.padding(.top, 14)
                }
                Color.clear.frame(height: 130)
            }
        }
        .scrollContentBackground(.hidden)
        .background(
            // Gradient als ScrollView-Hintergrund: bleedet hinter die Notch (kein Clipping);
            // Cover bleibt korrekt unter der Toolbar, da die ScrollView die Safe-Area respektiert.
            LinearGradient(stops: [
                .init(color: hero, location: 0),
                .init(color: hero, location: 0.16),
                .init(color: hero.opacity(0.32), location: 0.34),
                .init(color: Theme.bg, location: 0.52)],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
                }
            }
            if !isAlbum {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { toggleSub() } label: {
                        Image(systemName: isSubscribed ? "bell.fill" : "bell")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isSubscribed ? Theme.accent : Theme.text)
                    }
                }
            }
        }
        .overlay { if loading { LoadingView() } }
        .overlay(alignment: .bottom) {
            if !copyMsg.isEmpty {
                Text(copyMsg).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.accent).clipShape(Capsule()).padding(.bottom, 150)
            }
        }
        .task(id: reload) {
            loading = true; tracks = []
            if !isAlbum { isSubscribed = (try? await app.api.subscriptions())?.contains { $0.uri == uri } ?? false }
            let absImg = image.flatMap { app.api.absoluteURL($0)?.absoluteString } ?? image
            if let c = await averageColor(absImg) { hero = c }
            var t = (isAlbum ? try? await app.api.albumTracks(uri) : try? await app.api.playlistTracks(uri, check: true))?.tracks ?? []
            // Fallback: History-Items sind manchmal falsch klassifiziert (Album<->Playlist)
            if t.isEmpty {
                let alt = isAlbum ? try? await app.api.playlistTracks(uri, check: true) : try? await app.api.albumTracks(uri)
                if let alt = alt?.tracks, !alt.isEmpty { t = alt }
            }
            tracks = t; loading = false
            let warm = t
            Task { await app.api.prewarmPlaylist(warm) }   // Server-Vorladen wie PWA
        }
        .task(id: reload) {
            // Cache-first: sofort die letzten Empfehlungen zeigen, dann im Hintergrund auffrischen
            let ckey = "recs_\(uri)"
            if recs.isEmpty, let cached = app.cacheGet(ckey, [Track].self) { recs = cached }
            if let fresh = try? await app.api.recommendations(uri), !fresh.isEmpty {
                recs = fresh
                app.cacheSet(ckey, fresh)
            }
        }
    }
}

// MARK: - Podcast
struct PodcastView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    let uri: String; let title: String; let image: String?
    @State private var resp: PodcastResponse?
    @State private var loading = true
    @State private var hero: Color = Theme.elev

    private var showName: String { resp?.show?.name ?? title }
    private var showImage: String? { resp?.show?.image ?? image }
    private var episodeTracks: [Track] { (resp?.episodes ?? []).map { $0.track(podcast: showName, fallbackImage: showImage) } }
    private var allDownloaded: Bool { !episodeTracks.isEmpty && episodeTracks.allSatisfy { downloads.isDownloaded($0.uri) } }
    private var anyDownloaded: Bool { episodeTracks.contains { downloads.isDownloaded($0.uri) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    PodcastFlipCard(image: showImage, description: resp?.show?.description, hero: hero)
                        .padding(.top, 24)
                    Text(showName).font(.system(size: 22, weight: .black)).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    if let pub = resp?.show?.publisher, !pub.isEmpty {
                        Text(pub).font(.system(size: 13)).foregroundStyle(Theme.sub)
                    }
                    HStack(spacing: 10) {
                        if let r = resp?.show?.rating, r > 0 {
                            Label(String(format: "%.1f", r), systemImage: "star.fill")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                        }
                        Text("\(resp?.episodes.count ?? 0) Folgen").font(.system(size: 13)).foregroundStyle(Theme.sub)
                    }
                    Text("Cover antippen für Beschreibung").font(.system(size: 11)).foregroundStyle(Theme.mute)

                    Button {
                        if anyDownloaded { for t in episodeTracks { downloads.delete(t.uri) } }
                        else { Task { for t in episodeTracks { await downloads.download(t) } } }
                    } label: {
                        Label(anyDownloaded ? "Heruntergeladene entfernen" : "Alle Folgen herunterladen",
                              systemImage: anyDownloaded ? "trash" : "arrow.down.circle")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(anyDownloaded ? Theme.text : .black)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(anyDownloaded ? Theme.input : Theme.accent).clipShape(Capsule())
                    }.padding(.top, 6)
                }.frame(maxWidth: .infinity).padding(.bottom, 16)

                LazyVStack(spacing: 0) {
                    ForEach(Array((resp?.episodes ?? []).enumerated()), id: \.element.id) { i, ep in
                        EpisodeRow(ep: ep, track: ep.track(podcast: showName, fallbackImage: showImage),
                                   playing: player.current?.uri == ep.uri) {
                            let q = (resp?.episodes ?? []).map { $0.track(podcast: showName, fallbackImage: showImage) }
                            player.play(tracks: q, startAt: i, contextName: showName, contextURI: uri)
                        }
                    }
                }.padding(.top, 6)
                Color.clear.frame(height: 130)
            }
        }
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(stops: [
                .init(color: hero, location: 0),
                .init(color: hero, location: 0.16),
                .init(color: hero.opacity(0.32), location: 0.34),
                .init(color: Theme.bg, location: 0.52)],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text) }
        } }
        .overlay { if loading { LoadingView() } }
        .task {
            loading = true
            let absImg = image.flatMap { app.api.absoluteURL($0)?.absoluteString } ?? image
            if let c = await averageColor(absImg) { hero = c }
            resp = try? await app.api.podcast(uri)
            loading = false
        }
    }
}

// MARK: - Podcast-Cover, das zur Beschreibung umklappt (Flip-Card)
struct PodcastFlipCard: View {
    let image: String?
    let description: String?
    var hero: Color = Theme.elev
    @State private var flipped = false
    private let side: CGFloat = 230

    var body: some View {
        ZStack {
            Artwork(url: image, size: side, corner: 12)
                .opacity(flipped ? 0 : 1)
            back
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))   // Text nicht gespiegelt
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.easeInOut(duration: 0.5), value: flipped)
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        .onTapGesture { flipped.toggle() }
    }

    private var back: some View {
        ScrollView {
            Text((description?.isEmpty == false) ? description! : "Keine Beschreibung verfügbar.")
                .font(.system(size: 13)).foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }
        .frame(width: side, height: side)
        .background(LinearGradient(colors: [hero.opacity(0.95), Theme.elev], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct EpisodeRow: View {
    let ep: Episode; let track: Track; let playing: Bool; let tap: () -> Void
    @EnvironmentObject var downloads: DownloadManager
    private var durText: String {
        let s = (ep.duration_ms ?? 0) / 1000
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h) Std. \(m) Min." : "\(m) Min."
    }
    private var dateText: String {
        guard let d = ep.release_date, !d.isEmpty else { return "" }
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"; inF.locale = Locale(identifier: "en_US_POSIX")
        guard let date = inF.date(from: d) else { return d }
        let out = DateFormatter(); out.locale = Locale(identifier: "de_DE"); out.dateFormat = "d. MMM yyyy"
        return out.string(from: date)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Artwork(url: ep.image, size: 56, corner: 6)
                VStack(alignment: .leading, spacing: 4) {
                    if !dateText.isEmpty {
                        Text(dateText).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.sub)
                    }
                    Text(ep.name).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(playing ? Theme.accent : Theme.text).lineLimit(2)
                    if let d = ep.description, !d.isEmpty {
                        Text(d).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                Image(systemName: "play.circle.fill").font(.system(size: 30))
                    .foregroundStyle(playing ? Theme.accent : Theme.text)
                Text(durText).font(.system(size: 12)).foregroundStyle(Theme.sub)
                Spacer()
                if downloads.isBusy(track.uri) {
                    ProgressView(value: downloads.progress(for: track.uri))
                        .progressViewStyle(.linear).tint(Theme.accent).frame(width: 70)
                } else {
                    Button { downloads.toggle(track) } label: {
                        Image(systemName: downloads.isDownloaded(track.uri) ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(downloads.isDownloaded(track.uri) ? Theme.accent : Theme.sub)
                    }.buttonStyle(.plain).frame(width: 44, height: 44).contentShape(Rectangle())
                }
            }
        }.padding(.vertical, 12).padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .overlay(Rectangle().fill(Theme.input).frame(height: 0.5), alignment: .bottom)
    }
}

struct NumberedTrackRow: View {
    let n: Int; let track: Track; var showCover: Bool = true; let playing: Bool; let tap: () -> Void
    @State private var showArtist = false
    @State private var showAlbum = false
    @State private var showAddPlaylist = false
    @State private var showSendUser = false
    var body: some View {
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
                TrackMenu(track: track, onShowArtist: { showArtist = true }, onShowAlbum: { showAlbum = true }, onAddToPlaylist: { showAddPlaylist = true }, onSendToUser: { showSendUser = true })
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16)).foregroundStyle(Theme.mute)
                    .frame(width: 46, height: 46).contentShape(Rectangle())
            }
        }.padding(.vertical, 9).padding(.horizontal)
            .background(playing ? Theme.accent.opacity(0.08) : .clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
            .contextMenu { TrackMenu(track: track, onShowArtist: { showArtist = true }, onShowAlbum: { showAlbum = true }, onAddToPlaylist: { showAddPlaylist = true }, onSendToUser: { showSendUser = true }) }
            .trackNavSheets(track: track, showArtist: $showArtist, showAlbum: $showAlbum, showAddPlaylist: $showAddPlaylist, showSendUser: $showSendUser)
    }
}

struct RecRow: View {
    let track: Track; let playing: Bool; let added: Bool; let add: () -> Void; let play: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: track.image, size: 50, corner: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name).font(.system(size: 15)).foregroundStyle(playing ? Theme.accent : Theme.text).lineLimit(1)
                Text(track.artist).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer()
            Button(action: add) {
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 24)).foregroundStyle(added ? Theme.accent : Theme.text)
                    .frame(width: 42, height: 42).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(added)
        }
        .padding(.vertical, 8).padding(.horizontal).contentShape(Rectangle())
        .onTapGesture(perform: play)
    }
}

struct TrackRow: View {
    let track: Track; let playing: Bool; let tap: () -> Void
    @State private var showArtist = false
    @State private var showAlbum = false
    @State private var showAddPlaylist = false
    @State private var showSendUser = false
    var body: some View {
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
                TrackMenu(track: track, onShowArtist: { showArtist = true }, onShowAlbum: { showAlbum = true }, onAddToPlaylist: { showAddPlaylist = true }, onSendToUser: { showSendUser = true })
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16)).foregroundStyle(Theme.mute)
                    .frame(width: 46, height: 46).contentShape(Rectangle())
            }
        }.padding(.vertical, 9).padding(.horizontal)
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
            .contextMenu { TrackMenu(track: track, onShowArtist: { showArtist = true }, onShowAlbum: { showAlbum = true }, onAddToPlaylist: { showAddPlaylist = true }, onSendToUser: { showSendUser = true }) }
            .trackNavSheets(track: track, showArtist: $showArtist, showAlbum: $showAlbum, showAddPlaylist: $showAddPlaylist, showSendUser: $showSendUser)
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
    @Environment(\.liquidGlass) private var glass
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
            .glassSurface(glass, shape: RoundedRectangle(cornerRadius: 8), fallback: Color(hex6: 0x282828))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            .contentShape(Rectangle())   // ganze Leiste tippbar (auch ohne Songtext / mit Glas)
            .onTapGesture { showPlayer = true }
        }
    }
}

// MARK: - Vollbild-Player
struct PlayerView: View {
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var clock: PlaybackClock   // Live-Position (haengt nur hier, nicht an Listen)
    @Environment(\.liquidGlass) private var glass
    @Environment(\.dismiss) private var dismiss
    @State private var scrub: Double = 0
    @State private var scrubbing = false
    @State private var page = 0
    @State private var scrollToLyrics = false
    @State private var hero: Color = Theme.elev
    @State private var showAddPlaylist = false
    @State private var showArtist = false
    @State private var showAlbum = false
    @State private var showSendUser = false

    var body: some View {
        let p = player
        ZStack {
            LinearGradient(colors: [hero.opacity(0.85), Theme.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            TabView(selection: $page) {
             GeometryReader { geo in
              ScrollViewReader { proxy in
               ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                 VStack(spacing: 22) {
                // Obere Leiste: runter / WIEDERGABE+Titel / Menue
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text("WIEDERGABE").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.sub).tracking(1)
                        Text(p.displayTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    }
                    Spacer()
                    Menu {
                        if p.sleepRemaining > 0 || p.sleepAtEnd {
                            Button("Sleep-Timer aus", role: .destructive) { p.cancelSleep() }
                        }
                        Button("15 Minuten") { p.setSleep(minutes: 15) }
                        Button("30 Minuten") { p.setSleep(minutes: 30) }
                        Button("45 Minuten") { p.setSleep(minutes: 45) }
                        Button("60 Minuten") { p.setSleep(minutes: 60) }
                        Button("Ende des Songs") { p.setSleepEndOfTrack() }
                    } label: {
                        Image(systemName: (p.sleepRemaining > 0 || p.sleepAtEnd) ? "moon.fill" : "moon")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle((p.sleepRemaining > 0 || p.sleepAtEnd) ? Theme.accent : Theme.text)
                    }.padding(.trailing, 14)
                    Menu { if let t = p.current { TrackMenu(track: t, onShowArtist: { showArtist = true }, onShowAlbum: { showAlbum = true }, onAddToPlaylist: { showAddPlaylist = true }, onSendToUser: { showSendUser = true }) } } label: {
                        Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
                    }.disabled(p.current == nil)
                }.padding(.horizontal, 4).padding(.top, 8)
                Spacer()
                Artwork(url: p.displayImage, size: 300, corner: 12).shadow(radius: 24)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.displayTitle).font(.title2.bold()).foregroundStyle(Theme.text).lineLimit(1)
                        Text(p.displayArtist).foregroundStyle(Theme.sub).lineLimit(1)
                        if p.isEpisode {
                            SourceBadge(source: "podcast").padding(.top, 4)
                        } else if !p.isRadio && !p.source.isEmpty {
                            SourceBadge(source: p.source).padding(.top, 4)
                        }
                    }
                    Spacer(minLength: 8)
                    if let t = p.current {
                        Button { downloads.toggle(t); Haptics.tap() } label: {
                            Image(systemName: downloads.isDownloaded(t.uri) ? "arrow.down.circle.fill" : "arrow.down.circle")
                                .font(.system(size: 24))
                                .foregroundStyle(downloads.isDownloaded(t.uri) ? Theme.accent : Theme.text)
                        }
                        Button { player.addToQueue(t); Haptics.tap() } label: {
                            Image(systemName: "plus.circle").font(.system(size: 26)).foregroundStyle(Theme.text)
                        }
                    }
                }.padding(.horizontal, 4)
                if !p.isRadio {
                    VStack(spacing: 2) {
                        Slider(value: Binding(get: { scrubbing ? scrub : clock.time }, set: { scrub = $0 }),
                               in: 0...max(clock.duration, 1), onEditingChanged: { e in scrubbing = e; if !e { p.seek(scrub) } })
                            .tint(Theme.accent)
                        HStack {
                            Text(fmt(scrubbing ? scrub : clock.time)).font(.caption2).foregroundStyle(Theme.sub)
                            Spacer()
                            Text(fmt(clock.duration)).font(.caption2).foregroundStyle(Theme.sub)
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
                                if glass {
                                    Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 30)).foregroundStyle(Theme.text)
                                        .frame(width: 78, height: 78)
                                        .glassButton(true, shape: Circle(), fallback: .clear)
                                } else {
                                    Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 72))
                                }
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
                    HStack(spacing: 30) {
                        Button { scrollToLyrics = true } label: { Label("Songtext", systemImage: "quote.bubble").font(.system(size: 15, weight: .semibold)) }
                        AirPlayButton().frame(width: 30, height: 30)
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
                 }.padding().frame(height: geo.size.height).id("player")
                 LyricsView().frame(minHeight: geo.size.height, alignment: .top)
                    .background(Theme.bg).id("lyrics")
                }
               }
               .onChange(of: scrollToLyrics) { go in
                   if go { withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("lyrics", anchor: .top) }; scrollToLyrics = false }
               }
              }
             }.tag(0)
             QueuePage(page: $page).tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showAddPlaylist) { if let t = player.current { AddToPlaylistSheet(track: t) } }
        .sheet(isPresented: $showSendUser) { if let t = player.current { SendToUserSheet(track: t) } }
        .sheet(isPresented: $showArtist) {
            if let t = player.current, let u = t.artists?.first?.uri {
                NavigationStack { ArtistView(uri: u, name: t.artists?.first?.name ?? t.artist, image: t.image) }
            }
        }
        .sheet(isPresented: $showAlbum) {
            if let t = player.current, let u = t.album_uri {
                NavigationStack { TrackListView(uri: u, title: t.album ?? "Album", image: t.image, isAlbum: true) }
            }
        }
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
                                .onTapGesture { player.playUpNext(i) }
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
/// Songtext als Scroll-Sektion unter dem Player (hochwischen scrollt hin).
struct LyricsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var clock: PlaybackClock
    @State private var lines: [(t: Double, s: String)] = []   // synced LRC
    @State private var plain = "Lade Songtext…"
    @State private var hasSynced = false

    private var currentIndex: Int {
        guard hasSynced else { return -1 }
        var idx = -1
        for (i, l) in lines.enumerated() { if l.t <= clock.time + 0.2 { idx = i } else { break } }
        return idx
    }

    var body: some View {
        VStack(alignment: .leading, spacing: hasSynced ? 12 : 14) {
            HStack(spacing: 8) {
                Text("Songtext").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text)
                if hasSynced {
                    Image(systemName: "waveform").font(.system(size: 13)).foregroundStyle(Theme.accent)
                }
            }
            if hasSynced {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                    if !l.s.isEmpty {
                        Text(l.s)
                            .font(.system(size: 19, weight: i == currentIndex ? .bold : .medium))
                            .foregroundStyle(i == currentIndex ? Theme.text : Theme.sub.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { player.seek(l.t) }   // antippen -> dahin springen
                    }
                }
            } else {
                Text(plain).font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24).padding(.bottom, 60)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: player.current?.id) { await load() }
    }

    private func load() async {
        hasSynced = false; lines = []; plain = "Lade Songtext…"
        guard let t = player.current else { plain = "Kein Song"; return }
        guard let ly = try? await app.api.lyrics(title: t.name, artist: t.artist, duration: Int(t.durationSec)) else {
            plain = "Kein Songtext gefunden"; return
        }
        if let synced = ly.synced, !synced.isEmpty {
            let parsed = parseLRC(synced)
            if parsed.count > 2 { lines = parsed; hasSynced = true; return }
        }
        plain = (ly.lyrics?.isEmpty == false) ? ly.lyrics! :
                (ly.instrumental == true ? "🎵 Instrumental" : "Kein Songtext gefunden")
    }

    /// LRC parsen: [mm:ss.xx] Text  (mehrere Stamps pro Zeile moeglich).
    private func parseLRC(_ lrc: String) -> [(t: Double, s: String)] {
        var out: [(Double, String)] = []
        for raw in lrc.split(separator: "\n") {
            var rest = String(raw)
            var stamps: [Double] = []
            while rest.hasPrefix("[") {
                guard let close = rest.firstIndex(of: "]") else { break }
                let tag = String(rest[rest.index(after: rest.startIndex)..<close])
                rest = String(rest[rest.index(after: close)...])
                let parts = tag.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                    stamps.append(m * 60 + s)
                }
            }
            let txt = rest.trimmingCharacters(in: .whitespaces)
            for st in stamps { out.append((st, txt)) }
        }
        return out.sorted { $0.0 < $1.0 }.map { (t: $0.0, s: $0.1) }
    }
}

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
        case "podcast":   label = "Podcast";    color = Theme.sub
        case "offline":   label = "Offline";    color = Color(hex6: 0x4A90E2)
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
/// In-Memory-Cache fuer dekodierte Bilder -> fluessiges Scrollen, kein Re-Download.
final class ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSURL, UIImage>()
    init() { cache.countLimit = 400 }   // NSCache ist thread-safe
    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func load(_ url: URL) async -> UIImage? {
        if let c = cached(url) { return c }
        guard let (d, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: d) else { return nil }
        cache.setObject(img, forKey: url as NSURL)
        return img
    }
}

struct Artwork: View {
    let url: String?
    var size: CGFloat = 48
    var corner: CGFloat = 6
    @State private var image: UIImage?
    private var resolved: URL? {
        guard let s = url, !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: ImageBase.url + (s.hasPrefix("/") ? s : "/" + s))
    }
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: corner).fill(Theme.card)
                    .overlay(Image(systemName: "music.note").foregroundStyle(Theme.mute))
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: corner))
        .task(id: resolved) {
            guard let u = resolved else { image = nil; return }
            if let c = ImageLoader.shared.cached(u) { image = c; return }   // sofort aus Cache
            image = nil
            if let img = await ImageLoader.shared.load(u), u == resolved { image = img }
        }
    }
}
