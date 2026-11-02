import AVFoundation
import UIKit

// MARK: - Nach der Pause erreichbar bleiben
// „Auf iPhone abspielen“ vom PC kam bei gesperrtem iPhone nie an: iOS friert eine App
// ein paar Sekunden nach der Pause ein, dann fragt sie den Server nicht mehr nach Befehlen.
// Wecken könnte sie nur Apples Push, und den gibt es mit dem Signulous-Zertifikat nicht.
// Darum läuft nach einer Pause im Hintergrund eine Weile stummer Ton weiter (wie bei
// Wecker-Apps). Solange bleibt die App wach und übernimmt sofort.
@MainActor
final class ConnectKeepAlive {
    static let shared = ConnectKeepAlive()
    nonisolated static let minutesKey = "connectKeepAliveMin"
    /// Minuten nach der Pause (0 = aus). Standard 30.
    nonisolated static var minutes: Int { UserDefaults.standard.object(forKey: minutesKey) as? Int ?? 30 }

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var timer: Task<Void, Never>?
    private var stopSoon: Task<Void, Never>?
    private var inBackground = false
    private var musicPlaying = false
    private(set) var running = false

    private init() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: nil, queue: .main) { n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            // Eine andere App spielt jetzt. Nicht dagegenhalten, iOS darf uns schlafen legen.
            Task { @MainActor in ConnectKeepAlive.shared.stop() }
        }
    }

    func playerChanged(playing: Bool) {
        musicPlaying = playing
        if playing {
            // Erst aus, wenn der echte Ton sicher läuft. Sonst friert iOS die App in der
            // Lücke zwischen Befehl und erstem Ton ein.
            stopSoon?.cancel()
            stopSoon = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled, let self, self.musicPlaying else { return }
                self.stop()
            }
        } else if inBackground {
            start()
        }
    }

    func enteredBackground() {
        inBackground = true
        if !musicPlaying { start() }
    }

    func enteredForeground() {
        inBackground = false
        stop()
    }

    private func start() {
        let min = Self.minutes
        guard min > 0 else { return }
        stopSoon?.cancel()
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(min) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
        guard !running else { return }
        if node == nil {
            guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else { return }
            let n = Self.silentNode(fmt)
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: fmt)
            node = n
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            running = true
        } catch {
            running = false
        }
    }

    /// Läuft auf dem Audio-Thread, darum ausserhalb des MainActor gebaut.
    nonisolated private static func silentNode(_ fmt: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: fmt) { _, _, _, abl -> OSStatus in
            for b in UnsafeMutableAudioBufferListPointer(abl) {
                if let p = b.mData { memset(p, 0, Int(b.mDataByteSize)) }
            }
            return noErr
        }
    }

    func stop() {
        timer?.cancel(); timer = nil
        stopSoon?.cancel(); stopSoon = nil
        guard running else { return }
        engine.stop()
        running = false
    }
}
