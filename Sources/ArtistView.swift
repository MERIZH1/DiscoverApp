import SwiftUI
import UIKit

// MARK: - Künstlerseite wie bei Spotify
// Titelbild über die volle Breite (zieht sich beim Herunterziehen mit), Name groß
// darauf, darunter monatliche Hörer*innen, Zufall und Play. Dann Beliebt,
// Veröffentlichungen, „Fans mögen auch“ und „Über“.
struct ArtistView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.playerRef) private var playerRef
    private var player: PlayerController { playerRef! }
    @EnvironmentObject var now: NowPlayingState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.liquidGlass) private var glass
    let uri: String; let name: String; let image: String?
    @State private var resp: ArtistResponse?
    @State private var retry = 0
    @State private var loading = true
    @State private var tint: Color = Theme.elev
    @State private var showAllTop = false
    @State private var bioOpen = false
    @State private var scrollY: CGFloat = 0
    /// Höhe von Statusleiste und Navigationsleiste. Die ScrollView rückt ihren Inhalt um
    /// diesen Wert ein, das Titelbild soll aber bis ganz nach oben reichen.
    @State private var insetScroll: CGFloat = 0
    @State private var insetSafe: CGFloat = 0
    private var topInset: CGFloat { max(insetScroll, insetSafe) }

    private let heroH: CGFloat = 380
    private var top: [Track] { resp?.top_tracks ?? [] }
    private var title: String { resp?.name ?? name }
    private var heroURL: String? {
        [resp?.header_image, resp?.avatar, resp?.image, image].compactMap { $0 }.first { !$0.isEmpty }
    }
    /// Ab hier steht der Name klein oben in der Leiste.
    private var collapsed: Bool { scrollY > heroH - 130 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                content
                    .background(
                        LinearGradient(colors: [tint.opacity(0.55), Theme.bg], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
                    )
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
            scrollY = y
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, v in
            insetScroll = v
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { v in
            insetSafe = v
        }
        .ignoresSafeArea(edges: .top)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(collapsed ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(tint.mix(with: .black, by: 0.45), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .glassButton(glass, shape: Circle(), fallback: .black.opacity(0.42))
                        .contentShape(Circle())
                }.buttonStyle(.pressable).accessibilityLabel("Zurück")
            }
            ToolbarItem(placement: .principal) {
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    .opacity(collapsed ? 1 : 0).animation(.easeOut(duration: 0.18), value: collapsed)
            }
        }
        .overlay {
            if loading && resp == nil { LoadingView() }
            else if !loading && resp == nil { LoadFailedView { retry += 1 } }
        }
        .animation(.easeOut(duration: 0.25), value: loading)
        .task(id: retry) {
            if resp != nil { return }   // zurueck von einer Unterseite: Seite bleibt stehen
            loading = true
            let r = try? await app.api.artist(uri)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) { resp = r }
            loading = false
            if let hex = r?.color, let c = Color(hexString: hex) {
                withAnimation(.easeOut(duration: 0.3)) { tint = c }
            } else {
                let src = heroURL.flatMap { app.api.absoluteURL($0)?.absoluteString } ?? heroURL
                if let c = await averageColor(src) { withAnimation(.easeOut(duration: 0.3)) { tint = c } }
            }
        }
    }

    // MARK: Titelbild
    private var hero: some View {
        GeometryReader { g in
            // scrollY ist 0 in Ruhe und negativ beim Herunterziehen. Das Bild reicht immer bis
            // unter die Statusleiste (topInset) und wächst beim Ziehen mit.
            let stretch = topInset + max(0, -scrollY)
            ZStack(alignment: .bottomLeading) {
                HeroFill(url: heroURL, width: g.size.width, height: heroH + stretch)
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.25), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .black.opacity(0.55), location: 1)],
                    startPoint: .top, endPoint: .bottom)
                Text(title)
                    .font(.system(size: 46, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.5)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 2)
                    .padding(.horizontal, 16).padding(.bottom, 14)
                    .opacity(max(0, 1 - Double(max(0, scrollY)) / 220))
            }
            .frame(width: g.size.width, height: heroH + stretch)
            .offset(y: -stretch)
        }
        .frame(height: heroH)
    }

    // MARK: Inhalt
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let ml = resp?.monthly_listeners, ml > 0 {
                    Text("\(ml.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(Locale(identifier: "de_DE")))) monatliche Hörer*innen")
                        .font(.system(size: 13)).foregroundStyle(Theme.sub)
                }
                Spacer()
                GlassSymbolButton(systemName: "shuffle", size: 44, symbolSize: 20) {
                    guard !top.isEmpty else { return }
                    player.shuffle = true
                    player.play(tracks: top.shuffled(), contextName: title, contextURI: uri)
                }
                .accessibilityLabel("Zufallswiedergabe")
                Button {
                    if !top.isEmpty { player.play(tracks: top, startAt: 0, contextName: title, contextURI: uri) }
                } label: {
                    Image(systemName: "play.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Theme.accent, in: Circle())
                        .shadow(color: Theme.accent.opacity(0.34), radius: 12, y: 3)
                }.buttonStyle(.pressable).accessibilityLabel("Abspielen")
            }
            .padding(.horizontal).padding(.top, 14).padding(.bottom, 6)

            if !top.isEmpty {
                SectionHeader("Beliebt")
                LazyVStack(spacing: 0) {
                    ForEach(Array(top.prefix(showAllTop ? 10 : 5).enumerated()), id: \.offset) { i, t in
                        NumberedTrackRow(n: i + 1, track: t, playing: now.track?.id == t.id) {
                            player.play(tracks: top, startAt: i, contextName: title, contextURI: uri)
                        }
                    }
                }.padding(.top, 4)
                if top.count > 5 {
                    Button { withAnimation(Motion.spring) { showAllTop.toggle() } } label: {
                        Text(showAllTop ? "Weniger anzeigen" : "Mehr anzeigen")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sub)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .overlay(Capsule().stroke(Theme.mute.opacity(0.6), lineWidth: 1))
                    }.buttonStyle(.pressable).padding(.horizontal).padding(.top, 6)
                }
            }

            let popular = resp?.discog_popular ?? []
            if !popular.isEmpty {
                SectionHeader("Beliebte Veröffentlichungen").padding(.top, 18)
                VStack(spacing: 0) {
                    ForEach(popular.prefix(4)) { r in
                        NavigationLink { TrackListView(uri: r.uri, title: r.name, image: r.image, isAlbum: true) } label: {
                            HStack(spacing: 12) {
                                Artwork(url: r.image, size: 64, corner: 4)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(r.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text(r.subtitle).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal).padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.pressable)
                    }
                }.padding(.top, 6)
            }

            releaseRow("Alben", resp?.discog_albums ?? [])
            releaseRow("Singles und EPs", resp?.discog_singles ?? [])
            if (resp?.discog_albums ?? []).isEmpty && (resp?.discog_singles ?? []).isEmpty {
                releaseRow("Alben", resp?.albums ?? [])
            }

            if let rel = resp?.related, !rel.isEmpty {
                SectionHeader("Fans mögen auch").padding(.top, 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(rel) { a in
                            NavigationLink { ArtistView(uri: a.uri, name: a.name, image: a.image) } label: {
                                VStack(spacing: 8) {
                                    Artwork(url: a.image, size: 128, corner: 64)
                                        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                                    Text(a.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                                        .lineLimit(1).frame(width: 128)
                                }
                            }.buttonStyle(.pressable)
                        }
                    }.padding(.horizontal).padding(.vertical, 6)
                }
            }

            if let r = resp, !(r.bio ?? "").isEmpty || (r.monthly_listeners ?? 0) > 0 {
                SectionHeader("Über").padding(.top, 18)
                aboutCard(r).padding(.horizontal).padding(.top, 8)
            }
            Color.clear.frame(height: 130)
        }
    }

    @ViewBuilder
    private func releaseRow(_ label: String, _ items: [ArtistRelease]) -> some View {
        if !items.isEmpty {
            SectionHeader(label).padding(.top, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(items) { r in
                        NavigationLink { TrackListView(uri: r.uri, title: r.name, image: r.image, isAlbum: true) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Artwork(url: r.image, size: 148, corner: 6)
                                Text(r.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                                    .lineLimit(1).frame(width: 148, alignment: .leading)
                                Text(r.subtitle).font(.system(size: 12)).foregroundStyle(Theme.sub)
                                    .lineLimit(1).frame(width: 148, alignment: .leading)
                            }
                        }.buttonStyle(.pressable)
                    }
                }.padding(.horizontal).padding(.vertical, 6)
            }
        }
    }

    private func aboutCard(_ r: ArtistResponse) -> some View {
        Button { withAnimation(Motion.spring) { bioOpen.toggle() } } label: {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { g in
                    HeroFill(url: r.about_image ?? r.avatar ?? r.image, width: g.size.width, height: g.size.height)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    if let ml = r.monthly_listeners, ml > 0 {
                        Text("\(ml.formatted(.number.locale(Locale(identifier: "de_DE")))) monatliche Hörer*innen")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    }
                    if let bio = r.bio, !bio.isEmpty {
                        Text(bio).font(.system(size: 14)).foregroundStyle(.white.opacity(0.9))
                            .lineLimit(bioOpen ? nil : 3).multilineTextAlignment(.leading)
                    }
                }.padding(16)
            }
            .frame(minHeight: bioOpen ? 0 : 280)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.pressable)
    }
}

/// Bild, das eine Fläche ganz ausfüllt (Titelbild, Über-Karte). Lädt in der passenden Größe.
struct HeroFill: View {
    let url: String?
    let width: CGFloat
    let height: CGFloat
    @Environment(\.displayScale) private var displayScale
    @State private var img: UIImage?
    private var resolved: URL? {
        guard let s = url, !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: ImageBase.url + (s.hasPrefix("/") ? s : "/" + s))
    }
    private var pixels: Int { Int((max(width, 1) * displayScale).rounded(.up)) }
    var body: some View {
        let shown = resolved.flatMap { ImageLoader.shared.cached($0, pixels: pixels) } ?? img
        ZStack {
            Theme.card
            if let shown {
                Image(uiImage: shown).resizable().scaledToFill()
                    .frame(width: width, height: height)
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height).clipped()
        .task(id: resolved) {
            guard let u = resolved else { img = nil; return }
            let loaded = await ImageLoader.shared.load(u, pixels: pixels)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { img = loaded }
        }
    }
}

extension Color {
    /// "#3d5474" -> Farbe
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt(s, radix: 16) else { return nil }
        self.init(hex6: v)
    }
}
