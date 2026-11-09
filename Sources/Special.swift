import SwiftUI
import AVFoundation
import AVKit
import UserNotifications

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

/// Große Karte oben auf der Startseite (z.B. eine Playlist für den Tag).
struct SpecialCard: Codable, Equatable {
    var title: String?
    var sub: String?
    var kicker: String?      // kleine Zeile über dem Titel
    var uri: String?
    var image: String?
}

/// Nachricht, die einmal beim Öffnen erscheint.
struct SpecialMessage: Codable, Equatable {
    var title: String?
    var text: String?
    var button: String?      // spielt `uri`
    var uri: String?
}

/// Sprachaufnahme, die einmal nach `after` Songwechseln läuft.
struct SpecialVoice: Codable, Equatable {
    var url: String?
    var after: Int?
    var label: String?
}

/// Einblendung ab Uhrzeit `at` (Unix-Zeit); Antippen spielt das Video.
struct SpecialNotice: Codable, Equatable {
    var at: Double?
    var title: String?
    var text: String?
    var video: String?
}

struct SpecialResponse: Codable {
    var id: String?
    var end: Double?
    var app: SpecialLook?
    var greeting: String?    // ersetzt die Begrüßung auf der Startseite
    var card: SpecialCard?
    var message: SpecialMessage?
    var voice: SpecialVoice?
    var notice: SpecialNotice?
}

/// Ein Ausbruch: wann und von wo (Bildschirm-Koordinaten). Ohne Ort: unten Mitte.
struct SpecialBurst: Equatable, Sendable {
    let start: Date
    let at: CGPoint?
}

@MainActor
final class SpecialTheme: ObservableObject {
    static let shared = SpecialTheme()

    @Published private(set) var id = ""
    @Published private(set) var look = SpecialLook()
    @Published private(set) var bursts: [SpecialBurst] = []
    @Published private(set) var card: SpecialCard?
    @Published private(set) var greeting: String?
    // Einmalige Dinge. Was schon gezeigt wurde, merkt sich der Server und zusätzlich das Gerät,
    // damit der gemerkte Stand es nach einem Neustart nicht noch einmal zeigt.
    @Published private(set) var message: SpecialMessage?
    @Published private(set) var notice: SpecialNotice?
    @Published private(set) var noticeDue = false       // Uhrzeit erreicht -> Einblendung zeigen
    @Published var videoOpen = false
    @Published private(set) var videoPath: String?      // Video, das gerade offen ist
    @Published private(set) var voiceLabel: String?     // solange die Sprachaufnahme läuft
    private var voice: VoiceState?
    private var voicePlayer: AVAudioPlayer?
    private var voiceDelegate: VoiceDelegate?
    private var voiceDone: (() -> Void)?
    private var noticeTask: Task<Void, Never>?
    private var api: APIClient?
    private let seenKey = "specialSeen"
    nonisolated static let noticeID = "special-notice"

    private struct VoiceState {
        var url: String
        var after: Int
        var label: String
        var count = 0
        var file: URL?
        var loading = false
    }
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
        self.api = api
        loadVoice()
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
            if card != nil { card = nil }
            if greeting != nil { greeting = nil }
            if message != nil { message = nil }
            if notice != nil { notice = nil; scheduleNotice() }
            if voicePlayer == nil { voice = nil }
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
        if card != r.card { card = r.card }
        let g = r.greeting.flatMap { $0.isEmpty ? nil : $0 }
        if greeting != g { greeting = g }
        if id != rid { id = rid }
        applyOnce(r)
        if let d = try? JSONEncoder().encode(r) { UserDefaults.standard.set(d, forKey: key) }
    }

    // MARK: Nachricht, Einblendung mit Video, Sprachaufnahme

    private func seenHere(_ what: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: seenKey) ?? []).contains("\(id):\(what)")
    }

    private func markSeen(_ what: String) {
        var a = UserDefaults.standard.stringArray(forKey: seenKey) ?? []
        let k = "\(id):\(what)"
        guard !a.contains(k) else { return }
        a.append(k)
        UserDefaults.standard.set(Array(a.suffix(30)), forKey: seenKey)
        let api = self.api
        Task { await api?.specialSeen(what) }
    }

    private func applyOnce(_ r: SpecialResponse) {
        // Eine offene Nachricht bleibt stehen, bis sie geschlossen wird (der Server meldet sie
        // nach dem Anzeigen nicht mehr)
        if message == nil, let m = r.message, m.text?.isEmpty == false, !seenHere("message") { message = m }
        let n = (r.notice?.at != nil && !seenHere("notice")) ? r.notice : nil
        if notice != n { notice = n; scheduleNotice() }
        if let v = r.voice, let u = v.url, !u.isEmpty, !seenHere("voice") {
            if voice?.url != u {
                voice = VoiceState(url: u, after: max(1, v.after ?? 2), label: v.label ?? "")
                loadVoice()
            }
        } else if voicePlayer == nil {
            voice = nil
        }
    }

    /// Nachricht ist zu sehen -> gilt als gezeigt (auch wenn die App gleich danach beendet wird).
    func messageAppeared() { markSeen("message") }
    func closeMessage() { message = nil }

    /// Wecker auf die Uhrzeit der Einblendung, dazu eine Mitteilung für den Fall, dass die App
    /// dann zu ist (die Erlaubnis fragt die App schon beim ersten Start).
    private func scheduleNotice() {
        noticeTask?.cancel()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.noticeID])
        guard let n = notice, let at = n.at else { noticeDue = false; return }
        let wait = at - Date().timeIntervalSince1970
        guard wait > 0 else { noticeDue = true; return }
        noticeDue = false
        let c = UNMutableNotificationContent()
        c.title = n.title ?? ""
        c.body = n.text ?? ""
        c.sound = .default
        center.add(UNNotificationRequest(identifier: Self.noticeID, content: c,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, wait), repeats: false)))
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.noticeDue = true
        }
    }

    /// Einblendung oder Mitteilung angetippt: Video im Vollbild.
    func openVideo() {
        guard let v = notice?.video, !v.isEmpty else { return }
        noticeDue = true
        videoPath = v
        videoOpen = true
    }

    /// Video lief bis zum Ende -> die Einblendung verschwindet und kommt nicht wieder.
    /// Wird es vorher geschlossen, bleibt sie stehen.
    func videoFinished() {
        markSeen("notice")
        notice = nil
        scheduleNotice()
    }

    func videoClosed() { videoPath = nil }

    private func loadVoice() {
        guard let v = voice, v.file == nil, !v.loading, let api, let u = api.absoluteURL(v.url) else { return }
        voice?.loading = true
        Task { [weak self] in
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("special-voice-" + u.lastPathComponent)
            if let (tmp, resp) = try? await URLSession.shared.download(from: u),
               (resp as? HTTPURLResponse)?.statusCode == 200 {
                try? FileManager.default.removeItem(at: file)
                try? FileManager.default.moveItem(at: tmp, to: file)
                if self?.voice?.url == v.url { self?.voice?.file = file }
            }
            self?.voice?.loading = false
        }
    }

    /// Beim Songwechsel (PlayerController.next): Ist jetzt die Sprachaufnahme dran, spielt sie
    /// und ruft danach `weiter`. true = der Songwechsel wartet so lange.
    func voiceGate(weiter: @escaping () -> Void) -> Bool {
        guard active, var v = voice, voicePlayer == nil else { return false }
        v.count += 1
        voice = v
        guard v.count >= v.after, let file = v.file, let p = try? AVAudioPlayer(contentsOf: file) else { return false }
        let d = VoiceDelegate { [weak self] in self?.finishVoice() }
        p.delegate = d
        guard p.play() else { return false }
        voicePlayer = p
        voiceDelegate = d
        voiceDone = weiter
        voiceLabel = v.label.isEmpty ? "Eine Nachricht für dich" : v.label
        return true
    }

    /// Aufnahme zu Ende oder „Weiter“ getippt: einmal gehört, weiter mit dem nächsten Song.
    func finishVoice() {
        guard let p = voicePlayer else { return }
        p.stop()
        voicePlayer = nil
        voiceDelegate = nil
        voiceLabel = nil
        voice = nil
        markSeen("voice")
        let w = voiceDone
        voiceDone = nil
        w?()
    }

    /// Einmal je Sonderdesign: der Regen beim Öffnen.
    func takeRain() -> Date? {
        guard active, look.rain == true else { return nil }
        if rainFor != id { rainFor = id; rainStart = Date() }
        return rainStart
    }

    /// Symbole sprühen aus dem gedrückten Knopf (Play, Liken). `at` ist dessen Mitte in
    /// Bildschirm-Koordinaten. Ohne Sonderdesign passiert nichts.
    func celebrate(at: CGPoint? = nil) {
        guard active, look.burst != nil else { return }
        let now = Date()
        bursts = bursts.filter { now.timeIntervalSince($0.start) < 1.6 } + [SpecialBurst(start: now, at: at)]
    }
}

/// Die schwebenden Symbole. Fängt keine Berührungen ab und ist für VoiceOver unsichtbar.
struct SpecialLayer: View {
    var density: Double = 1
    var rain = false
    var floating = true      // schwebende Symbole und Regen
    var sprays = true        // Ausbrüche aus Knöpfen
    @ObservedObject private var special = SpecialTheme.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rainStart: Date?
    @State private var origin: CGPoint = .zero   // eigene Lage auf dem Bildschirm

    var body: some View {
        if special.active, let symbol = special.look.symbol {
            let palette = (special.look.colors ?? []).compactMap { Color(hexString: $0) }
            let colors = palette.isEmpty ? [Theme.accent] : palette
            let burstSymbol = special.look.burst ?? symbol
            let scene = Setup(count: floating ? max(4, Int(Double(special.look.count ?? 14) * density)) : 0,
                              colors: colors.count, still: reduceMotion, rainStart: floating ? rainStart : nil,
                              bursts: sprays ? special.bursts : [], origin: origin)
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
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
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
        let bursts: [SpecialBurst]
        let origin: CGPoint
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
        // Ausbrüche: Symbole sprühen aus dem gedrückten Knopf, rundherum mit Zug nach oben,
        // dann fallen sie langsam und verblassen
        for (b, burst) in scene.bursts.enumerated() {
            let age = now.timeIntervalSince(burst.start)
            guard age >= 0, age < 1.5 else { continue }
            let cx = burst.at.map { $0.x - scene.origin.x } ?? w / 2
            let cy = burst.at.map { $0.y - scene.origin.y } ?? h * 0.8
            let count = burst.at == nil ? 10 : 20
            for i in 0..<count {
                let k = b * 53 + i
                let a = -Double.pi / 2 + (Double(i) / Double(count) - 0.5) * 2 * Double.pi * 0.92 + (rnd(k, 21) - 0.5) * 0.35
                let sp = 140 + rnd(k, 22) * 190
                let life = 1.0 + rnd(k, 25) * 0.5
                guard age < life else { continue }
                let x = cx + cos(a) * sp * age
                let y = cy + (sin(a) * sp - 90) * age + 260 * age * age
                let grow = min(1, age * 7)   // kommen klein aus dem Knopf und werden groß
                put(&ctx, 100 + i % colors, x: x, y: y, size: (10 + rnd(k, 23) * 14) * grow,
                    angle: (rnd(k, 24) - 0.5) * age * 5, alpha: min(1, (1 - age / life) * 2))
            }
        }
    }
}

/// Die Sonderkarte oben auf der Startseite: Antippen öffnet die Playlist, der Knopf spielt sie.
struct SpecialCardView: View {
    let card: SpecialCard
    let uri: String
    @EnvironmentObject var app: AppState
    @Environment(\.playerRef) private var playerRef
    @State private var playCenter: CGPoint?
    @State private var starting = false

    var body: some View {
        NavigationLink(value: HomeItem(uri: uri, name: card.title ?? "", image: card.image, sub: card.sub, type: "playlist")) {
            HStack(spacing: 14) {
                Artwork(url: card.image, size: 92, corner: 10)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 4) {
                    if let k = card.kicker, !k.isEmpty {
                        Text(k.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Text(card.title ?? "").font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.55)
                    if let s = card.sub, !s.isEmpty {
                        Text(s).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Color.clear.frame(width: 50, height: 50)   // Platz für den Play-Knopf
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.elev],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("home.specialCard")
        .overlay(alignment: .trailing) {
            Button { play() } label: {
                Image(systemName: "play.fill").font(.system(size: 19, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 50, height: 50)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.pressable)
            .onGeometryChange(for: CGPoint.self) { CGPoint(x: $0.frame(in: .global).midX, y: $0.frame(in: .global).midY) } action: { playCenter = $0 }
            .padding(.trailing, 14)
            .accessibilityLabel("Abspielen")
            .accessibilityIdentifier("home.specialCard.play")
        }
    }

    private func play() {
        guard !starting, let player = playerRef else { return }
        starting = true
        SpecialTheme.shared.celebrate(at: playCenter)
        Task {
            defer { starting = false }
            if let r = try? await app.api.playlistTracks(uri), !r.tracks.isEmpty {
                player.play(tracks: r.tracks, startAt: 0, contextName: card.title ?? r.name ?? "", contextURI: uri)
            }
        }
    }
}

private final class VoiceDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let onEnd: @MainActor @Sendable () -> Void
    init(_ onEnd: @escaping @MainActor @Sendable () -> Void) { self.onEnd = onEnd }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.onEnd() }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.onEnd() }
    }
}

/// Nachricht beim Öffnen: abgedunkelter Hintergrund, Karte mit Text und Knöpfen.
struct SpecialMessageView: View {
    let message: SpecialMessage
    let close: () -> Void
    let play: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 12) {
                if let t = message.title, !t.isEmpty {
                    Text(t).font(.system(size: 22, weight: .heavy))
                }
                // Kurzer Text so, langer Text scrollt
                ViewThatFits(in: .vertical) {
                    textView(message.text ?? "")
                    ScrollView { textView(message.text ?? "") }.frame(maxHeight: 380)
                }
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Button(action: close) {
                        Text("Schließen").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("special.message.close")
                    if let b = message.button, !b.isEmpty, message.uri?.isEmpty == false {
                        Button(action: play) {
                            Text(b).font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                                .padding(.horizontal, 18).padding(.vertical, 11)
                                .background(Theme.accent, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("special.message.play")
                    }
                }
                .padding(.top, 8)
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: 440)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .padding(20)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("special.message")
        }
    }

    private func textView(_ s: String) -> some View {
        Text(s).font(.system(size: 16)).foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Einblendung oben: Antippen spielt das Video.
struct SpecialNoticeBanner: View {
    let notice: SpecialNotice
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "play.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(Theme.accent, in: Circle())
                    .scaleEffect(pulse ? 1.08 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    if let t = notice.title, !t.isEmpty {
                        Text(t).font(.system(size: 16, weight: .heavy))
                    }
                    if let s = notice.text, !s.isEmpty {
                        Text(s).font(.system(size: 14)).foregroundStyle(.white.opacity(0.85)).lineLimit(3)
                    }
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Theme.accent.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 16)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityIdentifier("special.notice")
    }
}

/// Video im Vollbild. Läuft es bis zum Ende, ruft es `onEnd` und schließt sich.
struct SpecialVideoView: View {
    let onEnd: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL, onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player).ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .padding(.leading, 16).padding(.top, 8)
            .accessibilityLabel("Schließen")
            .accessibilityIdentifier("special.video.close")
        }
        .onAppear { player.play() }
        .onDisappear { player.pause() }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { n in
            guard (n.object as? AVPlayerItem) === player.currentItem else { return }
            onEnd()
            dismiss()
        }
        .accessibilityIdentifier("special.video")
    }
}
