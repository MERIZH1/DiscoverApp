import SwiftUI
import UIKit

// MARK: - Appearance
func configureAppearance() {
    let nav = UINavigationBarAppearance()
    nav.configureWithOpaqueBackground()
    nav.backgroundColor = .black; nav.shadowColor = .clear
    nav.titleTextAttributes = [.foregroundColor: UIColor.white]
    nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
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
    let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            Text(text).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? .black : Theme.text)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(active ? activeBg : Theme.input)
                .clipShape(Capsule())
        }.buttonStyle(.plain)
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
                        HomeRow(title: "Zuletzt geoeffnet", subtitle: nil, items: recents)
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
                TrackListView(uri: item.uri, title: item.name, image: item.image, isAlbum: item.type == "album")
            }
        }
        .sheet(isPresented: $showAccount) { AccountSheet() }
        .task {
            if home == nil { home = try? await app.api.home() }
            if recents.isEmpty { recents = (try? await app.api.recents()) ?? [] }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        AvatarCircle(name: app.profile?.name ?? "?", size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.profile?.name ?? "Profil").font(.title3.bold()).foregroundStyle(Theme.text)
                            Text(app.serverURL).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                        }
                    }.padding(.horizontal).padding(.top, 8).padding(.bottom, 6)

                    Text("PROFIL WECHSELN").font(.caption2.bold()).foregroundStyle(Theme.mute)
                        .padding(.horizontal).padding(.top, 8)
                    ForEach(profiles) { p in
                        Button { app.switchProfile(p); dismiss() } label: {
                            HStack(spacing: 12) {
                                AvatarCircle(name: p.name, size: 36)
                                Text(p.name).font(.system(size: 16)).foregroundStyle(Theme.text)
                                Spacer()
                                if p.id == app.profile?.id {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }.padding(.vertical, 8).padding(.horizontal).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }

                    Divider().background(Theme.input).padding(.vertical, 8)

                    AccountAction(icon: "person.2.fill", label: "Profil abmelden") { app.clearProfile(); dismiss() }
                    AccountAction(icon: "server.rack", label: "Server aendern") { app.changeServer(); dismiss() }

                    Text("Discover · native iOS-App").font(.caption2).foregroundStyle(Theme.mute)
                        .frame(maxWidth: .infinity).padding(.top, 24)
                }.padding(.bottom, 30)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }.foregroundStyle(Theme.accent)
            } }
        }
        .task { profiles = (try? await app.api.profiles()) ?? [] }
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
                        ForEach(["all","tracks","playlists","albums","artists"], id: \.self) { s in
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
                TrackListView(uri: c.uri, title: c.name, image: c.image, isAlbum: c.uri.contains(":album:"))
            }
        }
    }
    private func label(_ s: String) -> String {
        ["all":"Alle","tracks":"Songs","playlists":"Playlists","albums":"Alben","artists":"Künstler"][s] ?? s
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
    @State private var playlists: [Playlist] = []
    @State private var subs: Set<String> = []
    @State private var subSync: [String: String] = [:]
    @State private var filter = ""
    @State private var tab = "all"

    var shown: [Playlist] {
        var list = playlists
        if tab == "subs" { list = list.filter { subs.contains($0.uri) } }
        if tab == "az" { list = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        if !filter.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(filter) } }
        return list
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
                        ForEach([("all","Alle"),("subs","Abos"),("az","A–Z")], id: \.0) { f in
                            Pill(text: f.1, active: tab == f.0, activeBg: Theme.accent) { tab = f.0 }
                        }
                    }.padding(.horizontal)
                }.padding(.top, 10)

                LazyVStack(spacing: 2) {
                    // Liked Songs (Spezial)
                    LikedSongsRow()
                    ForEach(shown) { pl in
                        NavigationLink(value: pl) {
                            HStack(spacing: 12) {
                                ZStack(alignment: .bottomLeading) {
                                    Artwork(url: pl.image, size: 56, corner: 6)
                                    if subs.contains(pl.uri) {
                                        Image(systemName: "bell.fill").font(.system(size: 10)).foregroundStyle(.black)
                                            .padding(5).background(Circle().fill(Theme.accent)).offset(x: -3, y: 3)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pl.name).font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Theme.text).lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(subs.contains(pl.uri) ? "Abo" : "Playlist")
                                            .font(.system(size: 13))
                                            .foregroundStyle(subs.contains(pl.uri) ? Theme.accent : Theme.sub)
                                        if let s = subSync[pl.uri] {
                                            Text("· sync \(s)").font(.system(size: 13)).foregroundStyle(Theme.sub)
                                        }
                                    }
                                }
                                Spacer(minLength: 0)
                            }.padding(.vertical, 6).padding(.horizontal).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.top, 10).padding(.bottom, 130)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Meine Bibliothek")
            .navigationDestination(for: Playlist.self) { pl in
                TrackListView(uri: pl.uri, title: pl.name, image: pl.image, isAlbum: false)
            }
            .refreshable { await load() }
        }
        .task { if playlists.isEmpty { await load() } }
    }
    private func load() async {
        async let pls = app.api.playlists()
        async let sub = app.api.subscriptions()
        playlists = (try? await pls) ?? playlists
        if let s = try? await sub {
            subs = Set(s.map { $0.uri })
            subSync = Dictionary(uniqueKeysWithValues: s.compactMap { i in i.last_sync.map { (i.uri, $0) } })
        }
    }
}

struct LikedSongsRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(hex6: 0x8E8EE8), Color(hex6: 0x5050C0)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "heart.fill").foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("Liked Songs").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Playlist").font(.system(size: 13)).foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 6).padding(.horizontal)
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
                        Button { player.playRadio(st) } label: {
                            HStack(spacing: 12) {
                                Artwork(url: st.favicon, size: 50, corner: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(st.name).font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(player.isRadio && player.displayTitle == st.name ? Theme.accent : Theme.text).lineLimit(1)
                                    Text(st.country ?? "Live-Radio").font(.system(size: 13)).foregroundStyle(Theme.sub)
                                }
                                Spacer()
                                Image(systemName: "star.fill").foregroundStyle(Theme.accent)
                            }.padding(.vertical, 7).padding(.horizontal).contentShape(Rectangle())
                        }.buttonStyle(.plain)
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
    let uri: String; let title: String; let image: String?; let isAlbum: Bool
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var hero: Color = Theme.elev

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero
                VStack(spacing: 14) {
                    Artwork(url: image, size: 210, corner: 6).shadow(color: .black.opacity(0.6), radius: 30, y: 8).padding(.top, 12)
                    Text(title).font(.system(size: 26, weight: .black)).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    Text("\(isAlbum ? "Album" : "Playlist") · \(tracks.count) Songs")
                        .font(.system(size: 13)).foregroundStyle(Theme.sub)
                    // Aktions-Reihe
                    HStack {
                        Image(systemName: "arrow.down.circle").font(.title2).foregroundStyle(Theme.sub)
                        Image(systemName: "ellipsis").font(.title3).foregroundStyle(Theme.sub).padding(.leading, 14)
                        Spacer()
                        Button { if !tracks.isEmpty { player.shuffle = true; player.play(tracks: tracks.shuffled()) } } label: {
                            Image(systemName: "shuffle").font(.title2).foregroundStyle(Theme.text)
                        }.padding(.trailing, 18)
                        Button { if !tracks.isEmpty { player.shuffle = false; player.play(tracks: tracks, startAt: 0) } } label: {
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
                        NumberedTrackRow(n: idx + 1, track: t, playing: player.current?.id == t.id) {
                            player.shuffle = false; player.play(tracks: tracks, startAt: idx)
                        }
                    }
                }.padding(.bottom, 130).padding(.top, 6)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .overlay { if loading { ProgressView().tint(Theme.accent) } }
        .task {
            loading = true
            let absImg = image.flatMap { app.api.absoluteURL($0)?.absoluteString } ?? image
            if let c = await averageColor(absImg) { hero = c }
            let resp = isAlbum ? try? await app.api.albumTracks(uri) : try? await app.api.playlistTracks(uri, check: true)
            tracks = resp?.tracks ?? []; loading = false
        }
    }
}

struct NumberedTrackRow: View {
    let n: Int; let track: Track; let playing: Bool; let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Text("\(n)").font(.system(size: 13).monospacedDigit()).foregroundStyle(playing ? Theme.accent : Theme.sub)
                    .frame(width: 24, alignment: .trailing)
                Artwork(url: track.image, size: 48, corner: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).font(.system(size: 15, weight: .regular))
                        .foregroundStyle(playing ? Theme.accent : Theme.text).lineLimit(1)
                    Text(track.artist).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer()
                if track.downloaded == true {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
                }
                Image(systemName: "ellipsis").font(.system(size: 15)).foregroundStyle(Theme.mute).padding(.leading, 6)
            }.padding(.vertical, 7).padding(.horizontal).contentShape(Rectangle())
                .background(playing ? Theme.accent.opacity(0.08) : .clear)
        }.buttonStyle(.plain)
    }
}

struct TrackRow: View {
    let track: Track; let playing: Bool; let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Artwork(url: track.image, size: 46, corner: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).font(.system(size: 15))
                        .foregroundStyle(playing ? Theme.accent : Theme.text).lineLimit(1)
                    Text(track.artist).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer()
                if track.downloaded == true {
                    Image(systemName: "arrow.down.circle.fill").font(.caption).foregroundStyle(Theme.accent.opacity(0.7))
                }
            }.padding(.vertical, 7).padding(.horizontal).contentShape(Rectangle())
        }.buttonStyle(.plain)
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
                    Text(player.displayArtist).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).foregroundStyle(.black)
                        .frame(width: 38, height: 38).background(.white).clipShape(Circle())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(hex6: 0x2A2A2A)).clipShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { showPlayer = true }
        }
    }
}

// MARK: - Vollbild-Player
struct PlayerView: View {
    @EnvironmentObject var player: PlayerController
    @State private var scrub: Double = 0
    @State private var scrubbing = false
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var hero: Color = Theme.elev

    var body: some View {
        let p = player
        ZStack {
            LinearGradient(colors: [hero.opacity(0.85), Theme.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 22) {
                Capsule().fill(Theme.mute).frame(width: 38, height: 5).padding(.top, 8)
                Spacer()
                Artwork(url: p.displayImage, size: 300, corner: 12).shadow(radius: 24)
                VStack(spacing: 6) {
                    Text(p.displayTitle).font(.title2.bold()).foregroundStyle(Theme.text).lineLimit(1)
                    Text(p.displayArtist).foregroundStyle(Theme.sub).lineLimit(1)
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
                    HStack(spacing: 50) {
                        Button { showLyrics = true } label: { Label("Songtext", systemImage: "quote.bubble").font(.subheadline) }
                        Button { showQueue = true } label: { Label("Warteschlange", systemImage: "list.bullet").font(.subheadline) }
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
            }.padding()
        }
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showQueue) { QueueSheet() }
        .sheet(isPresented: $showLyrics) { LyricsSheet() }
        .task(id: player.displayImage) { if let c = await averageColor(player.displayImage) { hero = c } }
    }
    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(s)/60, Int(s)%60)
    }
}

// MARK: - Warteschlange
struct QueueSheet: View {
    @EnvironmentObject var player: PlayerController
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("Warteschlange").font(.title3.bold()).foregroundStyle(Theme.text).padding()
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { i, t in
                        TrackRow(track: t, playing: i == player.index) { player.playAt(i) }
                    }
                }.padding(.bottom, 40)
            }.scrollContentBackground(.hidden)
        }
        .presentationDetents([.medium, .large])
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

// MARK: - Cover
struct Artwork: View {
    let url: String?
    var size: CGFloat = 48
    var corner: CGFloat = 6
    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: corner).fill(Theme.card)
                .overlay(Image(systemName: "music.note").foregroundStyle(Theme.mute))
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: corner))
    }
}
