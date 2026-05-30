import Foundation
import AVFoundation
import MediaPlayer
import WebKit

/// Nativer Audio-Player: spielt die Stream-URLs der Web-App ueber AVPlayer.
/// Damit besitzt iOS die Wiedergabe nativ -> Lock-Screen/Control-Center
/// bleiben auch bei Pause sauber. Die Web-App steuert ihn ueber ein JS-Shim
/// (window.webkit.messageHandlers.audioctl), Events gehen via JS zurueck.
final class AudioEngine: NSObject {
    weak var webView: WKWebView?
    private var player: AVPlayer?
    private var item: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObs: NSKeyValueObservation?
    private var endObs: NSObjectProtocol?
    private var currentURL: String = ""
    private var pendingPlay = false

    // ── Setup ───────────────────────────────────────────────────────
    func activateSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [])
        try? s.setActive(true)
        setupRemoteCommands()
    }

    // ── Kommandos von der Web-App (audioctl) ────────────────────────
    func handle(_ body: [String: Any]) {
        guard let cmd = body["cmd"] as? String else { return }
        switch cmd {
        case "load":
            let url = (body["url"] as? String) ?? ""
            let autoplay = (body["autoplay"] as? Bool) ?? false
            load(url: url, autoplay: autoplay)
        case "play":   play()
        case "pause":  pause()
        case "seek":   if let t = body["time"] as? Double { seek(t) }
        case "volume": if let v = body["volume"] as? Double { player?.volume = Float(v) }
        case "nowplaying": updateNowPlaying(body)
        default: break
        }
    }

    private func load(url: String, autoplay: Bool) {
        guard let u = URL(string: url) else { return }
        currentURL = url
        pendingPlay = autoplay
        // alten Beobachter abbauen
        teardownItemObservers()
        let it = AVPlayerItem(url: u)
        self.item = it
        if player == nil {
            player = AVPlayer(playerItem: it)
            addTimeObserver()
        } else {
            player?.replaceCurrentItem(with: it)
        }
        emit("loadstart", [:])
        // Status beobachten -> canplay / error
        statusObs = it.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            switch item.status {
            case .readyToPlay:
                let dur = CMTimeGetSeconds(item.duration)
                self.emit("loadedmetadata", ["duration": dur.isFinite ? dur : 0])
                self.emit("canplay", [:])
                if self.pendingPlay { self.play() }
            case .failed:
                self.emit("error", ["code": 4, "message": item.error?.localizedDescription ?? "failed"])
            default: break
            }
        }
        // Ende
        endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: it, queue: .main) { [weak self] _ in
            self?.emit("ended", [:])
        }
    }

    private func play() {
        guard let p = player else { pendingPlay = true; return }
        p.play()
        pendingPlay = false
        emit("play", [:])
        emit("playing", [:])
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
    }

    private func pause() {
        player?.pause()
        emit("pause", [:])
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
    }

    private func seek(_ t: Double) {
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600))
    }

    // ── Zeit-Updates -> Web ─────────────────────────────────────────
    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, let it = self.item else { return }
            let cur = CMTimeGetSeconds(time)
            let dur = CMTimeGetSeconds(it.duration)
            var buffered = 0.0
            if let r = it.loadedTimeRanges.first?.timeRangeValue {
                buffered = CMTimeGetSeconds(r.start) + CMTimeGetSeconds(r.duration)
            }
            self.emit("timeupdate", [
                "currentTime": cur.isFinite ? cur : 0,
                "duration": dur.isFinite ? dur : 0,
                "buffered": buffered.isFinite ? buffered : 0,
            ])
            // Position im Lock-Screen mitziehen
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = cur.isFinite ? cur : 0
            if dur.isFinite { info[MPMediaItemPropertyPlaybackDuration] = dur }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    private func teardownItemObservers() {
        statusObs?.invalidate(); statusObs = nil
        if let e = endObs { NotificationCenter.default.removeObserver(e); endObs = nil }
    }

    // ── Now-Playing (Metadaten von der Web-App) ─────────────────────
    private func updateNowPlaying(_ d: [String: Any]) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if let t = d["title"] as? String  { info[MPMediaItemPropertyTitle] = t }
        if let a = d["artist"] as? String { info[MPMediaItemPropertyArtist] = a }
        if let dur = d["duration"] as? Double, dur > 0 { info[MPMediaItemPropertyPlaybackDuration] = dur }
        if let pos = d["position"] as? Double { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = pos }
        if let playing = d["playing"] as? Bool { info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0 }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if let art = d["artwork"] as? String, let u = URL(string: art) {
            URLSession.shared.dataTask(with: u) { data, _, _ in
                guard let data = data, let img = UIImage(data: data) else { return }
                let aw = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                DispatchQueue.main.async {
                    var i = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    i[MPMediaItemPropertyArtwork] = aw
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = i
                }
            }.resume()
        }
    }

    // ── Lock-Screen-Buttons -> Web-App ──────────────────────────────
    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.removeTarget(nil)
        c.pauseCommand.removeTarget(nil)
        c.nextTrackCommand.removeTarget(nil)
        c.previousTrackCommand.removeTarget(nil)
        c.togglePlayPauseCommand.removeTarget(nil)
        c.playCommand.isEnabled = true
        c.pauseCommand.isEnabled = true
        c.nextTrackCommand.isEnabled = true
        c.previousTrackCommand.isEnabled = true
        c.togglePlayPauseCommand.isEnabled = true
        c.playCommand.addTarget { [weak self] _ in self?.js("window.__nativePlay && __nativePlay()"); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.js("window.__nativePause && __nativePause()"); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.js("window.__nativeToggle && __nativeToggle()"); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.js("window.__nativeNext && __nativeNext()"); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.js("window.__nativePrev && __nativePrev()"); return .success }
    }

    // ── Helpers ─────────────────────────────────────────────────────
    private func emit(_ type: String, _ payload: [String: Any]) {
        var p = payload; p["type"] = type
        guard let data = try? JSONSerialization.data(withJSONObject: p),
              let json = String(data: data, encoding: .utf8) else { return }
        js("window.__onNativeAudio && __onNativeAudio(\(json))")
    }
    private func js(_ code: String) {
        DispatchQueue.main.async { self.webView?.evaluateJavaScript(code, completionHandler: nil) }
    }
}
