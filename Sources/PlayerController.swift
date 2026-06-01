import Foundation
import AVFoundation
import MediaPlayer
import UIKit

enum RepeatMode { case off, all, one }

/// Nativer Player: Queue + AVPlayer + Lock-Screen. Spielt Tracks (ueber das
/// Backend aufgeloest) und Live-Radio (direkte Stream-URL). Komplett nativ.
@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var loading = false
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var isRadio = false
    @Published private(set) var source = ""   // "youtube" | "navidrome"
    private var radioTitle = ""
    private var radioFavicon: String?
    private var primedNotLoaded = false   // letzter Song wiederhergestellt, aber noch nicht gestreamt
    var profileScope = ""                 // fuer profil-spezifische Persistenz
    weak var downloads: DownloadManager?  // Offline-Wiedergabe
    @Published var sleepRemaining = 0     // Sekunden, 0 = aus
    @Published var sleepAtEnd = false     // bis Songende
    private var sleepTimer: Timer?

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var hasContent: Bool { current != nil || isRadio }
    var isEpisode: Bool { !isRadio && (current?.uri.hasPrefix("spotify:episode:") ?? false) }
    var displayTitle: String { isRadio ? radioTitle : (current?.name ?? "") }
    var displayArtist: String { isRadio ? "Live-Radio" : (current?.artist ?? "") }
    var displayImage: String? { isRadio ? radioFavicon : current?.image }
    var upNext: [Track] { index + 1 < queue.count ? Array(queue[(index+1)...]) : [] }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObs: NSKeyValueObservation?
    private var endObs: NSObjectProtocol?
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
        setupRemoteCommands()
        addTimeObserver()
    }

    private var ctxName = ""
    private var ctxURI = ""

    // MARK: - Tracks
    func play(tracks: [Track], startAt i: Int = 0, contextName: String = "", contextURI: String = "") {
        guard !tracks.isEmpty else { return }
        isRadio = false
        ctxName = contextName; ctxURI = contextURI
        queue = tracks
        index = max(0, min(i, tracks.count - 1))
        loadCurrent(autoplay: true)
    }

    func toggle() {
        if primedNotLoaded { loadCurrent(autoplay: true); return }
        isPlaying ? pause() : resume()
    }
    func resume() {
        if primedNotLoaded { loadCurrent(autoplay: true); return }
        player.play(); isPlaying = true; updateRate()
    }
    func pause() { player.pause(); isPlaying = false; updateRate() }

    /// Letzten Song wiederherstellen (Mini-Player sofort da, aber noch nicht gestreamt).
    func prime(_ t: Track) {
        guard !hasContent else { return }
        isRadio = false; queue = [t]; index = 0
        currentTime = 0; duration = t.durationSec; source = ""; isPlaying = false
        primedNotLoaded = true
        updateNowPlaying(title: t.name, artist: t.artist, album: t.album, dur: t.durationSec, art: t.image, live: false)
    }
    func restoreLast() {
        guard !hasContent,
              let d = UserDefaults.standard.data(forKey: "lastTrack_\(profileScope)"),
              let t = try? JSONDecoder().decode(Track.self, from: d) else { return }
        prime(t)
        source = UserDefaults.standard.string(forKey: "lastSource_\(profileScope)") ?? ""
    }
    private func persistLast(_ t: Track) {
        if let d = try? JSONEncoder().encode(t) {
            UserDefaults.standard.set(d, forKey: "lastTrack_\(profileScope)")
        }
    }

    // MARK: - Sleep-Timer
    func setSleep(minutes: Int) {
        cancelSleep()
        guard minutes > 0 else { return }
        sleepRemaining = minutes * 60
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleepRemaining -= 1
                if self.sleepRemaining <= 0 { self.cancelSleep(); self.pause() }
            }
        }
    }
    func setSleepEndOfTrack() { cancelSleep(); sleepAtEnd = true }
    func cancelSleep() { sleepTimer?.invalidate(); sleepTimer = nil; sleepRemaining = 0; sleepAtEnd = false }

    func next(auto: Bool = false) {
        if auto && sleepAtEnd { sleepAtEnd = false; pause(); return }
        if isRadio { return }
        guard !queue.isEmpty else { return }
        if auto && repeatMode == .one { seek(0); resume(); return }
        if shuffle && queue.count > 1 {
            var n = Int.random(in: 0..<queue.count)
            while n == index { n = Int.random(in: 0..<queue.count) }
            index = n
        } else if index + 1 < queue.count {
            index += 1
        } else if repeatMode != .off {
            index = 0
        } else { return }
        loadCurrent(autoplay: true)
    }
    func prev() {
        if isRadio { return }
        if currentTime > 3 || index == 0 { seek(0); return }
        index -= 1; loadCurrent(autoplay: true)
    }
    func playAt(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i; loadCurrent(autoplay: true)
    }
    func seek(_ t: Double) {
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in self?.currentTime = t; self?.updateElapsed() }
        }
    }
    func toggleShuffle() { shuffle.toggle() }
    func cycleRepeat() { repeatMode = repeatMode == .off ? .all : (repeatMode == .all ? .one : .off) }

    /// Relativ vor/zurueck springen (Podcast ±10s).
    func skip(_ delta: Double) {
        var t = currentTime + delta
        if t < 0 { t = 0 }
        if duration > 0 { t = min(t, duration) }
        seek(t)
    }

    /// Song direkt hinter dem aktuellen einreihen ("Als Naechstes spielen").
    func playNext(_ t: Track) {
        if !hasContent || isRadio { play(tracks: [t]); return }
        queue.insert(t, at: min(index + 1, queue.count))
    }
    /// Song ans Ende der Warteschlange.
    func addToQueue(_ t: Track) {
        if !hasContent || isRadio { play(tracks: [t]); return }
        queue.append(t)
    }
    /// Kommende Tracks (nach dem aktuellen) per Drag umsortieren.
    func moveUpNext(from source: IndexSet, to destination: Int) {
        let base = index + 1
        guard base <= queue.count else { return }
        var up = Array(queue[base...])
        up.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange(base..., with: up)
    }
    /// Einen kommenden Track entfernen (Offset relativ zu upNext).
    func removeUpNext(at offset: Int) {
        let real = index + 1 + offset
        guard queue.indices.contains(real) else { return }
        queue.remove(at: real)
    }
    /// Alle kommenden Tracks leeren (aktueller bleibt).
    func clearUpNext() {
        guard hasContent, !isRadio, index + 1 < queue.count else { return }
        queue.removeSubrange((index + 1)...)
    }

    private func loadCurrent(autoplay: Bool) {
        guard let track = current else { return }
        primedNotLoaded = false
        persistLast(track)
        updateRemoteForContent()
        loading = true; currentTime = 0; duration = track.durationSec; source = ""
        updateNowPlaying(title: track.name, artist: track.artist, album: track.album,
                         dur: track.durationSec, art: track.image, live: false)
        // Offline vorhanden? -> lokal abspielen, kein Stream noetig
        if let local = downloads?.localURL(for: track.uri) {
            source = "offline"
            let item = AVPlayerItem(url: local)
            attachItemObservers(item)
            player.replaceCurrentItem(with: item)
            if autoplay { resume() }
            loading = false
            Task { await api.postHistory(track, contextName: ctxName, contextURI: ctxURI) }
            return
        }
        let myIndex = index
        Task {
            do {
                let r = try await api.streamURL(for: track)
                guard myIndex == index, !isRadio else { return }
                guard r.ok, let rel = r.url, let url = api.absoluteURL(rel) else { loading = false; return }
                source = r.source ?? ""
                UserDefaults.standard.set(source, forKey: "lastSource_\(profileScope)")
                let played = track
                Task { await api.postHistory(played, contextName: ctxName, contextURI: ctxURI) }
                let item = AVPlayerItem(url: url)
                attachItemObservers(item)
                player.replaceCurrentItem(with: item)
                if autoplay { resume() }
                loading = false
            } catch { loading = false }
        }
    }

    // MARK: - Radio
    func playRadio(_ s: RadioStation) {
        guard let url = URL(string: s.url) else { return }
        isRadio = true; queue = []; index = 0
        radioTitle = s.name; radioFavicon = s.favicon
        currentTime = 0; duration = 0; loading = true
        let item = AVPlayerItem(url: url)
        attachItemObservers(item)
        player.replaceCurrentItem(with: item)
        updateNowPlaying(title: s.name, artist: "Live-Radio", album: nil, dur: 0, art: s.favicon, live: true)
        resume(); loading = false
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
            Task { @MainActor in self?.next(auto: true) }
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

    // MARK: - Lock-Screen
    private func updateNowPlaying(title: String, artist: String, album: String?, dur: Double, art: String?, live: Bool) {
        var info: [String: Any] = [MPMediaItemPropertyTitle: title, MPMediaItemPropertyArtist: artist]
        if let al = album { info[MPMediaItemPropertyAlbumTitle] = al }
        if dur > 0 { info[MPMediaItemPropertyPlaybackDuration] = dur }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyIsLiveStream] = live
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if let a = art, let u = URL(string: a) {
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
            Task { @MainActor in self?.seek(e.positionTime) }; return .success
        }
        // Podcast: 10s vor/zurueck im Lock-Screen
        c.skipForwardCommand.preferredIntervals = [NSNumber(value: 10)]
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: 10)]
        c.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(10) }; return .success }
        c.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(-10) }; return .success }
    }

    /// Lock-Screen: Podcast -> 10s-Skip, Musik -> Track vor/zurueck.
    private func updateRemoteForContent() {
        let c = MPRemoteCommandCenter.shared()
        let ep = isEpisode
        c.nextTrackCommand.isEnabled = !ep
        c.previousTrackCommand.isEnabled = !ep
        c.skipForwardCommand.isEnabled = ep
        c.skipBackwardCommand.isEnabled = ep
    }
}
