import SwiftUI

/// Sonderdesign für besondere Tage. Was es zeigt (Symbol, Farben, Akzent, Zeitraum), bestimmt
/// allein der Server unter /api/special. Ohne Eintrag dort sieht die App aus wie immer.
/// Der letzte Stand wird bis zu seinem Ende gemerkt, damit er beim Start sofort da ist.
struct SpecialLook: Codable, Equatable {
    var symbol: String?      // SF Symbol, das über die App schwebt
    var colors: [String]?    // Farben dafür (#rrggbb)
    var accent: String?      // ersetzt die Akzentfarbe
    var count: Int?          // wie viele gleichzeitig
    var burst: String?       // Symbol für den kleinen Ausbruch bei Play und Liken
    var rain: Bool?          // beim Öffnen einmal viele auf einmal
}

struct SpecialResponse: Codable {
    var id: String?
    var end: Double?
    var app: SpecialLook?
}

@MainActor
final class SpecialTheme: ObservableObject {
    static let shared = SpecialTheme()

    @Published private(set) var id = ""
    @Published private(set) var look = SpecialLook()
    @Published private(set) var bursts: [Date] = []
    /// Wann der Regen beim Öffnen begann (einmal je Sonderdesign und App-Start).
    private(set) var rainStart: Date?
    private var rainFor = ""
    private var end: Double = 0
    private var loop: Task<Void, Never>?
    private let key = "specialTheme"

    var active: Bool { !id.isEmpty }

    private init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let r = try? JSONDecoder().decode(SpecialResponse.self, from: d) { apply(r) }
    }

    /// Beim Start, alle 5 Minuten und pünktlich zum Ende nachfragen.
    func start(api: APIClient) {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(api)
                let wait = self?.nextWait() ?? 300
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    func refresh(_ api: APIClient) async {
        if active, Date().timeIntervalSince1970 >= end { apply(nil) }
        guard let r = await api.special() else { return }   // Netzfehler: Stand behalten
        apply(r)
    }

    private func nextWait() -> Double {
        guard active else { return 300 }
        return min(300, max(1, end - Date().timeIntervalSince1970 + 0.5))
    }

    private func apply(_ r: SpecialResponse?) {
        guard let r, let rid = r.id, !rid.isEmpty, let e = r.end, e > Date().timeIntervalSince1970 else {
            Theme.accentOverride = nil
            if active { look = SpecialLook(); id = "" }
            end = 0
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        end = e
        let l = r.app ?? SpecialLook()
        // Erst die Farbe, dann die ID: Die ID baut die Oberfläche neu auf (siehe ContentView).
        Theme.accentOverride = l.accent.flatMap { Color(hexString: $0) }
        if look != l { look = l }
        if id != rid { id = rid }
        if let d = try? JSONEncoder().encode(r) { UserDefaults.standard.set(d, forKey: key) }
    }

    /// Einmal je Sonderdesign: der Regen beim Öffnen.
    func takeRain() -> Date? {
        guard active, look.rain == true else { return nil }
        if rainFor != id { rainFor = id; rainStart = Date() }
        return rainStart
    }

    /// Kleiner Ausbruch von Symbolen (Play, Liken). Ohne Sonderdesign passiert nichts.
    func celebrate() {
        guard active, look.burst != nil else { return }
        let now = Date()
        bursts = bursts.filter { now.timeIntervalSince($0) < 1.5 } + [now]
    }
}

/// Die schwebenden Symbole. Fängt keine Berührungen ab und ist für VoiceOver unsichtbar.
struct SpecialLayer: View {
    var density: Double = 1
    var rain = false
    @ObservedObject private var special = SpecialTheme.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rainStart: Date?

    var body: some View {
        if special.active, let symbol = special.look.symbol {
            let palette = (special.look.colors ?? []).compactMap { Color(hexString: $0) }
            let colors = palette.isEmpty ? [Theme.accent] : palette
            let burstSymbol = special.look.burst ?? symbol
            let scene = Setup(count: max(4, Int(Double(special.look.count ?? 14) * density)), colors: colors.count,
                              still: reduceMotion, rainStart: rainStart, bursts: special.bursts)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tl in
                Canvas { ctx, size in
                    Self.draw(&ctx, size: size, now: tl.date, scene: scene)
                } symbols: {
                    // EINE Liste, deren IDs den Tags gleichen: Zwei ForEach mit denselben IDs
                    // (0, 1, 2 …) bringen CanvasSymbols zum Absturz (Simulator, 08.11.2026).
                    ForEach(symbolTags(colors.count), id: \.self) { tag in
                        Image(systemName: tag < 100 ? symbol : burstSymbol)
                            .font(.system(size: 40))
                            .foregroundStyle(colors[tag % 100])
                            .tag(tag)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { if rain && !reduceMotion { rainStart = special.takeRain() } }
        }
    }

    /// Tags 0… für die schwebenden Symbole, 100… für den Ausbruch, je eins pro Farbe.
    private func symbolTags(_ n: Int) -> [Int] { Array(0..<n) + Array(100..<(100 + n)) }

    struct Setup {
        let count: Int
        let colors: Int
        let still: Bool
        let rainStart: Date?
        let bursts: [Date]
    }

    /// Gleichmäßig verteilte Zufallszahl 0..<1, fest je Teilchen i und Eigenschaft k.
    nonisolated private static func rnd(_ i: Int, _ k: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: i &* 73_856_093 ^ k &* 19_349_663) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 10_000) / 10_000
    }

    nonisolated private static func put(_ ctx: inout GraphicsContext, _ tag: Int, x: Double, y: Double, size: Double, angle: Double, alpha: Double) {
        guard alpha > 0.01, let img = ctx.resolveSymbol(id: tag) else { return }
        var c = ctx
        c.opacity = alpha
        c.translateBy(x: x, y: y)
        c.rotate(by: .radians(angle))
        c.scaleBy(x: size / 40, y: size / 40)
        c.draw(img, at: .zero)
    }

    nonisolated private static func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Date, scene: Setup) {
        let w = size.width, h = size.height
        let t = scene.still ? 0 : now.timeIntervalSinceReferenceDate
        let n = scene.count, colors = scene.colors
        // Schweben: langsam nach oben, leicht hin und her
        for i in 0..<n {
            let s = 10 + rnd(i, 1) * 16
            let v = 14 + rnd(i, 2) * 22
            let phase = rnd(i, 3) * 6.283
            let span = h + 80
            let y = h + 40 - (t * v + rnd(i, 7) * span).truncatingRemainder(dividingBy: span)
            let x = rnd(i, 5) * w + sin(t * 0.6 + phase) * (8 + rnd(i, 4) * 24)
            put(&ctx, i % colors, x: x, y: y, size: s, angle: sin(t + phase) * 0.15, alpha: 0.3 + rnd(i, 6) * 0.25)
        }
        // Regen beim Öffnen
        if let r = scene.rainStart {
            let age = now.timeIntervalSince(r)
            if age < 6 {
                for i in 0..<(n * 3) {
                    let life = 3.2 + rnd(i, 11) * 2.3
                    guard age < life else { continue }
                    // Start ab dem unteren Drittel, damit sofort etwas zu sehen ist
                    let y = h * 0.7 + rnd(i, 12) * h * 0.8 - (140 + rnd(i, 13) * 140) * age
                    let x = rnd(i, 14) * w + (rnd(i, 15) - 0.5) * 40 * age
                    put(&ctx, i % colors, x: x, y: y, size: 12 + rnd(i, 16) * 18,
                        angle: (rnd(i, 17) - 0.5) * 0.8 + age * (rnd(i, 18) - 0.5), alpha: min(1, (1 - age / life) * 1.6) * 0.9)
                }
            }
        }
        // Kleine Ausbrüche bei Play und Liken, von unten Mitte
        for (b, start) in scene.bursts.enumerated() {
            let age = now.timeIntervalSince(start)
            guard age >= 0, age < 1.2 else { continue }
            for i in 0..<9 {
                let k = b * 31 + i
                let a = -Double.pi / 2 + (Double(i) / 8 - 0.5) * 2.2 + (rnd(k, 21) - 0.5) * 0.3
                let sp = 160 + rnd(k, 22) * 140
                let x = w / 2 + cos(a) * sp * age
                let y = h * 0.8 + sin(a) * sp * age + 200 * age * age
                put(&ctx, 100 + i % colors, x: x, y: y, size: 12 + rnd(k, 23) * 10,
                    angle: (rnd(k, 24) - 0.5) * age * 4, alpha: min(1, (1 - age / 1.2) * 1.8))
            }
        }
    }
}
