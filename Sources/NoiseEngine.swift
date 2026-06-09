import Foundation
import AVFoundation
import SwiftUI

/// Hintergrund-Geraeusche, die PARALLEL zum Song laufen (iOS mischt automatisch).
/// Color Noises sind prozedural (physikalisch korrekt); Natur-Sounds sind DSP-
/// Annaeherungen. L/R werden unabhaengig erzeugt -> echte Stereo-Breite.
enum NoiseType: String, CaseIterable, Identifiable {
    case white, pink, brown, rain, ocean, wind, fire
    var id: String { rawValue }
    var label: String {
        switch self {
        case .white: return "White"
        case .pink:  return "Pink"
        case .brown: return "Brown / Dark"
        case .rain:  return "Regen"
        case .ocean: return "Meer"
        case .wind:  return "Wind"
        case .fire:  return "Kaminfeuer"
        }
    }
    var icon: String {
        switch self {
        case .white: return "waveform"
        case .pink:  return "waveform.path"
        case .brown: return "waveform.path.ecg"
        case .rain:  return "cloud.rain.fill"
        case .ocean: return "water.waves"
        case .wind:  return "wind"
        case .fire:  return "flame.fill"
        }
    }
    fileprivate var dspIndex: Int32 {
        switch self {
        case .white: return 0; case .pink: return 1; case .brown: return 2
        case .rain: return 3; case .ocean: return 4; case .wind: return 5; case .fire: return 6
        }
    }
}

/// Real-time-DSP — laeuft auf dem Audio-Thread (NICHT main-actor). Pro Kanal (L/R)
/// eigener Zustand -> dekorrelierte Stereo-Breite. Parameter werden vom Main-Thread
/// gesetzt; ein gelegentlich "zerrissener" Float-Lesezugriff ist fuer Rauschen egal.
final class NoiseDSP: @unchecked Sendable {
    var enabled: Int32 = 0
    var type: Int32 = 2
    var volume: Float = 0.4
    private let sr: Float = 44100
    private let twoPi: Float = 2 * .pi
    // Pro Kanal (Index 0 = L, 1 = R) eigener Zustand
    private var rng: [UInt64] = [0x9E3779B97F4A7C15, 0xD1B54A32D192ED03]
    private var brown: [Float] = [0, 0]
    private var lp: [Float] = [0, 0]
    private var lastW: [Float] = [0, 0]
    private var pk: [[Float]] = [[Float](repeating: 0, count: 7), [Float](repeating: 0, count: 7)]
    private var lfo: [Float] = [0, 1.7]            // versetzte Startphase -> Bewegung
    private var crackleTimer: [Int] = [0, 0]
    private var crackleEnv: [Float] = [0, 0]

    @inline(__always) private func white(_ c: Int) -> Float {
        var x = rng[c]; x ^= x << 13; x ^= x >> 7; x ^= x << 17; rng[c] = x
        return Float(Int32(truncatingIfNeeded: x)) / Float(Int32.max)
    }
    @inline(__always) private func unit(_ c: Int) -> Float { (white(c) + 1) * 0.5 }

    @inline(__always) private func sample(_ ty: Int32, _ c: Int) -> Float {
        let w = white(c)
        switch ty {
        case 0:                                   // White
            return w * 0.45
        case 1:                                   // Pink (Paul Kellet)
            pk[c][0] = 0.99886*pk[c][0] + w*0.0555179
            pk[c][1] = 0.99332*pk[c][1] + w*0.0750759
            pk[c][2] = 0.96900*pk[c][2] + w*0.1538520
            pk[c][3] = 0.86650*pk[c][3] + w*0.3104856
            pk[c][4] = 0.55000*pk[c][4] + w*0.5329522
            pk[c][5] = -0.7616*pk[c][5] - w*0.0168980
            let out = pk[c][0]+pk[c][1]+pk[c][2]+pk[c][3]+pk[c][4]+pk[c][5]+pk[c][6]+w*0.5362
            pk[c][6] = w*0.115926
            return out * 0.11
        case 2:                                   // Brown / Dark
            brown[c] = (brown[c] + 0.02*w) / 1.02
            return brown[c] * 3.2
        case 3:                                   // Regen: Patter + Tropfen
            let hp = w - lastW[c]*0.85; lastW[c] = w
            var s = hp * 0.26
            crackleTimer[c] -= 1
            if crackleTimer[c] <= 0 { crackleEnv[c] = 0.5 + unit(c)*0.5; crackleTimer[c] = 180 + Int(unit(c)*1200) }
            if crackleEnv[c] > 0.001 { s += white(c) * crackleEnv[c] * 0.14; crackleEnv[c] *= 0.7 }
            return s
        case 4:                                   // Meer: Surf mit asymmetrischer Welle + Gischt
            brown[c] = (brown[c] + 0.02*w) / 1.02
            lfo[c] += 0.09 / sr * twoPi
            if lfo[c] > twoPi { lfo[c] -= twoPi }
            let ph = (sinf(lfo[c]) + 1) * 0.5
            let env = powf(ph, 2.2) * 0.9 + 0.1
            let foam = w - lastW[c]; lastW[c] = w
            return (brown[c] * 3.0 + foam * 0.22) * env
        case 5:                                   // Wind: Tiefpass + Boeen
            lp[c] = lp[c]*0.96 + w*0.04
            lfo[c] += 0.18 / sr * twoPi
            if lfo[c] > twoPi { lfo[c] -= twoPi }
            let env = 0.25 + 0.75 * powf((sinf(lfo[c]) + 1) * 0.5, 1.5)
            return lp[c] * 6.5 * env
        default:                                  // Feuer: rumble + crackle
            brown[c] = (brown[c] + 0.02*w) / 1.02
            var s = brown[c] * 1.3
            crackleTimer[c] -= 1
            if crackleTimer[c] <= 0 { crackleEnv[c] = 0.7 + unit(c)*0.3; crackleTimer[c] = 40 + Int(unit(c)*1400) }
            if crackleEnv[c] > 0.001 { s += white(c) * crackleEnv[c] * 0.6; crackleEnv[c] *= 0.5 }
            return s
        }
    }

    func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        let on = enabled != 0
        let vol = volume
        let ty = type
        for ch in 0..<abl.count {
            guard let p = abl[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
            let c = ch % 2                          // L/R unabhaengig -> Stereo-Breite
            for f in 0..<frames {
                p[f] = on ? sample(ty, c) * vol : 0
            }
        }
    }
}

@MainActor
final class NoiseEngine: ObservableObject {
    static let shared = NoiseEngine()
    @Published private(set) var active: NoiseType? = nil
    @Published var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: "noiseVolume")
            dsp.volume = Float(volume)
        }
    }
    private let engine = AVAudioEngine()
    private let dsp = NoiseDSP()
    private var node: AVAudioSourceNode?
    private var setup = false

    private init() {
        let v = UserDefaults.standard.object(forKey: "noiseVolume") as? Double ?? 0.4
        self.volume = v
        self.dsp.volume = Float(v)
    }

    private func ensureSetup() {
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

    func toggle(_ type: NoiseType) { active == type ? stop() : start(type) }

    func start(_ type: NoiseType) {
        ensureSetup()
        dsp.type = type.dspIndex
        dsp.enabled = 1
        active = type
        if !engine.isRunning {
            try? AVAudioSession.sharedInstance().setActive(true)
            do { try engine.start() } catch { dsp.enabled = 0; active = nil }
        }
    }

    func stop() {
        dsp.enabled = 0
        active = nil
        engine.pause()   // pause statt stop -> schnelles Wieder-Anlaufen
    }
}

// MARK: - UI
struct NoiseSheet: View {
    @ObservedObject var noise = NoiseEngine.shared
    @Environment(\.dismiss) private var dismiss
    private let cols = [GridItem(.adaptive(minimum: 96), spacing: 12)]
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Laeuft zusaetzlich zum Song. Tippe zum An-/Ausschalten.")
                    .font(.system(size: 13)).foregroundStyle(Theme.sub)
                    .multilineTextAlignment(.center).padding(.horizontal)
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(NoiseType.allCases) { t in
                        Button { noise.toggle(t) } label: {
                            VStack(spacing: 8) {
                                Image(systemName: t.icon).font(.system(size: 22))
                                Text(t.label).font(.system(size: 12, weight: .semibold))
                                    .multilineTextAlignment(.center).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(noise.active == t ? Theme.accent.opacity(0.22) : Theme.input)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(noise.active == t ? Theme.accent : .clear, lineWidth: 2))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(noise.active == t ? Theme.accent : Theme.text)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal)
                if noise.active != nil {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill").foregroundStyle(Theme.sub).font(.system(size: 13))
                        Slider(value: $noise.volume, in: 0...1).tint(Theme.accent)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.sub).font(.system(size: 13))
                    }.padding(.horizontal)
                    Button { noise.stop() } label: {
                        Label("Sound aus", systemImage: "stop.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }.foregroundStyle(Theme.accent)
                }
                Spacer()
            }
            .padding(.top, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Hintergrund-Sound").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }.foregroundStyle(Theme.accent) } }
        }
        .presentationDetents([.medium, .large])
    }
}
