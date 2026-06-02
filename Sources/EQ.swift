import AVFoundation
import Accelerate
import MediaToolbox

// Einfacher Bass/Hoehen-Shelf-EQ ueber einen MTAudioProcessingTap am AVPlayerItem.
// Opt-in: Preset "Aus" (0/0 dB) setzt KEINEN Tap -> Normalpfad voellig unberuehrt.
// DSP via vDSP.Biquad (zwei Sections: Low-Shelf + High-Shelf), ein Biquad je Kanal.

struct EQPreset: Equatable {
    let name: String
    let bassDB: Float
    let trebleDB: Float
    var isFlat: Bool { bassDB == 0 && trebleDB == 0 }

    static let all: [EQPreset] = [
        EQPreset(name: "Aus", bassDB: 0, trebleDB: 0),
        EQPreset(name: "Bass Boost", bassDB: 6, trebleDB: 0),
        EQPreset(name: "Höhen Boost", bassDB: 0, trebleDB: 5),
        EQPreset(name: "Loudness", bassDB: 5, trebleDB: 4),
        EQPreset(name: "Vocal", bassDB: -3, trebleDB: 3),
        EQPreset(name: "Warm", bassDB: 3, trebleDB: -3),
    ]
}

// MARK: - Tap-Kontext (haelt die Biquad-Filter pro Kanal)
final class EQTapContext {
    let bassDB: Float
    let trebleDB: Float
    private var biquads: [vDSP.Biquad<Float>] = []
    init(bassDB: Float, trebleDB: Float) { self.bassDB = bassDB; self.trebleDB = trebleDB }

    func prepare(sampleRate: Double, channels: Int) {
        let coeffs = EQTapContext.shelfCoeffs(sampleRate: sampleRate, bassDB: Double(bassDB), trebleDB: Double(trebleDB))
        biquads = (0..<max(1, channels)).compactMap { _ in
            vDSP.Biquad(coefficients: coeffs, channelCount: 1, sectionCount: 2, ofType: Float.self)
        }
    }

    func process(_ abl: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard !biquads.isEmpty, frames > 0 else { return }
        let list = UnsafeMutableAudioBufferListPointer(abl)
        for (i, buf) in list.enumerated() {
            guard i < biquads.count, let raw = buf.mData else { continue }
            let n = min(frames, Int(buf.mDataByteSize) / MemoryLayout<Float>.size)
            guard n > 0 else { continue }
            let ptr = raw.assumingMemoryBound(to: Float.self)
            let out = biquads[i].apply(input: UnsafeBufferPointer(start: ptr, count: n))
            out.withUnsafeBufferPointer { src in
                if let base = src.baseAddress { ptr.update(from: base, count: min(n, src.count)) }
            }
        }
    }

    // RBJ-Cookbook Low-/High-Shelf, je normalisiert (a0=1) -> [b0,b1,b2,a1,a2] pro Section.
    static func shelfCoeffs(sampleRate: Double, bassDB: Double, trebleDB: Double) -> [Double] {
        lowShelf(f0: 100, sampleRate: sampleRate, gainDB: bassDB)
            + highShelf(f0: 6000, sampleRate: sampleRate, gainDB: trebleDB)
    }
    private static func lowShelf(f0: Double, sampleRate: Double, gainDB: Double) -> [Double] {
        let A = pow(10.0, gainDB / 40.0)
        let w0 = 2 * Double.pi * f0 / sampleRate
        let c = cos(w0), s = sin(w0)
        let alpha = s / 2 * sqrt(2.0)               // S = 1
        let twoSqrtAalpha = 2 * sqrt(A) * alpha
        let b0 =  A * ((A + 1) - (A - 1) * c + twoSqrtAalpha)
        let b1 =  2 * A * ((A - 1) - (A + 1) * c)
        let b2 =  A * ((A + 1) - (A - 1) * c - twoSqrtAalpha)
        let a0 =      (A + 1) + (A - 1) * c + twoSqrtAalpha
        let a1 = -2 * ((A - 1) + (A + 1) * c)
        let a2 =      (A + 1) + (A - 1) * c - twoSqrtAalpha
        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }
    private static func highShelf(f0: Double, sampleRate: Double, gainDB: Double) -> [Double] {
        let A = pow(10.0, gainDB / 40.0)
        let w0 = 2 * Double.pi * f0 / sampleRate
        let c = cos(w0), s = sin(w0)
        let alpha = s / 2 * sqrt(2.0)
        let twoSqrtAalpha = 2 * sqrt(A) * alpha
        let b0 =  A * ((A + 1) + (A - 1) * c + twoSqrtAalpha)
        let b1 = -2 * A * ((A - 1) + (A + 1) * c)
        let b2 =  A * ((A + 1) + (A - 1) * c - twoSqrtAalpha)
        let a0 =      (A + 1) - (A - 1) * c + twoSqrtAalpha
        let a1 =  2 * ((A - 1) - (A + 1) * c)
        let a2 =      (A + 1) - (A - 1) * c - twoSqrtAalpha
        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }
}

// MARK: - C-Callbacks (duerfen keinen Swift-Kontext capturen -> ueber clientInfo/Storage)
private let eqTapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    tapStorageOut.pointee = clientInfo
}
private let eqTapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    Unmanaged<EQTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}
private let eqTapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, processingFormat in
    let ctx = Unmanaged<EQTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    let f = processingFormat.pointee
    ctx.prepare(sampleRate: f.mSampleRate, channels: Int(f.mChannelsPerFrame))
}
private let eqTapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in }
private let eqTapProcess: MTAudioProcessingTapProcessCallback = { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }
    let ctx = Unmanaged<EQTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    ctx.process(bufferListInOut, frames: numberFramesOut.pointee)
}

/// Baut einen AVAudioMix mit EQ-Tap fuer das Item. nil = kein EQ (flat) oder keine Audiospur.
func makeEQAudioMix(for item: AVPlayerItem, preset: EQPreset) async -> AVAudioMix? {
    guard !preset.isFlat else { return nil }
    guard let tracks = try? await item.asset.loadTracks(withMediaType: .audio),
          let track = tracks.first else { return nil }

    let ctx = EQTapContext(bassDB: preset.bassDB, trebleDB: preset.trebleDB)
    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(ctx).toOpaque()),
        init: eqTapInit, finalize: eqTapFinalize, prepare: eqTapPrepare,
        unprepare: eqTapUnprepare, process: eqTapProcess)
    var tap: Unmanaged<MTAudioProcessingTap>?
    let err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                         kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
    guard err == noErr, let tap else {
        // Tap nicht erstellt -> Kontext-Retain wieder freigeben (sonst Leak), kein EQ.
        Unmanaged<EQTapContext>.fromOpaque(callbacks.clientInfo!).release()
        return nil
    }
    let params = AVMutableAudioMixInputParameters(track: track)
    params.audioTapProcessor = tap.takeRetainedValue()
    let mix = AVMutableAudioMix()
    mix.inputParameters = [params]
    return mix
}
