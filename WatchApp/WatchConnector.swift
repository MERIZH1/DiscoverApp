import Foundation
import SwiftUI
import WatchConnectivity

/// Watch-Seite der Bruecke: empfaengt den gespiegelten Zustand vom iPhone
/// (updateApplicationContext) und schickt Steuer-Kommandos zurueck.
@MainActor
final class WatchConnector: NSObject, ObservableObject {
    static let shared = WatchConnector()

    @Published var state = WatchState()
    @Published var localPosition: Double = 0   // lokal hochgezaehlt zwischen Updates
    @Published var reachable = false

    private var timer: Timer?

    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        // Falls schon ein Kontext anliegt (App war zu): sofort uebernehmen.
        apply(context: s.receivedApplicationContext)
        startTimer()
    }

    // MARK: - Kommandos
    func send(_ msg: [String: Any]) {
        let s = WCSession.default
        if s.isReachable {
            s.sendMessage(msg, replyHandler: nil, errorHandler: { _ in s.transferUserInfo(msg) })
        } else {
            s.transferUserInfo(msg)   // wird zugestellt, sobald das iPhone erreichbar ist
        }
    }
    func requestSync()             { send([WatchCmd.key: WatchCmd.sync]) }
    func toggle()                  { send([WatchCmd.key: WatchCmd.toggle]); state.playing.toggle() }
    func next()                    { send([WatchCmd.key: WatchCmd.next]) }
    func prev()                    { send([WatchCmd.key: WatchCmd.prev]) }
    func shuffle()                 { send([WatchCmd.key: WatchCmd.shuffle]); state.shuffle.toggle() }
    func cycleRepeat()             { send([WatchCmd.key: WatchCmd.repeatMode]) }
    func playAt(_ i: Int)          { send([WatchCmd.key: WatchCmd.playAt, "index": i]) }
    func playPlaylist(_ uri: String) { send([WatchCmd.key: WatchCmd.playPlaylist, "uri": uri]) }

    // MARK: - Zustand uebernehmen
    private func apply(context: [String: Any]) {
        guard let data = context[WatchState.ctxKey] as? Data,
              let st = try? JSONDecoder().decode(WatchState.self, from: data) else { return }
        self.state = st
        // Position auf den Sample-Zeitpunkt hochrechnen (Update kann alt sein).
        let elapsed = st.playing ? max(0, Date().timeIntervalSince1970 - st.ts) : 0
        self.localPosition = min(st.duration > 0 ? st.duration : st.position + elapsed,
                                 st.position + elapsed)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.playing, self.state.duration > 0 else { return }
                self.localPosition = min(self.state.duration, self.localPosition + 1)
            }
        }
    }
}

extension WatchConnector: WCSessionDelegate {
    nonisolated func session(_ s: WCSession, activationDidCompleteWith st: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.reachable = s.isReachable
            self.apply(context: s.receivedApplicationContext)
            self.requestSync()
        }
    }
    nonisolated func session(_ s: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        Task { @MainActor in self.apply(context: ctx) }
    }
    nonisolated func sessionReachabilityDidChange(_ s: WCSession) {
        Task { @MainActor in
            self.reachable = s.isReachable
            if s.isReachable { self.requestSync() }
        }
    }
}
