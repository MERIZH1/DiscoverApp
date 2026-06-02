import SwiftUI
import UIKit

// MARK: - Sync-Modelle (gleiche Form wie PWA-Snapshot)
struct SyncTrack: Codable, Hashable {
    let name: String
    let artist: String
    let uri: String
    let image: String?
}
struct RemoteState: Codable {
    let device_id: String?
    let device_name: String?
    let track: SyncTrack?
    let position: Double?
    let duration: Double?
    let playing: Bool?
    let shuffle: String?
    let repeatMode: String?
    let queue_idx: Int?
    let queue_len: Int?
    let queue_tracks: [SyncTrack]?
    let owner_seen_at: Double?   // vom Server gesetzt (ms) -> Frische-Check
    enum CodingKeys: String, CodingKey {
        case device_id, device_name, track, position, duration, playing, shuffle
        case queue_idx, queue_len, queue_tracks, owner_seen_at
        case repeatMode = "repeat"
    }
}
struct SyncStateResponse: Codable { let state: RemoteState? }

// MARK: - SyncManager
// Owner = das Geraet, das gerade spielt -> pusht State + fuehrt eingehende Commands aus.
// Remote = ein anderes Geraet spielt -> wir zeigen Banner + senden Commands.
@MainActor
final class SyncManager: ObservableObject {
    @Published var remote: RemoteState?     // anderes Geraet spielt gerade
    @Published var injectToast = ""          // "X hat dir einen Song geschickt"

    private let api: APIClient
    private weak var player: PlayerController?
    let deviceID: String
    let deviceName: String
    private var loop: Task<Void, Never>?

    init(api: APIClient, player: PlayerController) {
        self.api = api
        self.player = player
        if let id = UserDefaults.standard.string(forKey: "syncDeviceID") {
            deviceID = id
        } else {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: "syncDeviceID")
            deviceID = id
        }
        deviceName = UIDevice.current.name
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }
    func stop() { loop?.cancel(); loop = nil }

    private var wasOwner = false

    private func tick() async {
        guard let p = player else { return }
        if p.isPlaying && p.current != nil {
            // Owner: erst Commands (z.B. pause), DANN State pushen -> reflektiert die
            // Aenderung sofort (sonst sieht die Remote die Pause nicht).
            await consumeCommands(p)
            if let snap = snapshot(p) { await api.syncPushState(snap) }
            wasOwner = true
            if remote != nil { remote = nil }
        } else {
            // Gerade von Playing -> Pause/Stop gewechselt? Einmal finalen State pushen,
            // damit Remotes "pausiert" sehen statt in den Timeout zu laufen.
            if wasOwner {
                if let snap = snapshot(p) { await api.syncPushState(snap) }
                wasOwner = false
            }
            await consumeCommands(p)   // play / queue_inject auch im Pausezustand annehmen
            // Spielt ein anderes Geraet? (frischer State, egal ob play/pause -> Banner mit Play/Pause)
            let s = await api.syncGetState()
            let nowMs = Date().timeIntervalSince1970 * 1000
            if let s, s.device_name != deviceName, let seen = s.owner_seen_at, (nowMs - seen) < 15000 {
                remote = s
            } else {
                remote = nil
            }
        }
    }

    private func snapshot(_ p: PlayerController) -> [String: Any]? {
        guard let t = p.current else { return nil }
        func enc(_ x: Track) -> [String: Any] {
            ["name": x.name, "artist": x.artist, "uri": x.uri, "image": x.image ?? ""]
        }
        return [
            "device_id": deviceID, "device_name": deviceName,
            "track": enc(t),
            "position": p.currentTime, "duration": p.duration, "playing": p.isPlaying,
            "shuffle": p.shuffle ? "on" : "off",
            "repeat": p.repeatMode == .one ? "one" : (p.repeatMode == .all ? "all" : "off"),
            "queue_idx": p.index, "queue_len": p.queue.count,
            "queue_tracks": p.queue.prefix(200).map(enc),
        ]
    }

    private func consumeCommands(_ p: PlayerController) async {
        let cmds = await api.syncGetCommands(deviceID: deviceID)
        for c in cmds {
            switch c["cmd"] as? String ?? "" {
            case "play":  p.resume()
            case "pause": p.pause()
            case "next":  p.next()
            case "prev":  p.prev()
            case "seek":
                if let v = c["value"] as? Double { p.seek(v) }
                else if let v = c["value"] as? Int { p.seek(Double(v)) }
            case "set_shuffle":
                if let v = c["value"] as? String, (v != "off") != p.shuffle { p.toggleShuffle() }
            case "set_repeat":
                if let v = c["value"] as? String {
                    p.repeatMode = (v == "one" ? .one : (v == "all" ? .all : .off))
                }
            case "queue_inject":
                if let t = c["value"] as? [String: Any], let uri = t["uri"] as? String, let name = t["name"] as? String {
                    p.playNext(Track(uri: uri, name: name, artist: t["artist"] as? String ?? "", image: t["image"] as? String))
                    injectToast = "📥 \(name) erhalten"
                    Task { try? await Task.sleep(nanoseconds: 2_500_000_000); injectToast = "" }
                }
            default: break
            }
        }
    }

    // MARK: - Remote-Steuerung (dieses Geraet ist Fernbedienung)
    private func send(_ cmd: String, value: Any? = nil) {
        let target = remote?.device_id
        Task { await api.syncSendCommand(cmd, value: value, target: target, fromID: deviceID) }
    }
    func remotePlayPause() { send((remote?.playing == true) ? "pause" : "play") }
    func remoteNext() { send("next") }
    func remotePrev() { send("prev") }
    func remoteSeek(_ t: Double) { send("seek", value: t) }
}

// MARK: - Remote-Banner (erscheint, wenn ein anderes Geraet spielt)
struct SyncBanner: View {
    @EnvironmentObject var sync: SyncManager
    var body: some View {
        if let r = sync.remote, let t = r.track {
            HStack(spacing: 12) {
                Artwork(url: t.image, size: 44, corner: 5)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Image(systemName: "wifi").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accent)
                        Text("Läuft auf \(r.device_name ?? "anderem Gerät")")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent).lineLimit(1)
                    }
                    Text(t.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(t.artist).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer()
                Button { sync.remotePrev() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 16)).foregroundStyle(Theme.text)
                        .frame(width: 34, height: 34).contentShape(Rectangle())
                }
                Button { sync.remotePlayPause() } label: {
                    Image(systemName: (r.playing == true) ? "pause.fill" : "play.fill").font(.title3).foregroundStyle(.black)
                        .frame(width: 38, height: 38).background(.white).clipShape(Circle())
                }
                Button { sync.remoteNext() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 16)).foregroundStyle(Theme.text)
                        .frame(width: 34, height: 34).contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex6: 0x1E2A24))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.4), lineWidth: 1)))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        }
    }
}
