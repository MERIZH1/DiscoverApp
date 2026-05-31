import SwiftUI
import UIKit

// MARK: - UIKit-Appearance (schwarze Nav/Tab-Bars)
func configureAppearance() {
    let nav = UINavigationBarAppearance()
    nav.configureWithOpaqueBackground()
    nav.backgroundColor = .black
    nav.shadowColor = .clear
    nav.titleTextAttributes = [.foregroundColor: UIColor.white]
    nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
    UINavigationBar.appearance().standardAppearance = nav
    UINavigationBar.appearance().scrollEdgeAppearance = nav
    UINavigationBar.appearance().compactAppearance = nav

    let tab = UITabBarAppearance()
    tab.configureWithOpaqueBackground()
    tab.backgroundColor = .black
    tab.shadowColor = .clear
    UITabBar.appearance().standardAppearance = tab
    UITabBar.appearance().scrollEdgeAppearance = tab
}

// MARK: - Haupt-Tab-View mit Now-Playing-Bar
struct MainView: View {
    @EnvironmentObject var player: PlayerController
    @State private var showPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                HomeView().tabItem { Label("Home", systemImage: "house.fill") }
                LibraryView().tabItem { Label("Bibliothek", systemImage: "music.note.list") }
                SearchView().tabItem { Label("Suche", systemImage: "magnifyingglass") }
            }
            .tint(Theme.accent)
            if player.current != nil {
                NowPlayingBar(showPlayer: $showPlayer)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 50)
            }
        }
        .onAppear(perform: configureAppearance)
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
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(quick) { item in
                            NavigationLink(value: item) {
                                HStack(spacing: 8) {
                                    Artwork(url: item.image, size: 52, corner: 4)
                                    Text(item.name).font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal).padding(.top, 8).padding(.bottom, 130)
                } else {
                    ProgressView().tint(Theme.accent).padding(.top, 80)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(home?.greeting ?? "Discover")
            .navigationDestination(for: HomeItem.self) { item in
                TrackListView(uri: item.uri, title: item.name,
                              image: item.image, isAlbum: item.type == "album")
            }
        }
        .task { if home == nil { home = try? await app.api.home() } }
    }
}

// MARK: - Bibliothek
struct LibraryView: View {
    @EnvironmentObject var app: AppState
    @State private var playlists: [Playlist] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(playlists) { pl in
                        NavigationLink(value: pl) {
                            HStack(spacing: 12) {
                                Artwork(url: pl.image, size: 56, corner: 6)
                                Text(pl.name).font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text).lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6).padding(.horizontal)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.top, 6).padding(.bottom, 130)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Bibliothek")
            .navigationDestination(for: Playlist.self) { pl in
                TrackListView(uri: pl.uri, title: pl.name, image: pl.image, isAlbum: false)
            }
            .refreshable { playlists = (try? await app.api.playlists()) ?? playlists }
        }
        .task { if playlists.isEmpty { playlists = (try? await app.api.playlists()) ?? [] } }
    }
}

// MARK: - Track-Liste (Playlist/Album) mit Header
struct TrackListView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerController
    let uri: String
    let title: String
    let image: String?
    let isAlbum: Bool
    @State private var tracks: [Track] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Artwork(url: image, size: 200, corner: 8).shadow(radius: 16).padding(.top, 8)
                Text(title).font(.title3.bold()).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center).padding(.horizontal)
                Button {
                    if !tracks.isEmpty { player.play(tracks: tracks, startAt: 0) }
                } label: {
                    Label("Abspielen", systemImage: "play.fill")
                        .font(.headline).foregroundStyle(.black)
                        .padding(.horizontal, 40).padding(.vertical, 12)
                        .background(Theme.accent).clipShape(Capsule())
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, t in
                        Button { player.play(tracks: tracks, startAt: idx) } label: {
                            HStack(spacing: 12) {
                                Artwork(url: t.image, size: 46, corner: 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name).font(.system(size: 15))
                                        .foregroundStyle(player.current?.id == t.id ? Theme.accent : Theme.text)
                                        .lineLimit(1)
                                    Text(t.artist).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                                }
                                Spacer()
                                if t.downloaded == true {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.caption).foregroundStyle(Theme.accent.opacity(0.7))
                                }
                            }
                            .padding(.vertical, 7).padding(.horizontal)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.bottom, 130)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .overlay { if loading { ProgressView().tint(Theme.accent) } }
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
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(Theme.mute)
                Text("Suche kommt als Naechstes").foregroundStyle(Theme.mute)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Suche")
        }
    }
}

// MARK: - Now-Playing-Bar
struct NowPlayingBar: View {
    @EnvironmentObject var player: PlayerController
    @Binding var showPlayer: Bool

    var body: some View {
        if let t = player.current {
            HStack(spacing: 12) {
                Artwork(url: t.image, size: 42, corner: 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(t.artist).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).foregroundStyle(Theme.text)
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title3).foregroundStyle(Theme.text)
                }.padding(.trailing, 4)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { showPlayer = true }
        }
    }
}

// MARK: - Vollbild-Player
struct PlayerView: View {
    @EnvironmentObject var player: PlayerController
    @State private var scrub: Double = 0
    @State private var scrubbing = false

    var body: some View {
        let p = player
        ZStack {
            LinearGradient(colors: [Theme.elev, Theme.bg], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 26) {
                Capsule().fill(Theme.mute).frame(width: 38, height: 5).padding(.top, 8)
                Spacer()
                Artwork(url: p.current?.image, size: 300, corner: 12).shadow(radius: 24)
                VStack(spacing: 6) {
                    Text(p.current?.name ?? "").font(.title2.bold()).foregroundStyle(Theme.text).lineLimit(1)
                    Text(p.current?.artist ?? "").foregroundStyle(Theme.sub).lineLimit(1)
                }
                VStack(spacing: 2) {
                    Slider(value: Binding(
                        get: { scrubbing ? scrub : p.currentTime },
                        set: { scrub = $0 }
                    ), in: 0...max(p.duration, 1), onEditingChanged: { editing in
                        scrubbing = editing
                        if !editing { p.seek(scrub) }
                    })
                    .tint(Theme.accent)
                    HStack {
                        Text(fmt(scrubbing ? scrub : p.currentTime)).font(.caption2).foregroundStyle(Theme.sub)
                        Spacer()
                        Text(fmt(p.duration)).font(.caption2).foregroundStyle(Theme.sub)
                    }
                }.padding(.horizontal)
                HStack(spacing: 50) {
                    Button { p.prev() } label: { Image(systemName: "backward.fill").font(.title) }
                    Button { p.toggle() } label: {
                        Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72))
                    }
                    Button { p.next() } label: { Image(systemName: "forward.fill").font(.title) }
                }.foregroundStyle(Theme.text)
                Spacer()
            }
            .padding()
        }
        .presentationDragIndicator(.hidden)
    }

    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
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
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}
