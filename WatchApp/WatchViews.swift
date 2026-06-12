import SwiftUI
import UIKit

// MARK: - Root: drei Seiten (Now-Playing / Warteschlange / Playlists)
struct WatchRootView: View {
    @EnvironmentObject var conn: WatchConnector
    var body: some View {
        TabView {
            NowPlayingView()
            QueueView()
            PlaylistsView()
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Now Playing
struct NowPlayingView: View {
    @EnvironmentObject var conn: WatchConnector
    private var s: WatchState { conn.state }

    var body: some View {
        VStack(spacing: 8) {
            cover
            VStack(spacing: 1) {
                Text(s.title.isEmpty ? "Nichts laeuft" : s.title)
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Text(s.artist).font(.caption2).foregroundStyle(WTheme.sub).lineLimit(1)
            }
            if s.duration > 0 && !s.isRadio {
                ProgressView(value: min(conn.localPosition, s.duration), total: s.duration)
                    .tint(WTheme.green)
            }
            controls
            if !s.isRadio { extras }
        }
        .padding(.horizontal, 6)
    }

    private var cover: some View {
        Group {
            if let d = s.coverJPEG, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack { WTheme.green.opacity(0.25); Image(systemName: "music.note").foregroundStyle(WTheme.green) }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button { conn.prev() } label: { Image(systemName: "backward.fill") }
            Button { conn.toggle() } label: {
                Image(systemName: s.playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
            }
            Button { conn.next() } label: { Image(systemName: "forward.fill") }
        }
        .buttonStyle(.plain)
        .font(.title3)
        .foregroundStyle(.white)
        .disabled(!s.hasContent)
    }

    private var extras: some View {
        HStack(spacing: 26) {
            Button { conn.shuffle() } label: {
                Image(systemName: "shuffle").foregroundStyle(s.shuffle ? WTheme.green : WTheme.sub)
            }
            Button { conn.cycleRepeat() } label: {
                Image(systemName: s.repeatMode == 2 ? "repeat.1" : "repeat")
                    .foregroundStyle(s.repeatMode == 0 ? WTheme.sub : WTheme.green)
            }
        }
        .buttonStyle(.plain).font(.system(size: 15))
    }
}

// MARK: - Warteschlange
struct QueueView: View {
    @EnvironmentObject var conn: WatchConnector
    var body: some View {
        Group {
            if conn.state.queue.isEmpty {
                EmptyHint(icon: "list.bullet", text: "Keine Warteschlange")
            } else {
                List {
                    Section("Als Naechstes") {
                        ForEach(Array(conn.state.queue.enumerated()), id: \.element.id) { i, t in
                            Button { conn.playAt(i) } label: { TrackRow(name: t.name, sub: t.artist, image: t.image) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Playlists
struct PlaylistsView: View {
    @EnvironmentObject var conn: WatchConnector
    var body: some View {
        Group {
            if conn.state.playlists.isEmpty {
                EmptyHint(icon: "music.note.list", text: "Keine Playlists")
            } else {
                List {
                    Section("Playlists") {
                        ForEach(conn.state.playlists) { pl in
                            Button { conn.playPlaylist(pl.uri) } label: { TrackRow(name: pl.name, sub: nil, image: pl.image) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Bausteine
struct TrackRow: View {
    let name: String
    let sub: String?
    let image: String?
    var body: some View {
        HStack(spacing: 8) {
            AsyncImage(url: image.flatMap { URL(string: $0) }) { ph in
                switch ph {
                case .success(let img): img.resizable().scaledToFill()
                default: ZStack { WTheme.green.opacity(0.2); Image(systemName: "music.note").font(.caption2).foregroundStyle(WTheme.green) }
                }
            }
            .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if let sub, !sub.isEmpty {
                    Text(sub).font(.caption2).foregroundStyle(WTheme.sub).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct EmptyHint: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(WTheme.sub)
            Text(text).font(.footnote).foregroundStyle(WTheme.sub)
        }
    }
}
