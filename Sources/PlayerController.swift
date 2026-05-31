import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Nativer Player: Queue + AVPlayer + Lock-Screen. Loest Stream-URLs ueber das
/// Discover-Backend auf. Komplett nativ (kein WebView/JS-Shim) -> Lock-Screen +
/// Next-Track funktionieren sauber, auch im Hintergrund.
@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var loading = false

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObs: NSKeyValueObservation?
    private var endObs: NSObjectProtocol?
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
        configureSession()
        setupRemoteCommands()
        addTimeObserver()
    }

    func configureSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
    }

    // MARK: - Steuerung
    func play(tracks: [Track], startAt i: Int = 0) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        index = max(0, min(i, tracks.count - 1))
        loadCurrent(autoplay: true)
    }

    func toggle() { isPlaying ? pause() : resume() }
    func resume() { player.play(); isPlaying = true; updateRate() }
    func pause() { player.pause(); isPlaying = false; updateRate() }

    func next() {
        guard index + 1 < queue.count else { return }
        index += 1; loadCurrent(autoplay: true)
    }
    func prev() {
        if currentTime > 3 || index == 0 { seek(0); return }
        index -= 1; loadCurrent(autoplay: true)
    }
    func seek(_ t: Double) {
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in self?.currentTime = t; self?.updateElapsed() }
        }
    }

    private func loadCurrent(autoplay: Bool) {
        guard let track = current else { return }
        loading = true
        currentTime = 0
        duration = track.durationSec
        updateNowPlaying(track: track)
        let myIndex = index
        Task {
            do {
                let r = try await api.streamURL(for: track)
                // Falls zwischenzeitlich weitergesprungen -> verwerfen
                guard myIndex == index else { return }
                guard r.ok, let rel = r.url, let url = api.absoluteURL(rel) else {
                    loading = false; return
                }
                let item = AVPlayerItem(url: url)
                attachItemObservers(item)
                player.replaceCurrentItem(with: item)
                if autoplay { resume() }
                loading = false
            } catch {
                loading = false
            }
        }
    }

    // MARK: - Beobachter
    private func attachItemObservers(_ item: AVPlayerItem) {
        statusObs?.invalidate()
        statusObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            guard let self else { return }
            Task { @MainActor in
                if it.status == .readyToPlay {
                    let d = CMTimeGetSeconds(it.duration)
                    if d.isFinite, d > 0 { self.duration = d }
                }
            }
        }
        if let e = endObs { NotificationCenter.default.removeObserver(e) }
        endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }
    }

    private func addTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self else { return }
            Task { @MainActor in
                let c = CMTimeGetSeconds(t)
                if c.isFinite { self.currentTime = c; self.updateElapsed() }
            }
        }
    }

    // MARK: - Lock-Screen / Now Playing
    private func updateNowPlaying(track: Track) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artist,
        ]
        if let al = track.album { info[MPMediaItemPropertyAlbumTitle] = al }
        if track.durationSec > 0 { info[MPMediaItemPropertyPlaybackDuration] = track.durationSec }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if let img = track.image, let u = URL(string: img) {
            URLSession.shared.dataTask(with: u) { d, _, _ in
                guard let d, let image = UIImage(data: d) else { return }
                let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                DispatchQueue.main.async {
                    var i = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    i[MPMediaItemPropertyArtwork] = art
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = i
                }
            }.resume()
        }
    }
    private func updateElapsed() {
        var i = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        i[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        if duration > 0 { i[MPMediaItemPropertyPlaybackDuration] = duration }
        i[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = i
    }
    private func updateRate() {
        var i = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        i[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = i
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.prev() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(e.positionTime) }
            return .success
        }
    }
}
