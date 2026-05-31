import SwiftUI

// MARK: - Haupt-Tab-View mit Now-Playing-Bar
struct MainView: View {
    @EnvironmentObject var app: AppState
    @State private var showPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                HomeView().tabItem { Label("Home", systemImage: "house.fill") }
                LibraryView().tabItem { Label("Bibliothek", systemImage: "music.note.list") }
                SearchView().tabItem { Label("Suche", systemImage: "magnifyingglass") }
            }
            if app.player.current != nil {
                NowPlayingBar(showPlayer: $showPlayer)
                    .padding(.bottom, 49) // ueber der Tab-Bar
            }
        }
        .sheet(isPresented: $showPlayer) { PlayerView() }
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
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(quick) { item in
                            NavigationLink(value: item) {
                                HStack(spacing: 8) {
                                    Artwork(url: item.image, size: 48, corner: 6)
                                    Text(item.name).font(.subheadline.bold())
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(6).background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }.padding()
                } else {
                    ProgressView().padding(.top, 60)
                }
            }
            .navigationTitle(home?.greeting ?? "Discover")
            .navigationDestination(for: HomeItem.self) { item in
                TrackListView(uri: item.uri, title: item.name, isAlbum: item.type == "album")
            }
            .padding(.bottom, 70)
        }
        .task {
            if home == nil { home = try? await app.api.home() }
        }
    }
}

// MARK: - Bibliothek (Playlists)
struct LibraryView: View {
    @EnvironmentObject var app: AppState
    @State private var playlists: [Playlist] = []

    var body: some View {
        NavigationStack {
            List(playlists) { pl in
                NavigationLink(value: pl) {
                    HStack(spacing: 12) {
                        Artwork(url: pl.image, size: 52, corner: 6)
                        Text(pl.name).font(.body)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Bibliothek")
            .navigationDestination(for: Playlist.self) { pl in
                TrackListView(uri: pl.uri, title: pl.name, isAlbum: false)
            }
            .refreshable { playlists = (try? await app.api.playlists()) ?? playlists }
            .padding(.bottom, 70)
        }
        .task { if playlists.isEmpty { playlists = (try? await app.api.playlists()) ?? [] } }
    }
}

// MARK: - Track-Liste (Playlist oder Album)
struct TrackListView: View {
    @EnvironmentObject var app: AppState
    let uri: String
    let title: String
    let isAlbum: Bool
    @State private var tracks: [Track] = []
    @State private var loading = true

    var body: some View {
        List {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, t in
                Button { app.player.play(tracks: tracks, startAt: idx) } label: {
                    HStack(spacing: 12) {
                        Artwork(url: t.image, size: 46, corner: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).lineLimit(1)
                                .foregroundStyle(app.player.current?.id == t.id ? Color.green : .primary)
                            Text(t.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if t.downloaded == true {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption).foregroundStyle(.green.opacity(0.7))
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .overlay { if loading { ProgressView() } }
        .padding(.bottom, 70)
        .task {
            loading = true
            let resp = isAlbum
                ? try? await app.api.albumTracks(uri)
                : try? await app.api.playlistTracks(uri, check: true)
            tracks = resp?.tracks ?? []
            loading = false
        }
    }
}

// MARK: - Suche (Basis)
struct SearchView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableViewCompat(text: "Suche kommt als Naechstes")
                .navigationTitle("Suche")
        }
    }
}

// MARK: - Now-Playing-Bar
struct NowPlayingBar: View {
    @EnvironmentObject var app: AppState
    @Binding var showPlayer: Bool

    var body: some View {
        if let t = app.player.current {
            HStack(spacing: 12) {
                Artwork(url: t.image, size: 42, corner: 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.name).font(.subheadline.bold()).lineLimit(1)
                    Text(t.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { app.player.toggle() } label: {
                    Image(systemName: app.player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                Button { app.player.next() } label: {
                    Image(systemName: "forward.fill").font(.title3)
                }.padding(.trailing, 4)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 8)
            .onTapGesture { showPlayer = true }
        }
    }
}

// MARK: - Vollbild-Player
struct PlayerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var scrub: Double = 0
    @State private var scrubbing = false

    var body: some View {
        let p = app.player
        VStack(spacing: 28) {
            Capsule().fill(.secondary).frame(width: 40, height: 5).padding(.top, 8)
            Spacer()
            Artwork(url: p.current?.image, size: 300, corner: 14)
                .shadow(radius: 20)
            VStack(spacing: 6) {
                Text(p.current?.name ?? "").font(.title2.bold()).lineLimit(1)
                Text(p.current?.artist ?? "").foregroundStyle(.secondary).lineLimit(1)
            }
            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { scrubbing ? scrub : p.currentTime },
                    set: { scrub = $0 }
                ), in: 0...max(p.duration, 1), onEditingChanged: { editing in
                    scrubbing = editing
                    if !editing { p.seek(scrub) }
                })
                .tint(.green)
                HStack {
                    Text(fmt(scrubbing ? scrub : p.currentTime)).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(fmt(p.duration)).font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.horizontal)
            HStack(spacing: 44) {
                Button { p.prev() } label: { Image(systemName: "backward.fill").font(.title) }
                Button { p.toggle() } label: {
                    Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 68))
                }
                Button { p.next() } label: { Image(systemName: "forward.fill").font(.title) }
            }.foregroundStyle(.primary)
            Spacer()
        }
        .padding()
        .presentationDragIndicator(.hidden)
    }

    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let m = Int(s) / 60, sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - kleine Helfer
struct Artwork: View {
    let url: String?
    var size: CGFloat = 48
    var corner: CGFloat = 6
    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(.gray.opacity(0.3))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}

struct ContentUnavailableViewCompat: View {
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
