import Foundation
import AVFoundation
import MediaPlayer
import UIKit

enum RepeatMode { case off, all, one }

/// Gesamter Player-Zustand fuer Session-Persistenz (ganze Queue + Position).
struct PlayerSnapshot: Codable { let tracks: [Track]; let index: Int; let original: [Track]? }

/// Hochfrequente Wiedergabe-Position. Bewusst SEPARAT vom PlayerController,
/// damit die Sekunden-Ticks NICHT alle Views (Listen, offene Menues) neu
/// rendern — nur der Player-Screen beobachtet diese Uhr.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var time: Double = 0
    @Published var duration: Double = 0
}

/// Liest den ICY-StreamTitle (laufender Song) aus einem Live-Radio-Stream.
/// (SHOUTcast/Icecast senden den aktuellen Titel als Timed-Metadata.)
final class ICYMetadataReader: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    var onTitle: ((String) -> Void)?
    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                                    didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                                    from track: AVPlayerItemTrack?) {
        // Viele Sender schicken mehrere Felder (Songtitel + Sender-Motto/Werbung).
        // Gezielt den Songtitel waehlen: StreamTitle / commonKey title; Artist ggf. davor.
        var title: String?, artist: String?, fallback: String?
        for group in groups {
            for item in group.items {
                guard let s = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { continue }
                let id = (item.identifier?.rawValue ?? "").lowercased()
                let common = (item.commonKey?.rawValue ?? "").lowercased()
                if common == "title" || id.contains("streamtitle") || id.hasSuffix("/title") || id.contains("songtitle") {
                    title = s
                } else if common == "artist" || id.contains("artist") {
                    artist = s
                } else if fallback == nil {
                    fallback = s
                }
            }
        }
        let result: String?
        if let t = title { result = artist.map { "\($0) – \(t)" } ?? t }
        else { result = fallback }
        if let r = result, !r.isEmpty { onTitle?(r) }
    }
}

/// Nativer Player: Queue + AVPlayer + Lock-Screen. Spielt Tracks (ueber das
/// Backend aufgeloest) und Live-Radio (direkte Stream-URL). Komplett nativ.
@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var queue: [Track] = []          // physische Playback-Queue (ggf. geshuffelt)
    @Published private(set) var index: Int = 0
    private var original: [Track] = []                       // Anzeige-Reihenfolge (zum Entshufflen)
    @Published private(set) var manualQueue: [Track] = []    // Play-Next / Add-to-Queue (wird zuerst gespielt)
    @Published private(set) var isPlaying = false
    // currentTime/duration leben in der separaten Uhr (kein Listen-Rerender pro Tick)
    let clock = PlaybackClock()
    var currentTime: Double { get { clock.time } set { clock.time = newValue } }
    var duration: Double { get { clock.duration } set { clock.duration = newValue } }
    @Published private(set) var loading = false
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var isRadio = false
    @Published private(set) var source = ""   // "youtube" | "navidrome"
    private var radioTitle = ""
    private var radioFavicon: String?
    @Published private(set) var radioNowPlaying = ""   // ICY-StreamTitle (laufender Song im Radio)
    private let metaReader = ICYMetadataReader()
    private var primedNotLoaded = false   // letzter Song wiederhergestellt, aber noch nicht gestreamt
    private var failedOffline: Set<String> = []   // Offline-Dateien, die diese Session nicht liefen -> streamen
    var profileScope = ""                 // fuer profil-spezifische Persistenz
    weak var downloads: DownloadManager?  // Offline-Wiedergabe
    @Published var sleepRemaining = 0     // Sekunden, 0 = aus
    @Published var sleepAtEnd = false     // bis Songende
    private var sleepDeadline: Date?      // absolute Deadline -> im Time-Observer geprueft (laeuft auch im Hintergrund)
    // Crossfade (Sekunden, 0 = aus). v2: echtes ueberlappendes Crossfade ueber zwei
    // Player (siehe applyFade/beginCrossfade/completeCrossfade). Bei 0 komplett
    // inaktiv -> Normalpfad unberuehrt.
    @Published var crossfadeSeconds: Int = UserDefaults.standard.integer(forKey: "crossfadeSeconds") {
        didSet {
            UserDefaults.standard.set(crossfadeSeconds, forKey: "crossfadeSeconds")
            if crossfadeSeconds == 0 { player.volume = 1 }
        }
    }
    // Wiedergabe-Tempo (1.0 = normal). AVPlayer haelt die Tonhoehe konstant.
    @Published var playbackRate: Double = {
        let v = UserDefaults.standard.double(forKey: "playbackRate"); return v > 0 ? v : 1.0
    }() {
        didSet {
            UserDefaults.standard.set(playbackRate, forKey: "playbackRate")
            if isPlaying && !isRadio { player.rate = Float(playbackRate) }
        }
    }

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var hasContent: Bool { current != nil || isRadio }
    var isEpisode: Bool { !isRadio && (current?.uri.hasPrefix("spotify:episode:") ?? false) }
    var displayTitle: String { isRadio ? radioTitle : (current?.name ?? "") }
    var displayArtist: String { isRadio ? (radioNowPlaying.isEmpty ? "Live-Radio" : radioNowPlaying) : (current?.artist ?? "") }
    var displayImage: String? { isRadio ? radioFavicon : current?.image }
    var upNext: [Track] { manualQueue + (index + 1 < queue.count ? Array(queue[(index+1)...]) : []) }

    /// Fisher-Yates wie PWA. anchor != nil -> der Track bleibt vorne (Pos 0).
    private func fisherYates(_ arr: [Track], anchor: Track?) -> [Track] {
        var a = arr
        var start = 0
        if let k = anchor, let ki = a.firstIndex(where: { $0.uri == k.uri }) {
            if ki != 0 { a.swapAt(0, ki) }
            start = 1
        }
        if a.count > start + 1 {
            for i in stride(from: a.count - 1, through: start + 1, by: -1) {
                let j = start + Int.random(in: 0...(i - start))
                a.swapAt(i, j)
            }
        }
        return a
    }

    // Zwei Player fuer echtes ueberlappendes Crossfade (v2). `player` = aktiver/
    // getrackter Player; `idlePlayer` = der andere (spielt den eingehenden Track
    // waehrend der Ueberblende). Bei crossfade=0 wird der zweite nie benutzt.
    private let playerA = AVPlayer()
    private let playerB = AVPlayer()
    private var activeIsA = true
    private var player: AVPlayer { activeIsA ? playerA : playerB }
    private var idlePlayer: AVPlayer { activeIsA ? playerB : playerA }
    private var crossfading = false
    private var xfTarget: Track?
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
        isRadio = false; radioNowPlaying = ""
        ctxName = contextName; ctxURI = contextURI
        original = tracks
        manualQueue = []
        let start = max(0, min(i, tracks.count - 1))
        if shuffle && tracks.count > 1 {
            queue = fisherYates(tracks, anchor: tracks[start])   // geklickter Track als Anker vorne
            index = 0
        } else {
            queue = tracks
            index = start
        }
        loadCurrent(autoplay: true)
    }

    func toggle() {
        if primedNotLoaded { loadCurrent(autoplay: true); return }
        isPlaying ? pause() : resume()
    }
    func resume() {
        if primedNotLoaded && !isRadio { loadCurrent(autoplay: true); return }
        player.play()
        if !isRadio && playbackRate != 1.0 { player.rate = Float(playbackRate) }
        isPlaying = true; updateRate()
    }
    func pause() { player.pause(); isPlaying = false; updateRate() }

    /// Gesamten Player wiederherstellen (ganze Queue, Mini-Player sofort da).
    func restoreLast() {
        restoreMode()
        guard !hasContent,
              let d = UserDefaults.standard.data(forKey: "playerSnap_\(profileScope)"),
              let snap = try? JSONDecoder().decode(PlayerSnapshot.self, from: d),
              !snap.tracks.isEmpty else { return }
        isRadio = false; radioNowPlaying = ""
        queue = snap.tracks
        original = snap.original ?? snap.tracks
        manualQueue = []
        index = min(max(0, snap.index), snap.tracks.count - 1)
        let t = queue[index]
        currentTime = 0; duration = t.durationSec; source = ""; isPlaying = false
        primedNotLoaded = true
        updateNowPlaying(title: t.name, artist: t.artist, album: t.album, dur: t.durationSec, art: t.image, live: false)
        source = UserDefaults.standard.string(forKey: "lastSource_\(profileScope)") ?? ""
    }
    private func persistSnapshot() {
        guard !isRadio, !queue.isEmpty else { return }
        if let d = try? JSONEncoder().encode(PlayerSnapshot(tracks: queue, index: index, original: original)) {
            UserDefaults.standard.set(d, forKey: "playerSnap_\(profileScope)")
        }
    }
    // Play-Modi (Shuffle/Repeat) serverseitig sichern/laden — wie PWA
    private func saveMode() { Task { await api.savePlaymode(shuffle: shuffle, mode: repeatMode) } }
    func restoreMode() { Task { let m = await api.playmode(); shuffle = m.shuffle; repeatMode = m.mode } }

    // MARK: - Sleep-Timer (Deadline-basiert -> wird im Time-Observer geprueft und
    // feuert dadurch auch bei gesperrtem Bildschirm zuverlaessig, anders als ein
    // Main-Runloop-Timer. Mit sanftem Fade-out in den letzten Sekunden.)
    func setSleep(minutes: Int) {
        cancelSleep()
        guard minutes > 0 else { return }
        sleepDeadline = Date().addingTimeInterval(Double(minutes) * 60)
        sleepRemaining = minutes * 60
    }
    func setSleepEndOfTrack() { cancelSleep(); sleepAtEnd = true }
    func cancelSleep() {
        sleepDeadline = nil
        sleepRemaining = 0
        sleepAtEnd = false
        player.volume = 1.0
    }
    /// Sanftes Aus-/Einblenden an den Track-Grenzen (Fade-Transition). Wird vom
    /// Time-Observer aufgerufen, laeuft so auch bei gesperrtem Bildschirm.
    /// Laeuft VOR checkSleep -> der Sleep-Fade behaelt im Zweifel die Oberhand.
    private func applyFade() {
        guard crossfadeSeconds > 0, !isRadio else { return }
        let cf = Double(crossfadeSeconds)
        if crossfading {
            // Ueberblende laeuft: Lautstaerken aus der Restzeit des AUSGEHENDEN
            // (aktiven) Tracks ableiten -> funktioniert auch im Hintergrund.
            let remaining = max(0, duration - currentTime)
            let out = max(0, min(1, duration > 0 ? remaining / cf : 0))
            player.volume = Float(out)
            idlePlayer.volume = Float(1 - out)
            return
        }
        guard isPlaying, duration > 0 else { return }
        // Fade-in am Anfang
        player.volume = currentTime < cf ? Float(max(0, min(1, currentTime / cf))) : 1
        // Ueberblende ausloesen, wenn das Ende naht (nur einfache Faelle: manuelle
        // Queue oder naechster Queue-Track; am Playlist-Ende normaler Schnitt).
        let remaining = duration - currentTime
        if remaining <= cf, remaining > 0.4, repeatMode != .one, let nt = peekNext() {
            beginCrossfade(to: nt)
        }
    }

    private func peekNext() -> Track? {
        if !manualQueue.isEmpty { return manualQueue.first }
        if !queue.isEmpty, index < queue.count - 1 { return queue[index + 1] }
        return nil
    }

    /// Startet den eingehenden Track leise auf dem Idle-Player; applyFade blendet dann ueber.
    private func beginCrossfade(to nt: Track) {
        crossfading = true
        xfTarget = nt
        let b = idlePlayer
        b.volume = 0
        if let local = downloads?.localURL(for: nt.uri), !failedOffline.contains(nt.uri) {
            b.replaceCurrentItem(with: AVPlayerItem(url: local)); b.play()
            return
        }
        Task {
            do {
                let r = try await api.streamURL(for: nt)
                guard crossfading, xfTarget?.uri == nt.uri,
                      r.ok, let rel = r.url, let url = api.absoluteURL(rel) else { abortCrossfade(); return }
                b.replaceCurrentItem(with: AVPlayerItem(url: url)); b.play()
            } catch { abortCrossfade() }
        }
    }

    private func abortCrossfade() {
        crossfading = false; xfTarget = nil
        idlePlayer.pause(); idlePlayer.replaceCurrentItem(with: nil); idlePlayer.volume = 1
        player.volume = 1
    }

    /// Ueberblende abschliessen: Idle-Player (eingehend) wird aktiv, Queue-Status nachziehen.
    private func completeCrossfade() {
        guard crossfading else { return }
        // Eingehender Track noch nicht geladen (langsamer Stream)? -> normaler Schnitt.
        guard idlePlayer.currentItem != nil else {
            crossfading = false; xfTarget = nil
            idlePlayer.volume = 1; player.volume = 1
            next(auto: true)
            return
        }
        crossfading = false
        let wasOffline = (xfTarget.map { downloads?.localURL(for: $0.uri) != nil && !failedOffline.contains($0.uri) }) ?? false
        xfTarget = nil
        // Queue-Status wie next() (nur die einfachen Faelle, die peekNext liefert)
        if !manualQueue.isEmpty {
            let inj = manualQueue.removeFirst()
            let at = min(index + 1, queue.count)
            queue.insert(inj, at: at); index = at
        } else if index < queue.count - 1 {
            index += 1
        }
        // Player tauschen: Idle (eingehend) -> aktiv
        detachTimeObserver(from: player)        // alter aktiver (ausgehend)
        let old = player
        activeIsA.toggle()                      // player = eingehender
        player.volume = 1
        addTimeObserver()                       // Observer auf neuen aktiven
        if let item = player.currentItem { attachItemObservers(item) }
        old.pause(); old.replaceCurrentItem(with: nil); old.volume = 1
        // UI/State auf den neuen Track ziehen
        primedNotLoaded = false
        source = wasOffline ? "offline" : ""
        let pos = CMTimeGetSeconds(player.currentTime())
        currentTime = pos.isFinite ? pos : 0
        if let t = current {
            duration = t.durationSec
            updateNowPlaying(title: t.name, artist: t.artist, album: t.album, dur: t.durationSec, art: t.image, live: false)
            Task { await api.postHistory(t, contextName: ctxName, contextURI: ctxURI) }
        }
        persistSnapshot()
    }

    private func detachTimeObserver(from p: AVPlayer) {
        if let t = timeObserver { p.removeTimeObserver(t); timeObserver = nil }
    }
    /// Wird vom Time-Observer (~alle 0.5s waehrend der Wiedergabe) aufgerufen —
    /// laeuft so auch im Hintergrund, solange Audio spielt.
    private func checkSleep() {
        guard let dl = sleepDeadline else { return }
        let remaining = dl.timeIntervalSinceNow
        sleepRemaining = max(0, Int(ceil(remaining)))
        if remaining <= 0 {
            sleepDeadline = nil
            sleepRemaining = 0
            pause()
            player.volume = 1.0          // fuer die naechste Wiedergabe zuruecksetzen
        } else if remaining <= 6 {
            player.volume = Float(max(0, remaining / 6))   // sanfter Fade-out
        }
    }

    func next(auto: Bool = false) {
        if crossfading { completeCrossfade(); return }
        if auto && sleepAtEnd { sleepAtEnd = false; pause(); return }
        if isRadio { return }
        if auto && repeatMode == .one { seek(0); resume(); return }
        // 1) Manuelle Queue (Play-Next/Add-to-Queue) zuerst
        if !manualQueue.isEmpty {
            let inj = manualQueue.removeFirst()
            let at = min(index + 1, queue.count)
            queue.insert(inj, at: at)
            index = at
            loadCurrent(autoplay: true)
            return
        }
        guard !queue.isEmpty else { return }
        // 2) Ende der Queue
        if index >= queue.count - 1 {
            if shuffle && queue.count > 1 {        // neu mischen, von vorne (wie PWA)
                queue = fisherYates(queue, anchor: nil); index = 0
                loadCurrent(autoplay: true); return
            }
            if repeatMode == .all {                // auf Anfang
                index = 0; loadCurrent(autoplay: true); return
            }
            pause(); return                        // repeat off, kein Shuffle -> stop
        }
        // 3) Normaler sequenzieller Advance
        index += 1
        loadCurrent(autoplay: true)
    }
    func prev() {
        if isRadio { return }
        if currentTime > 10 || queue.isEmpty { seek(0); return }   // >10s -> Anfang (wie PWA)
        index = (index - 1 + queue.count) % queue.count
        loadCurrent(autoplay: true)
    }
    func playAt(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i; loadCurrent(autoplay: true)
    }
    /// Tap auf einen Eintrag in "Als Naechstes" (manuelle Queue + Rest).
    func playUpNext(_ offset: Int) {
        if offset < manualQueue.count {
            let t = manualQueue.remove(at: offset)
            let at = min(index + 1, queue.count)
            queue.insert(t, at: at); index = at
            loadCurrent(autoplay: true)
        } else {
            let real = index + 1 + (offset - manualQueue.count)
            if queue.indices.contains(real) { index = real; loadCurrent(autoplay: true) }
        }
    }
    func seek(_ t: Double) {
        if crossfading { abortCrossfade() }
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in self?.currentTime = t; self?.updateElapsed() }
        }
    }
    func toggleShuffle() {
        let wasOff = !shuffle
        shuffle.toggle()
        saveMode()
        guard queue.count > 1 else { return }
        let cur = current
        if wasOff {
            if original.isEmpty || original.count != queue.count { original = queue }  // pre-Shuffle-Reihenfolge sichern
            queue = fisherYates(queue, anchor: cur)   // ON: laufenden Track als Anker, Rest mischen
            index = 0
        } else {
            // OFF: Original-Reihenfolge wieder her, ab Position des laufenden Songs
            let src = original.isEmpty ? queue : original
            if let c = cur, let pos = src.firstIndex(where: { $0.uri == c.uri }) {
                queue = src; index = pos
            } else if let c = cur {
                queue = [c] + src.filter { $0.uri != c.uri }; index = 0
            } else {
                queue = src; index = 0
            }
        }
    }
    func cycleRepeat() { repeatMode = repeatMode == .off ? .all : (repeatMode == .all ? .one : .off); saveMode() }

    /// Relativ vor/zurueck springen (Podcast ±10s).
    func skip(_ delta: Double) {
        var t = currentTime + delta
        if t < 0 { t = 0 }
        if duration > 0 { t = min(t, duration) }
        seek(t)
    }

    /// "Als Naechstes spielen" -> vorne in die manuelle Queue (wird zuerst gespielt).
    func playNext(_ t: Track) {
        if !hasContent || isRadio { play(tracks: [t]); return }
        manualQueue.insert(t, at: 0)
    }
    /// "Zur Warteschlange" -> ans Ende der manuellen Queue.
    func addToQueue(_ t: Track) {
        if !hasContent || isRadio { play(tracks: [t]); return }
        manualQueue.append(t)
    }
    /// "Als Naechstes" (manuelle Queue + Rest der Playback-Queue) umsortieren.
    func moveUpNext(from source: IndexSet, to destination: Int) {
        var up = upNext
        guard !up.isEmpty else { return }
        up.move(fromOffsets: source, toOffset: destination)
        manualQueue = up                                       // alles Kommende wird manuelle Queue
        if index + 1 < queue.count { queue.removeSubrange((index + 1)...) }
    }
    /// Einen kommenden Track entfernen (Offset relativ zu upNext).
    func removeUpNext(at offset: Int) {
        if offset < manualQueue.count { manualQueue.remove(at: offset) }
        else {
            let real = index + 1 + (offset - manualQueue.count)
            if queue.indices.contains(real) { queue.remove(at: real) }
        }
    }
    /// Alle kommenden Tracks leeren (aktueller bleibt).
    func clearUpNext() {
        manualQueue = []
        if !isRadio, index + 1 < queue.count { queue.removeSubrange((index + 1)...) }
    }

    private func loadCurrent(autoplay: Bool) {
        guard let track = current else { return }
        if crossfading { abortCrossfade() }
        primedNotLoaded = false
        persistSnapshot()
        updateRemoteForContent()
        loading = true; currentTime = 0; duration = track.durationSec; source = ""
        player.volume = crossfadeSeconds > 0 ? 0 : 1        // Crossfade: aus Stille einblenden
        updateNowPlaying(title: track.name, artist: track.artist, album: track.album,
                         dur: track.durationSec, art: track.image, live: false)
        // Offline vorhanden (und diese Session nicht als fehlerhaft markiert)? -> lokal abspielen
        if let local = downloads?.localURL(for: track.uri), !failedOffline.contains(track.uri) {
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
        if crossfading { abortCrossfade() }
        isRadio = true; primedNotLoaded = false   // sonst leitet resume() faelschlich in loadCurrent um
        queue = []; index = 0; manualQueue = []; original = []
        radioTitle = s.name; radioFavicon = s.favicon; radioNowPlaying = ""
        currentTime = 0; duration = 0; loading = true
        player.volume = 1                                   // Radio: volle Lautstaerke, kein Fade
        let item = AVPlayerItem(url: url)
        attachItemObservers(item)
        // ICY-StreamTitle (laufender Song) live mitlesen
        let mdOut = AVPlayerItemMetadataOutput(identifiers: nil)
        metaReader.onTitle = { [weak self] title in
            Task { @MainActor in
                guard let self, self.isRadio else { return }
                self.radioNowPlaying = title
                self.updateNowPlaying(title: self.radioTitle, artist: title.isEmpty ? "Live-Radio" : title,
                                      album: nil, dur: 0, art: self.radioFavicon, live: true)
            }
        }
        mdOut.setDelegate(metaReader, queue: .main)
        item.add(mdOut)
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
                } else if it.status == .failed {
                    // Offline-Datei spielt gerade nicht -> NUR diese Session streamen.
                    // Datei NICHT loeschen (bleibt in der Offline-Bibliothek).
                    if self.source == "offline", let t = self.current {
                        self.failedOffline.insert(t.uri)
                        self.source = ""
                        self.loadCurrent(autoplay: true)
                    }
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
                self.applyFade()
                self.checkSleep()
            }
        }
    }

    // MARK: - Lock-Screen
    private func updateNowPlaying(title: String, artist: String, album: String?, dur: Double, art: String?, live: Bool) {
        var info: [String: Any] = [MPMediaItemPropertyTitle: title, MPMediaItemPropertyArtist: artist]
        if let al = album { info[MPMediaItemPropertyAlbumTitle] = al }
        if dur > 0 { info[MPMediaItemPropertyPlaybackDuration] = dur }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        info[MPNowPlayingInfoPropertyIsLiveStream] = live
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        // Relative Server-Bild-URLs aufloesen (sonst kein Cover am Lock-Screen)
        if let a = art, !a.isEmpty,
           let u = URL(string: a.hasPrefix("http") ? a : ImageBase.url + (a.hasPrefix("/") ? a : "/" + a)) {
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
        i[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = i
    }
    private func updateRate() {
        var i = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        i[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
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
