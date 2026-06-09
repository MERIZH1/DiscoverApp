import Foundation
import AVFoundation
import SwiftUI

/// Color Noises (prozedural, physikalisch korrekt, Stereo). Natur-Sounds kommen
/// als echte Dateien vom Server (siehe AmbientSound).
enum NoiseType: String, CaseIterable, Identifiable {
    case white, pink, brown
    var id: String { rawValue }
    var label: String {
        switch self { case .white: return "White"; case .pink: return "Pink"; case .brown: return "Brown / Dark" }
    }
    var icon: String {
        switch self { case .white: return "waveform"; case .pink: return "waveform.path"; case .brown: return "waveform.path.ecg" }
    }
    fileprivate var dspIndex: Int32 {
        switch self { case .white: return 0; case .pink: return 1; case .brown: return 2 }
    }
}

/// Eine Hintergrund-Sound-Datei vom Server (static/ambient/, Auto-Discovery).
struct AmbientSound: Codable, Identifiable, Hashable {
    let id: String          // Dateiname
    let name: String
    let url: String
    var icon: String {
        let n = name.lowercased()
        if n.contains("rain") || n.contains("regen") { return "cloud.rain.fill" }
        if n.contains("ocean") || n.contains("sea") || n.contains("meer") || n.contains("wave") { return "water.waves" }
        if n.contains("stream") || n.contains("water") || n.contains("bach") || n.contains("river") { return "drop.fill" }
        if n.contains("fire") || n.contains("feuer") || n.contains("camp") { return "flame.fill" }
        if n.contains("wind") { return "wind" }
        if n.contains("forest") || n.contains("wald") || n.contains("bird") { return "tree.fill" }
        if n.contains("thunder") || n.contains("storm") { return "cloud.bolt.rain.fill" }
        if n.contains("night") || n.contains("cricket") { return "moon.stars.fill" }
        return "music.note"
    }
}
struct AmbientResponse: Codable { let sounds: [AmbientSound] }

/// Real-time-DSP fuer Color Noise — laeuft auf dem Audio-Thread (NICHT main-actor).
/// Pro Kanal (L/R) eigener Zustand -> echte Stereo-Breite.
final class NoiseDSP: @unchecked Sendable {
    var enabled: Int32 = 0
    var type: Int32 = 2
    var volume: Float = 0.4
    var fadeTarget: Float = 1                         // 0 = ausblenden, 1 = einblenden
    private var fadeGain: Float = 0
    private let fadeStep: Float = 1.0 / (0.2 * 44100) // 0.2s Ein-/Ausblende
    private var rng: [UInt64] = [0x9E3779B97F4A7C15, 0xD1B54A32D192ED03]
    private var brown: [Float] = [0, 0]
    private var pk: [[Float]] = [[Float](repeating: 0, count: 7), [Float](repeating: 0, count: 7)]

    @inline(__always) private func white(_ c: Int) -> Float {
        var x = rng[c]; x ^= x << 13; x ^= x >> 7; x ^= x << 17; rng[c] = x
        return Float(Int32(truncatingIfNeeded: x)) / Float(Int32.max)
    }
    @inline(__always) private func sample(_ ty: Int32, _ c: Int) -> Float {
        let w = white(c)
        switch ty {
        case 0:                                   // White (lauter + ausbalanciert)
            return w * 0.85
        case 1:                                   // Pink (war deutlich zu leise)
            pk[c][0] = 0.99886*pk[c][0] + w*0.0555179
            pk[c][1] = 0.99332*pk[c][1] + w*0.0750759
            pk[c][2] = 0.96900*pk[c][2] + w*0.1538520
            pk[c][3] = 0.86650*pk[c][3] + w*0.3104856
            pk[c][4] = 0.55000*pk[c][4] + w*0.5329522
            pk[c][5] = -0.7616*pk[c][5] - w*0.0168980
            let out = pk[c][0]+pk[c][1]+pk[c][2]+pk[c][3]+pk[c][4]+pk[c][5]+pk[c][6]+w*0.5362
            pk[c][6] = w*0.115926
            return out * 0.24
        default:                                  // Brown / Dark
            brown[c] = (brown[c] + 0.02*w) / 1.02
            return brown[c] * 3.6
        }
    }
    func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        let vol = volume * 1.3, ty = type                      // +30 % Pegel
        let nch = abl.count
        if enabled == 0 {                                       // aus -> Stille + Fade fuer naechsten Start zuruecksetzen
            fadeGain = 0
            for ch in 0..<nch {
                if let p = abl[ch].mData?.assumingMemoryBound(to: Float.self) {
                    for f in 0..<frames { p[f] = 0 }
                }
            }
            return
        }
        for f in 0..<frames {
            if fadeGain < fadeTarget { fadeGain = min(fadeTarget, fadeGain + fadeStep) }
            else if fadeGain > fadeTarget { fadeGain = max(fadeTarget, fadeGain - fadeStep) }
            let g = fadeGain
            for ch in 0..<nch {
                guard let p = abl[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                let c = ch % 2
                var s = sample(ty, c) * vol * g
                if s > 1 { s = 1 } else if s < -1 { s = -1 }   // begrenzen statt harter Verzerrung
                p[f] = s
            }
        }
    }
}

@MainActor
final class NoiseEngine: ObservableObject {
    static let shared = NoiseEngine()
    @Published private(set) var activeId: String? = nil      // "color:white" | "file:Rain_1.m4a"
    @Published var ambient: [AmbientSound] = []
    @Published var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: "noiseVolume")
            dsp.volume = Float(volume)
            filePlayer?.volume = Float(volume)
        }
    }
    private let engine = AVAudioEngine()
    private let dsp = NoiseDSP()
    private var node: AVAudioSourceNode?
    private var setup = false
    private var filePlayer: AVAudioPlayer?
    private var fileCache: [String: URL] = [:]
    private var api: APIClient? { DiscoverServices.app?.api }

    private init() {
        let v = UserDefaults.standard.object(forKey: "noiseVolume") as? Double ?? 0.4
        self.volume = v
        self.dsp.volume = Float(v)
    }

    static func colorId(_ t: NoiseType) -> String { "color:" + t.rawValue }
    static func fileId(_ s: AmbientSound) -> String { "file:" + s.id }
    static func audioExt(mime: String?, fallback: String) -> String {
        let m = (mime ?? "").lowercased()
        if m.contains("mp4") || m.contains("m4a") || m.contains("aac") { return "m4a" }
        if m.contains("mpeg") || m.contains("mp3") { return "mp3" }
        if m.contains("flac") { return "flac" }
        if m.contains("wav") { return "wav" }
        if m.contains("aiff") || m.contains("aif") { return "aiff" }
        let f = fallback.lowercased()
        return ["m4a","mp3","aac","flac","wav","aiff","aif","caf"].contains(f) ? f : "m4a"
    }
    func isActive(_ id: String) -> Bool { activeId == id }

    func loadAmbient() {
        Task { if let list = await api?.ambientSounds() { ambient = list } }
    }

    // MARK: Color Noise (prozedural)
    func toggleColor(_ t: NoiseType) {
        let id = Self.colorId(t)
        if activeId == id { stopAll() } else { startColor(t, id: id) }
    }
    private func startColor(_ t: NoiseType, id: String) {
        stopFile()
        ensureEngine()
        dsp.type = t.dspIndex
        dsp.fadeTarget = 1            // 0.2s einblenden (Fade aus enabled==0 startet bei 0)
        dsp.enabled = 1
        activeId = id
        if !engine.isRunning {
            try? AVAudioSession.sharedInstance().setActive(true)
            do { try engine.start() } catch { dsp.enabled = 0; activeId = nil }
        }
    }
    private func ensureEngine() {
        guard !setup else { return }
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else { return }
        let d = dsp
        let n = AVAudioSourceNode(format: fmt) { _, _, frameCount, ablPtr -> OSStatus in
            d.render(Int(frameCount), UnsafeMutableAudioBufferListPointer(ablPtr))
            return noErr
        }
        node = n
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: fmt)
        setup = true
    }

    // MARK: Ambient (Datei vom Server, gapless geloopt)
    func toggleFile(_ s: AmbientSound) {
        let id = Self.fileId(s)
        if activeId == id { stopAll() } else { startFile(s, id: id) }
    }
    private func startFile(_ s: AmbientSound, id: String) {
        stopEngine()
        activeId = id
        if let local = fileCache[s.id] { playLoop(local, id: id); return }
        guard let api = api, let url = api.absoluteURL(s.url) else { activeId = nil; return }
        Task {
            var req = URLRequest(url: url)
            if let pid = api.profileId { req.setValue(pid, forHTTPHeaderField: "X-Profile-Id") }
            guard let (data, resp) = try? await URLSession.shared.data(for: req), data.count > 1000 else {
                if activeId == id { activeId = nil }; return
            }
            // Endung aus Content-Type (Server liefert normalisiertes m4a) -> kein Format-Raten
            let ext = Self.audioExt(mime: resp.mimeType, fallback: (s.id as NSString).pathExtension)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("amb_\(abs(s.id.hashValue)).\(ext)")
            try? data.write(to: dest)
            fileCache[s.id] = dest
            if activeId == id { playLoop(dest, id: id) }     // noch gewuenscht?
        }
    }
    private func playLoop(_ url: URL, id: String) {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1                 // gapless endlos
            p.volume = 0
            p.prepareToPlay(); p.play()
            p.setVolume(Float(volume), fadeDuration: 0.2)   // 0.2s einblenden
            filePlayer = p
        } catch { if activeId == id { activeId = nil } }
    }

    // MARK: Stop
    private func stopEngine() {
        guard engine.isRunning, dsp.enabled != 0 else { dsp.enabled = 0; return }
        dsp.fadeTarget = 0                                  // 0.2s ausblenden
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            if self.dsp.fadeTarget == 0 {                  // nicht inzwischen neu gestartet?
                self.dsp.enabled = 0
                if self.engine.isRunning { self.engine.pause() }
            }
        }
    }
    private func stopFile() {
        guard let p = filePlayer else { return }
        filePlayer = nil
        p.setVolume(0, fadeDuration: 0.2)                  // 0.2s ausblenden, dann stoppen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { p.stop() }
    }
    func stopAll() { stopEngine(); stopFile(); activeId = nil }
}

// MARK: - UI
struct NoiseSheet: View {
    @ObservedObject var noise = NoiseEngine.shared
    @Environment(\.dismiss) private var dismiss
    private let cols = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    @ViewBuilder private func chip(_ label: String, _ icon: String, _ on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22))
                Text(label).font(.system(size: 12, weight: .semibold))
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(on ? Theme.accent.opacity(0.22) : Theme.input)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Theme.accent : .clear, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(on ? Theme.accent : Theme.text)
        }.buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Laeuft zusaetzlich zum Song. Nochmal tippen = aus.")
                        .font(.system(size: 13)).foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.horizontal)

                    Text("COLOR NOISE").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.sub).tracking(1).padding(.horizontal)
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(NoiseType.allCases) { t in
                            chip(t.label, t.icon, noise.isActive(NoiseEngine.colorId(t))) { noise.toggleColor(t) }
                        }
                    }.padding(.horizontal)

                    if !noise.ambient.isEmpty {
                        Text("AMBIENT").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.sub).tracking(1).padding(.horizontal).padding(.top, 4)
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(noise.ambient) { s in
                                chip(s.name, s.icon, noise.isActive(NoiseEngine.fileId(s))) { noise.toggleFile(s) }
                            }
                        }.padding(.horizontal)
                    }

                    if noise.activeId != nil {
                        HStack(spacing: 12) {
                            Image(systemName: "speaker.fill").foregroundStyle(Theme.sub).font(.system(size: 13))
                            Slider(value: $noise.volume, in: 0...1).tint(Theme.accent)
                            Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.sub).font(.system(size: 13))
                        }.padding(.horizontal).padding(.top, 4)
                        Button { noise.stopAll() } label: {
                            Label("Sound aus", systemImage: "stop.circle.fill").font(.system(size: 15, weight: .semibold))
                        }.foregroundStyle(Theme.accent).frame(maxWidth: .infinity)
                    }
                }.padding(.vertical, 16)
            }
            .background(Theme.bg)
            .navigationTitle("Hintergrund-Sound").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }.foregroundStyle(Theme.accent) } }
            .onAppear { noise.loadAmbient() }
        }
        .presentationDetents([.medium, .large])
    }
}
