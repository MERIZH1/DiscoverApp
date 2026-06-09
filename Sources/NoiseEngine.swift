import Foundation
import AVFoundation
import SwiftUI

/// Hintergrund-Geraeusche, die PARALLEL zum Song laufen (iOS mischt automatisch).
/// Alles prozedural erzeugt -> keine Audiodateien, perfekte Endlosschleife.
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

/// Real-time-DSP — laeuft auf dem Audio-Thread (NICHT main-actor). Parameter
/// (type/volume/enabled) werden vom Main-Thread gesetzt und hier gelesen; ein
/// gelegentlich "zerrissener" Lesezugriff auf einen Float ist fuer Rauschen egal.
final class NoiseDSP: @unchecked Sendable {
    var enabled: Int32 = 0
    var type: Int32 = 2
    var volume: Float = 0.4
    private let sr: Float = 44100
    private let twoPi: Float = 2 * .pi
    private var rng: UInt64 = 0x9E3779B97F4A7C15
    private var brown: Float = 0
    private var lp: Float = 0
    private var lastW: Float = 0
    private var pk = [Float](repeating: 0, count: 7)
    private var lfo: Float = 0
    private var crackleTimer: Int = 0
    private var crackleEnv: Float = 0

    @inline(__always) private func white() -> Float {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Float(Int32(truncatingIfNeeded: rng)) / Float(Int32.max)
    }
    @inline(__always) private func unit() -> Float { (white() + 1) * 0.5 }

    @inline(__always) private func sample(_ ty: Int32) -> Float {
        let w = white()
        switch ty {
        case 0:                                   // White
            return w * 0.45
        case 1:                                   // Pink (Paul Kellet)
            pk[0] = 0.99886*pk[0] + w*0.0555179
            pk[1] = 0.99332*pk[1] + w*0.0750759
            pk[2] = 0.96900*pk[2] + w*0.1538520
            pk[3] = 0.86650*pk[3] + w*0.3104856
            pk[4] = 0.55000*pk[4] + w*0.5329522
            pk[5] = -0.7616*pk[5] - w*0.0168980
            let out = pk[0]+pk[1]+pk[2]+pk[3]+pk[4]+pk[5]+pk[6]+w*0.5362
            pk[6] = w*0.115926
            return out * 0.11
        case 2:                                   // Brown / Dark
            brown = (brown + 0.02*w) / 1.02
            return brown * 3.2
        case 3:                                   // Regen: hochpass-Rauschen
            let hp = w - lastW; lastW = w
            return hp * 0.32
        case 4:                                   // Meer: brown + langsame Welle
            brown = (brown + 0.02*w) / 1.02
            lfo += 0.10 / sr * twoPi
            if lfo > twoPi { lfo -= twoPi }
            let env = 0.35 + 0.65 * (0.5 + 0.5*sinf(lfo))
            return brown * 3.2 * env
        case 5:                                   // Wind: tiefpass + Boeen
            lp = lp*0.97 + w*0.03
            lfo += 0.20 / sr * twoPi
            if lfo > twoPi { lfo -= twoPi }
            let env = 0.3 + 0.7 * (0.5 + 0.5*sinf(lfo))
            return lp * 6.5 * env
        default:                                  // Feuer: rumble + crackle
            brown = (brown + 0.02*w) / 1.02
            var s = brown * 1.4
            crackleTimer -= 1
            if crackleTimer <= 0 { crackleEnv = 0.8 + unit()*0.2; crackleTimer = 30 + Int(unit()*1500) }
            if crackleEnv > 0.001 { s += white() * crackleEnv * 0.7; crackleEnv *= 0.55 }
            return s
        }
    }

    func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        let on = enabled != 0
        let vol = volume
        let ty = type
        for f in 0..<frames {
            let s = on ? sample(ty) * vol : 0
            for ch in 0..<abl.count {
                if let p = abl[ch].mData?.assumingMemoryBound(to: Float.self) { p[f] = s }
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
