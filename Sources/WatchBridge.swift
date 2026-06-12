import Foundation
import Combine
import UIKit
import WatchConnectivity

/// iPhone-Seite der Apple-Watch-Bruecke.
///
/// Spiegelt den Player-Zustand (Now-Playing, Queue, Playlists) per
/// `updateApplicationContext` auf die Watch — das uebertraegt immer nur den
/// JEWEILS NEUESTEN Stand und wird zugestellt, sobald die Watch aufwacht
/// (ideal fuers Spiegeln). Eingehende Kommandos der Watch (Play/Pause, Skip,
/// Song/Playlist waehlen) werden hier auf den PlayerController angewandt.
///
/// Es laeuft NICHTS auf der Watch ohne iPhone — bewusst so gewollt (keine LTE).
@MainActor
final class WatchBridge: NSObject, ObservableObject {
    static let shared = WatchBridge()

    private weak var app: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var pushTask: Task<Void, Never>?
    private var coverCache: (url: String, data: Data)?
    private var playlists: [WatchPlaylist] = []
    private var loadingPlaylists = false

    func start(app: AppState) {
        guard WCSession.isSupported() else { return }
        self.app = app
        let s = WCSession.default
        s.delegate = self
        s.activate()
        observe()
    }

    private func observe() {
        guard let app else { return }
        // Bei jeder Player-/Sync-Aenderung den Stand (debounced) rueberschieben.
        app.player.objectWillChange
            .sink { [weak self] _ in self?.schedulePush() }
            .store(in: &cancellables)
        app.sync.objectWillChange
            .sink { [weak self] _ in self?.schedulePush() }
            .store(in: &cancellables)
    }

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.pushState()
        }
    }

    // MARK: - Zustand bauen + senden

    private func ensurePlaylists() async {
        guard playlists.isEmpty, !loadingPlaylists, let app else { return }
        loadingPlaylists = true
        defer { loadingPlaylists = false }
        if let pls = try? await app.api.playlists() {
            playlists = pls.prefix(60).map {
                WatchPlaylist(uri: $0.uri, name: $0.name,
                              image: absImage($0.image))
            }
        }
    }

    private func absImage(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return app?.api.absoluteURL(s)?.absoluteString
    }

    /// Kleines Cover (max ~140px, JPEG) — damit das Now-Playing-Cover auf der
    /// Watch IMMER sichtbar ist, auch ohne Netz.
    private func coverData(for urlStr: String?) async -> Data? {
        guard let urlStr, let url = app?.api.absoluteURL(urlStr) else { return nil }
        if let c = coverCache, c.url == urlStr { return c.data }
        guard let (d, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: d) else { return nil }
        let side: CGFloat = 140
        let scale = side / max(img.size.width, img.size.height, 1)
        let target = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let r = UIGraphicsImageRenderer(size: target)
        let small = r.image { _ in img.draw(in: CGRect(origin: .zero, size: target)) }
        let jpeg = small.jpegData(compressionQuality: 0.7)
        if let jpeg { coverCache = (urlStr, jpeg) }
        return jpeg
    }

    private func pushState() async {
        guard let app, WCSession.default.activationState == .activated else { return }
        await ensurePlaylists()
        let p = app.player

        var st = WatchState()
        st.hasContent = p.hasContent
        st.playing = p.isPlaying
        st.title = p.displayTitle
        st.artist = p.displayArtist
        st.image = absImage(p.displayImage)
        st.coverJPEG = await coverData(for: p.displayImage)
        st.position = p.time
        st.duration = p.duration
        st.ts = Date().timeIntervalSince1970
        st.shuffle = p.shuffle
        st.repeatMode = (p.repeatMode == .off) ? 0 : (p.repeatMode == .all ? 1 : 2)
        st.isRadio = p.isRadio
        st.queue = p.upNext.prefix(30).map {
            WatchTrack(id: $0.uri.isEmpty ? UUID().uuidString : $0.uri,
                       name: $0.name, artist: $0.artist, image: absImage($0.image))
        }
        st.playlists = playlists

        guard let data = try? JSONEncoder().encode(st) else { return }
        try? WCSession.default.updateApplicationContext([WatchState.ctxKey: data])
    }

    // MARK: - Kommandos der Watch anwenden

    private func apply(_ msg: [String: Any]) {
        guard let app, let cmd = msg[WatchCmd.key] as? String else { return }
        let p = app.player
        switch cmd {
        case WatchCmd.toggle:  p.toggle()
        case WatchCmd.next:    p.next()
        case WatchCmd.prev:    p.prev()
        case WatchCmd.shuffle: p.toggleShuffle()
        case WatchCmd.repeatMode: p.cycleRepeat()
        case WatchCmd.seek:
            if let t = msg["t"] as? Double { p.seek(t) }
        case WatchCmd.playAt:
            // Index bezieht sich auf upNext -> in Player-Queue uebersetzen.
            if let i = msg["index"] as? Int { playUpNext(at: i) }
        case WatchCmd.playPlaylist:
            if let uri = msg["uri"] as? String { Task { await playPlaylist(uri) } }
        case WatchCmd.sync:
            Task { await pushState() }
        default: break
        }
        // Nach jeder Steuer-Aktion frischen Stand zuruecksenden.
        if cmd != WatchCmd.sync { schedulePush() }
    }

    private func playUpNext(at i: Int) {
        guard let app else { return }
        let up = app.player.upNext
        guard i >= 0, i < up.count else { return }
        // upNext = manualQueue + Rest der Queue. Einfachste robuste Loesung:
        // ab dem getippten Song als neue Wiedergabe starten.
        let slice = Array(up[i...])
        app.player.play(tracks: slice, startAt: 0,
                        contextName: app.player.displayTitle, contextURI: "")
    }

    private func playPlaylist(_ uri: String) async {
        guard let app else { return }
        guard let resp = try? await app.api.playlistTracks(uri), !resp.tracks.isEmpty else { return }
        app.player.play(tracks: resp.tracks, startAt: 0,
                        contextName: resp.name ?? "Playlist", contextURI: uri)
    }
}

// MARK: - WCSessionDelegate (Callbacks kommen vom Hintergrund-Thread)
extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in await self.pushState() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler(["ok": true])
        Task { @MainActor in self.apply(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.apply(userInfo) }
    }
}
