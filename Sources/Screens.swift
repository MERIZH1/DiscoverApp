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
            .tint(Theme.accent)
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
    let text: String; let active: Bool; let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            Text(text).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? .black : Theme.text)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(active ? Theme.accent : Theme.input)
                .clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}

// MARK: - Home
struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var home: HomeResponse?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let quick = home?.quick {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(quick) { item in
                            NavigationLink(value: item) {
                                HStack(spacing: 8) {
                                    Artwork(url: item.image, size: 52, corner: 4)
                                    Text(item.name).font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Theme.text).lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal).padding(.top, 8).padding(.bottom, 130)
                } else {
                    ProgressView().tint(Theme.accent).padding(.top, 80)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle(home?.greeting ?? "Discover")
            .navigationDestination(for: HomeItem.self) { item in
                TrackListView(uri: item.uri, title: item.name, image: item.image, isAlbum: item.type == "album")
            }
        }
        .task { if home == nil { home = try? await app.api.home() } }
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
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.mute)
                    TextField("Songs, Künstler suchen…", text: $query)
                        .foregroundStyle(Theme.text)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .onSubmit { runSearch() }
                    if !query.isEmpty {
                        Button { query = ""; res = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.mute) }
                    }
                }
                .padding(10).background(Theme.input).clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)

                if res != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["all","tracks","playlists","albums","artists"], id: \.self) { s in
                                Pill(text: label(s), active: scope == s) { scope = s }
                            }
                        }.padding(.horizontal)
                    }
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
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(Theme.mute)
                            Text("Such nach einem Song").foregroundStyle(Theme.mute)
                        }.padding(.top, 80)
                    }
                }
                .scrollContentBackground(.hidden)
            }
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
    @State private var filter = ""

    var shown: [Playlist] {
        filter.isEmpty ? playlists : playlists.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.mute)
                    TextField("In Bibliothek suchen", text: $filter).foregroundStyle(Theme.text)
                }.padding(10).background(Theme.input).clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal).padding(.top, 4)
                LazyVStack(spacing: 2) {
                    ForEach(shown) { pl in
                        NavigationLink(value: pl) {
                            HStack(spacing: 12) {
                                Artwork(url: pl.image, size: 56, corner: 6)
                                Text(pl.name).font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text).lineLimit(2)
                                Spacer(minLength: 0)
                            }.padding(.vertical, 6).padding(.horizontal).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.top, 6).padding(.bottom, 130)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Bibliothek")
            .navigationDestination(for: Playlist.self) { pl in
                TrackListView(uri: pl.uri, title: pl.name, image: pl.image, isAlbum: false)
            }
            .refreshable { playlists = (try? await app.api.playlists()) ?? playlists }
        }
        .task { if playlists.isEmpty { playlists = (try? await app.api.playlists()) ?? [] } }
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
                LazyVStack(spacing: 2) {
                    ForEach(stations) { st in
                        Button { player.playRadio(st) } label: {
                            HStack(spacing: 12) {
                                Artwork(url: st.favicon, size: 50, corner: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(st.name).font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Theme.text).lineLimit(1)
                                    Text(st.country ?? "Live-Radio").font(.caption).foregroundStyle(Theme.sub)
                                }
                                Spacer()
                                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Theme.accent)
                            }.padding(.vertical, 7).padding(.horizontal).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.top, 6).padding(.bottom, 130)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Live-Radio")
            .overlay { if stations.isEmpty { ProgressView().tint(Theme.accent) } }
        }
        .task { if stations.isEmpty { stations = (try? await app.api.radioFavorites()) ?? [] } }
    }
}

// MARK: - Track-Liste
struct TrackListView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    let uri: String; let title: String; let image: String?; let isAlbum: Bool
    @State private var tracks: [Track] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Artwork(url: image, size: 200, corner: 8).shadow(radius: 16).padding(.top, 8)
                Text(title).font(.title3.bold()).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center).padding(.horizontal)
                HStack(spacing: 16) {
                    Button { player.shuffle = true; if !tracks.isEmpty { player.play(tracks: tracks.shuffled()) } } label: {
                        Image(systemName: "shuffle").font(.title3).foregroundStyle(Theme.text)
                    }
                    Button { if !tracks.isEmpty { player.shuffle = false; player.play(tracks: tracks, startAt: 0) } } label: {
                        Label("Abspielen", systemImage: "play.fill").font(.headline).foregroundStyle(.black)
                            .padding(.horizontal, 40).padding(.vertical, 12)
                            .background(Theme.accent).clipShape(Capsule())
                    }
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, t in
                        TrackRow(track: t, playing: player.current?.id == t.id) {
                            player.play(tracks: tracks, startAt: idx)
                        }
                    }
                }.padding(.bottom, 130)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .overlay { if loading { ProgressView().tint(Theme.accent) } }
        .task {
            loading = true
            let resp = isAlbum ? try? await app.api.albumTracks(uri) : try? await app.api.playlistTracks(uri, check: true)
            tracks = resp?.tracks ?? []; loading = false
        }
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
                Artwork(url: player.displayImage, size: 42, corner: 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.displayTitle).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(player.displayArtist).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).foregroundStyle(Theme.text)
                }
                if !player.isRadio {
                    Button { player.next() } label: { Image(systemName: "forward.fill").font(.title3).foregroundStyle(Theme.text) }
                        .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
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

    var body: some View {
        let p = player
        ZStack {
            LinearGradient(colors: [Theme.elev, Theme.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
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
