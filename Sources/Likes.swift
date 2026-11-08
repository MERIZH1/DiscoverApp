import SwiftUI

/// Herz im Player: legt den laufenden Song in die Liked Songs des Profils
/// (= Spotify-Lieblingssongs), genau wie in der PWA und im Programm.
/// Der Status je Song wird pro Profil gemerkt und nur einmal beim Server erfragt.
/// Songs ohne Spotify-URI (lokal, YouTube-Fund) ordnet der Server über die Suche zu.
@MainActor
final class LikeStore: ObservableObject {
    static let shared = LikeStore()

    @Published private var known: [String: Bool] = [:]   // "profil|spotify:track:…" -> geliked
    @Published private var busy: Set<String> = []
    private var resolved: [String: String] = [:]         // "profil|Track.id" -> gefundene Spotify-URI
    private var asking: Set<String> = []

    private var pid: String { DiscoverServices.app?.profileId ?? "" }

    /// Livestreams, Konzert-Ausschnitte, Radio und Podcast-Folgen lassen sich nicht liken.
    static func canLike(_ t: Track?) -> Bool {
        guard let t, !t.name.isEmpty, t.name != "?", t.liveRange == nil else { return false }
        let u = t.uri
        return !(u.hasPrefix("ytlive:") || u.hasPrefix("livestream:") || u.hasPrefix("radio")
                 || u.hasPrefix("spotify:episode:"))
    }

    private func spotifyURI(_ t: Track) -> String? {
        t.uri.hasPrefix("spotify:track:") ? t.uri : resolved[pid + "|" + t.id]
    }

    func isLiked(_ t: Track?) -> Bool {
        guard let t, let u = spotifyURI(t) else { return false }
        return known[pid + "|" + u] ?? false
    }

    /// Einmal pro Song und Profil nachfragen, danach gilt der gemerkte Stand.
    func refresh(_ t: Track?) async {
        guard let t, Self.canLike(t), let u = spotifyURI(t), let api = DiscoverServices.app?.api else { return }
        let key = pid + "|" + u
        guard known[key] == nil, !asking.contains(key) else { return }
        asking.insert(key)
        defer { asking.remove(key) }
        if let m = await api.likedCheck([u]), let v = m[u], !busy.contains(key) { known[key] = v }
    }

    func toggle(_ t: Track) async {
        guard Self.canLike(t), let app = DiscoverServices.app else { return }
        let p = pid
        let job = p + "|" + t.id
        guard !busy.contains(job) else { return }
        let want = !isLiked(t)
        let before = spotifyURI(t)
        busy.insert(job)
        if let u = before { known[p + "|" + u] = want }   // sofort zeigen, Server bestätigt
        let res = await app.api.setLiked(t, liked: want)
        busy.remove(job)
        if let uri = res.uri {
            if !t.uri.hasPrefix("spotify:track:") { resolved[p + "|" + t.id] = uri }
            known[p + "|" + uri] = want
            app.flash(want ? "Zu Liked Songs hinzugefügt ✓" : "Aus Liked Songs entfernt")
        } else {
            if let u = before { known[p + "|" + u] = !want }
            app.flash(res.error ?? "Liken fehlgeschlagen")
        }
    }
}

/// Das Herz neben dem Songtitel im großen Player.
struct LikeButton: View {
    let track: Track
    @ObservedObject private var likes = LikeStore.shared

    var body: some View {
        let liked = likes.isLiked(track)
        Button {
            Haptics.tap()
            if !liked { SpecialTheme.shared.celebrate() }
            Task { await likes.toggle(track) }
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 24))
                .foregroundStyle(liked ? Theme.accent : Theme.text)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: liked)
        }
        .accessibilityLabel(liked ? "Aus Liked Songs entfernen" : "Zu Liked Songs hinzufügen")
        .accessibilityIdentifier("player.like")
        .task(id: track.id) { await likes.refresh(track) }
    }
}
