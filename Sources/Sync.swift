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
    var updated_at: Double? = nil   // vom Server gesetzt (ms), Merker für /api/sync/wait
    enum CodingKeys: String, CodingKey {
        case device_id, device_name, track, position, duration, playing, shuffle
        case queue_idx, queue_len, queue_tracks, owner_seen_at, updated_at
        case repeatMode = "repeat"
    }
}
struct SyncStateResponse: Codable { let state: RemoteState? }

struct SyncDevice: Codable, Identifiable {
    let device_id: String
    let name: String
    let is_owner: Bool
    /// iOS hat die App eingefroren. Ein Befehl wartet 2 Minuten, bis sie wieder läuft.
    var asleep: Bool? = nil
    var id: String { device_id }
}
struct SyncDevicesResponse: Codable { let devices: [SyncDevice] }

// MARK: - SyncManager
// Owner = das Geraet, das gerade spielt -> pusht State + fuehrt eingehende Commands aus.
// Remote = ein anderes Geraet spielt -> wir zeigen Banner + senden Commands.
@MainActor
final class SyncManager: ObservableObject {
    @Published var remote: RemoteState?     // anderes Geraet spielt gerade
    @Published var injectToast = ""          // "X hat dir einen Song geschickt"
    /// Gleichzeitig auf mehreren Geräten hören (gilt fürs ganze Profil, liegt auf dem Server):
    /// Startet hier ein Song, hält das andere Gerät nicht an, und die Leiste zeigt den eigenen Song.
    @Published private(set) var multiDevice = UserDefaults.standard.bool(forKey: "multiDevice")

    private let api: APIClient
    private weak var player: PlayerController?
    let deviceID: String
    private let fallbackName: String
    /// Selbst gesetzter Geraete-Name (Einstellungen) — sonst der iOS-Geraetename.
    var deviceName: String {
        let custom = (UserDefaults.standard.string(forKey: "syncDeviceName") ?? "").trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? fallbackName : custom
    }
    private var loop: Task<Void, Never>?
    private var waiter: Task<Void, Never>?
    private var since: Double = 0

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
        fallbackName = UIDevice.current.name
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let ns = (await self?.tick()) ?? 2_500_000_000
                try? await Task.sleep(nanoseconds: ns)
            }
        }
        Task { [weak self] in await self?.loadMultiDevice() }
        waiter = Task { [weak self] in
            var fails: UInt64 = 0
            while !Task.isCancelled {
                guard let ok = await self?.waitOnce() else { return }
                fails = ok ? 0 : min(fails + 1, 10)
                if fails > 0 { try? await Task.sleep(nanoseconds: 1_500_000_000 * fails) }
            }
        }
    }
    func setMultiDevice(_ on: Bool) {
        multiDevice = on
        UserDefaults.standard.set(on, forKey: "multiDevice")
        Task { await api.saveSettings(["multi_device": on]) }
    }
    func loadMultiDevice() async {
        guard let m = (try? await api.settings())?.multi_device, m != multiDevice else { return }
        multiDevice = m
        UserDefaults.standard.set(m, forKey: "multiDevice")
    }

    func stop() {
        loop?.cancel(); loop = nil
        waiter?.cancel(); waiter = nil
    }

    private var wasOwner = false
    private var lastPush = 0.0

    /// Heartbeat: pusht den eigenen Stand, solange hier Musik läuft, und gibt das nächste
    /// Intervall (ns) zurück. Befehle und der Stand anderer Geräte kommen über waitOnce().
    @discardableResult
    private func tick() async -> UInt64 {
        let fast: UInt64 = 1_000_000_000, slow: UInt64 = 2_500_000_000
        guard let p = player else { return slow }
        let now = Date().timeIntervalSince1970
        if p.isPlaying && p.current != nil {
            if now - lastPush >= 2.4 {
                if let snap = snapshot(p) { await api.syncPushState(snap); lastPush = now }
            }
            wasOwner = true
            if let r = remote {
                // Wie bei Spotify spielt immer nur ein Geraet: Startet hier der Ton, stoppt das andere.
                // Ausnahme: Schalter „Gleichzeitig auf mehreren Geräten“.
                if r.playing == true, let id = r.device_id, !multiDevice {
                    await api.syncSendCommand("pause", value: nil, target: id, fromID: deviceID)
                }
                remote = nil
            }
        } else {
            // Play -> Pause-Wechsel: finalen State sofort pushen.
            if wasOwner {
                if let snap = snapshot(p) { await api.syncPushState(snap); lastPush = now }
                wasOwner = false
            }
            // Meldet sich das andere Gerät nicht mehr, verschwindet das Banner trotzdem.
            if let r = remote { applyRemote(r) }
        }
        return (p.isPlaying || remote != nil) ? fast : slow
    }

    /// Push statt Abfragen (02.11.2026): Der Server antwortet erst, wenn ein Befehl für
    /// dieses Gerät da ist, ein anderes Gerät seinen Stand ändert oder 12 s um sind.
    /// Vorher fragte die App jede Sekunde nach Befehlen und alle 1,4 s nach dem Stand.
    /// false bei Netzfehler, dann wartet die Schleife etwas länger.
    private func waitOnce() async -> Bool {
        guard let r = await api.syncWait(deviceID: deviceID, name: deviceName, since: since) else { return false }
        if let p = player, !r.commands.isEmpty {
            await execute(r.commands, p)
            if let snap = snapshot(p) { await api.syncPushState(snap); lastPush = Date().timeIntervalSince1970 }
        }
        if let s = r.state {
            if let u = s.updated_at { since = u }
            applyRemote(s)
        }
        // Kein freier Warteplatz auf dem Server: wie früher kurz warten
        if !r.wait { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        return true
    }

    /// Frische-Fenster: ein aktiv SPIELENDES Remote toleriert ein paar verpasste
    /// Heartbeats (Netz-Hiccup, Heartbeat ~2.5s), ein pausiertes/gestopptes Remote
    /// verschwindet dagegen zuegig, sonst klebt das Banner nach dem Stoppen am PC.
    private func applyRemote(_ s: RemoteState) {
        // Spielt es hier, kümmert sich tick() um das andere Gerät
        if player?.isPlaying ?? false { return }
        guard s.device_id != deviceID, let seen = s.owner_seen_at else { remote = nil; return }
        let age = Date().timeIntervalSince1970 * 1000 - seen
        let maxAge: Double = (s.playing == true) ? 6000 : 3000
        remote = (age < maxAge) ? s : nil
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

    private func execute(_ cmds: [[String: Any]], _ p: PlayerController) async {
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
                    p.setRepeat(v == "one" ? .one : (v == "all" ? .all : .off))
                }
            case "queue_inject":
                if let t = c["value"] as? [String: Any], let uri = t["uri"] as? String, let name = t["name"] as? String {
                    p.playNext(Track(uri: uri, name: name, artist: t["artist"] as? String ?? "", image: t["image"] as? String))
                    injectToast = "\(name) erhalten"
                    Task { try? await Task.sleep(nanoseconds: 2_500_000_000); injectToast = "" }
                }
            case "take_over":
                await handleTakeOver(p, value: c["value"])
            default: break
            }
        }
    }

    // MARK: - Remote-Steuerung (dieses Geraet ist Fernbedienung)
    private func send(_ cmd: String, value: Any? = nil) {
        let target = remote?.device_id
        Task { await api.syncSendCommand(cmd, value: value, target: target, fromID: deviceID) }
    }
    /// Steht das andere Geraet, geht es hier weiter statt dort.
    func remotePlayPause() {
        if remote?.playing == true { send("pause") } else { pullPlaybackHere() }
    }
    func remoteNext() { send("next") }
    func remotePrev() { send("prev") }
    func remoteSeek(_ t: Double) { send("seek", value: t) }
    /// Spielt ein anderes Geraet, gelten Shuffle und Wiederholen dort.
    func forwardModes(_ p: PlayerController) {
        guard remote?.playing == true else { return }
        send("set_shuffle", value: p.shuffle ? "on" : "off")
        send("set_repeat", value: p.repeatMode == .one ? "one" : (p.repeatMode == .all ? "all" : "off"))
    }

    // MARK: - Wiedergabe-Geraet wechseln (Connect-Style)
    func devices() async -> [SyncDevice] { await api.syncDevices() }
    func renameDevice(_ id: String, name: String) async { await api.syncRenameDevice(id, name: name) }

    /// Verschiebt die laufende Wiedergabe auf ein anderes Geraet.
    func switchPlaybackTo(_ targetID: String, name: String, asleep: Bool = false) {
        guard targetID != deviceID else { return }
        let ownerID = remote?.device_id ?? ((player?.isPlaying ?? false) ? deviceID : nil)
        Task {
            // Falls wir selbst Owner sind: State frisch pushen, damit das Ziel ihn holen kann.
            if remote == nil, let p = player, let snap = snapshot(p) { await api.syncPushState(snap) }
            await api.syncSendCommand("take_over", value: nil, target: targetID, fromID: deviceID)
            // Schlafendes Ziel: hier weiterspielen, bis es übernimmt und uns selbst stoppt.
            if asleep { return }
            if let ownerID, ownerID != targetID {
                if ownerID == deviceID { player?.pause() }
                else { await api.syncSendCommand("pause", value: nil, target: ownerID, fromID: deviceID) }
            }
        }
    }

    /// Dieses Geraet HOLT die laufende Wiedergabe zu sich (Owner -> hier).
    /// (Im Picker das eigene Geraet antippen; switchPlaybackTo blockt sich selbst.)
    func pullPlaybackHere() {
        guard let p = player else { return }
        let ownerID = remote?.device_id
        Task {
            await handleTakeOver(p, value: nil)   // frischen State (syncGetState) ziehen + lokal spielen
            if let ownerID, ownerID != deviceID {
                await api.syncSendCommand("pause", value: nil, target: ownerID, fromID: deviceID)
            }
        }
    }

    /// Dieses Geraet uebernimmt die Wiedergabe (track + position + queue) vom aktuellen Owner.
    private func handleTakeOver(_ p: PlayerController, value: Any?) async {
        var snap: RemoteState? = nil
        if let dict = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict) {
            snap = try? JSONDecoder().decode(RemoteState.self, from: data)
        }
        if snap == nil || (snap?.queue_tracks?.isEmpty ?? true) {
            snap = await api.syncGetState()
        }
        guard let s = snap else { return }
        let qt = s.queue_tracks ?? []
        let tracks = qt.map { Track(uri: $0.uri, name: $0.name, artist: $0.artist, image: $0.image) }
        // Snapshot-Reihenfolge exakt uebernehmen -> vor play() shuffle AUS, sonst
        // mischt play() die Queue neu (fisherYates) und Index/Position passen nicht.
        p.shuffle = false
        p.repeatMode = (s.repeatMode == "one" ? .one : (s.repeatMode == "all" ? .all : .off))
        p.handoffPosition = max(0, s.position ?? 0)
        if !tracks.isEmpty {
            let idx = max(0, min(tracks.count - 1, s.queue_idx ?? 0))
            p.play(tracks: tracks, startAt: idx, contextName: "Wiedergabe", contextURI: "connect:transfer")
        } else if let t = s.track {
            p.play(tracks: [Track(uri: t.uri, name: t.name, artist: t.artist, image: t.image)],
                   startAt: 0, contextName: "Wiedergabe", contextURI: "connect:transfer")
        } else { p.handoffPosition = 0; return }
        p.shuffle = (s.shuffle == "on")   // UI-Flag nachziehen (mischt nicht neu)
        remote = nil
        if let src = s.device_id, src != deviceID {
            await api.syncSendCommand("pause", value: nil, target: src, fromID: deviceID)
        }
    }
}

// MARK: - Wiedergabe-Geraet-Picker (Connect-Style Geraetewechsel)
struct DevicePickerSheet: View {
    @EnvironmentObject var sync: SyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var devices: [SyncDevice] = []
    @State private var loading = true
    @State private var renaming: SyncDevice?
    @State private var newName = ""
    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { Spacer(); ProgressView().tint(Theme.accent); Spacer() }
                        .listRowBackground(Color.clear)
                } else if devices.isEmpty {
                    Text("Keine aktiven Geräte gefunden. Öffne Discover auf einem anderen Gerät im selben Profil.")
                        .font(.system(size: 14)).foregroundStyle(Theme.sub)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(devices) { dev in
                        Button {
                            if dev.is_owner { dismiss(); return }
                            if dev.device_id == sync.deviceID {
                                sync.pullPlaybackHere()        // dieses Geraet holt die Wiedergabe her
                            } else {
                                sync.switchPlaybackTo(dev.device_id, name: dev.name, asleep: dev.asleep == true)
                            }
                            Haptics.tap(); dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: (dev.name.lowercased().contains("phone") || dev.name.lowercased().contains("pad")) ? "iphone" : "desktopcomputer")
                                    .font(.system(size: 18)).foregroundStyle(dev.is_owner ? Theme.accent : Theme.text)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dev.name + (dev.device_id == sync.deviceID ? " (dieses Gerät)" : ""))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(dev.is_owner ? Theme.accent : Theme.text)
                                    Text(dev.is_owner ? "Spielt gerade" : (dev.asleep == true ? "Schläft · übernimmt beim Öffnen" : "Bereit"))
                                        .font(.system(size: 12)).foregroundStyle(Theme.sub)
                                }
                                .opacity(dev.asleep == true ? 0.6 : 1)
                                Spacer()
                                if dev.is_owner { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Umbenennen") { newName = dev.name; renaming = dev }.tint(Theme.input)
                        }
                        .contextMenu {
                            Button { newName = dev.name; renaming = dev } label: { Label("Umbenennen", systemImage: "pencil") }
                        }
                    }
                }
                Section {
                    Toggle(isOn: Binding(get: { sync.multiDevice }, set: { sync.setMultiDevice($0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gleichzeitig auf mehreren Geräten")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("Startet hier ein Song, spielt das andere Gerät weiter")
                                .font(.system(size: 12)).foregroundStyle(Theme.sub)
                        }
                    }
                    .tint(Theme.accent)
                    .accessibilityIdentifier("devices.multi")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Wiedergabe-Gerät")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
        }
        .task {
            loading = true
            devices = await sync.devices()
            loading = false
            await sync.loadMultiDevice()
        }
        .alert("Gerät umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Sichern") {
                guard let dev = renaming else { return }
                let name = newName.trimmingCharacters(in: .whitespaces)
                Task {
                    await sync.renameDevice(dev.device_id, name: name)
                    devices = await sync.devices()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Der Name gilt auf allen Geräten.") }
    }
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
