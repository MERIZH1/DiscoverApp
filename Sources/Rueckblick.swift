import SwiftUI

// MARK: - Jahresrückblick „Dein Jahr“ (Server: GET /api/rueckblick, Server-Wiki `statistik` Abschnitt 4)
// Sichtbar 01.12.–31.01. (das entscheidet der Server über `aktiv`). Karte auf der Startseite unter dem
// Schnellzugriff, Tipp öffnet die Übersicht, ▶ spielt die Playlist „Dein <Jahr>“ (jahr:<Jahr>).

struct Rueckblick: Decodable, Equatable {
    struct Song: Decodable, Equatable {
        let uri: String
        let name: String
        let artist: String
        let image: String?
        let minuten: Int
    }
    struct Kuenstler: Decodable, Equatable {
        let name: String
        let minuten: Int
        let image: String?
    }
    struct Monat: Decodable, Equatable, Identifiable {
        var id: String { monat }
        let monat: String
        let name: String
        let minuten: Int
        let top_kuenstler: String?
        let uri: String?
    }
    let jahr: Int
    let protokoll_ab: String?
    let seit: String?
    let minuten: Int
    let songs: Int
    let kuenstler: Int
    let genug: Bool
    let aktiv: Bool?
    let top_songs: [Song]
    let top_kuenstler: [Kuenstler]
    let monate: [Monat]
    let playlist: String

    var zeigen: Bool { (aktiv ?? false) && genug }
    var jahrText: String { String(jahr) }      // ohne Tausenderpunkt („2.026“)
}

enum RB {
    static let gold = Color(hex6: 0xE8A33D)
    /// „22 Stunden“ bzw. „45 Min.“ als (Zahl, Einheit)
    static func zeit(_ min: Int) -> (String, String) {
        if min >= 60 {
            let h = Int((Double(min) / 60).rounded())
            return (String(h), h == 1 ? "Stunde" : "Stunden")
        }
        return (String(min), "Min.")
    }
    static func kurz(_ min: Int) -> String {
        min >= 60 ? "\(Int((Double(min) / 60).rounded())) Std." : "\(min) Min."
    }
}

/// Goldene Karte auf der Startseite.
struct RueckblickKarte: View {
    let d: Rueckblick
    let oeffnen: () -> Void
    let abspielen: () -> Void

    private var bild: String? {
        d.top_songs.first?.image.flatMap { $0.isEmpty ? nil : $0 } ?? d.top_kuenstler.first?.image
    }
    private var unterzeile: String {
        var s = "\(d.songs) Songs"
        if let k = d.top_kuenstler.first { s += " · am meisten: \(k.name)" }
        if let seit = d.seit, !seit.isEmpty { s += " · Daten seit \(seit.prefix(6))" }
        return s
    }

    var body: some View {
        Button(action: oeffnen) {
            HStack(spacing: 14) {
                Artwork(url: bild, size: 92, corner: 10)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEIN JAHR \(d.jahrText)").font(.system(size: 11, weight: .bold)).tracking(1)
                        .foregroundStyle(RB.gold)
                    let z = RB.zeit(d.minuten)
                    Text("\(z.0) \(z.1) Musik").font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.55)
                    Text(unterzeile).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Color.clear.frame(width: 50, height: 50)   // Platz für den Play-Knopf
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [RB.gold.opacity(0.30), RB.gold.opacity(0.08)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("home.rueckblick")
        .overlay(alignment: .trailing) {
            Button(action: abspielen) {
                Image(systemName: "play.fill").font(.system(size: 19, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 50, height: 50)
                    .background(RB.gold, in: Circle())
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.pressable)
            .padding(.trailing, 14)
            .accessibilityLabel("Dein \(d.jahrText) abspielen")
            .accessibilityIdentifier("home.rueckblick.play")
        }
    }
}

/// Übersicht: Zahlen, Top-Songs, Top-Künstler*innen, Monat für Monat.
struct RueckblickSheet: View {
    let d: Rueckblick
    let oeffne: (_ uri: String, _ name: String) -> Void
    let abspielen: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dein \(d.jahrText)").font(.system(size: 28, weight: .heavy)).foregroundStyle(Theme.text)
                    .padding(.top, 8)
                Text("Discover zeichnet erst seit \(d.protokoll_ab ?? "20.08.2026") auf, alles davor fehlt hier. Gezählt wird die wirklich gehörte Zeit.")
                    .font(.system(size: 13)).foregroundStyle(Theme.sub)
                HStack(spacing: 10) {
                    let z = RB.zeit(d.minuten)
                    zahl(z.0, z.1)
                    zahl("\(d.songs)", "Songs")
                    zahl("\(d.kuenstler)", "Künstler*innen")
                }.padding(.vertical, 4)

                if !d.top_songs.isEmpty {
                    ueberschrift("Deine Top-Songs")
                    ForEach(Array(d.top_songs.enumerated()), id: \.offset) { i, s in
                        Button { oeffne(d.playlist, "Dein \(d.jahrText)") } label: {
                            zeile(i + 1, s.image, rund: false, s.name, s.artist, RB.kurz(s.minuten))
                        }.buttonStyle(.pressable)
                    }
                }
                if !d.top_kuenstler.isEmpty {
                    ueberschrift("Deine Top-Künstler*innen")
                    ForEach(Array(d.top_kuenstler.enumerated()), id: \.offset) { i, k in
                        zeile(i + 1, k.image, rund: true, k.name, nil, RB.kurz(k.minuten))
                    }
                }
                if !d.monate.isEmpty {
                    ueberschrift("Monat für Monat")
                    let maxMin = max(1, d.monate.map(\.minuten).max() ?? 1)
                    ForEach(d.monate) { m in
                        if let u = m.uri, !u.isEmpty {
                            Button { oeffne(u, "Dein \(m.name) \(d.jahrText)") } label: { monat(m, maxMin) }
                                .buttonStyle(.pressable)
                        } else {
                            monat(m, maxMin)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button(action: abspielen) {
                        Label("Dein \(d.jahrText) abspielen", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(RB.gold, in: Capsule())
                    }.buttonStyle(.pressable)
                    Button { oeffne(d.playlist, "Dein \(d.jahrText)") } label: {
                        Text("Playlist öffnen").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    }.buttonStyle(.pressable)
                }.padding(.top, 14)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .background(Theme.elev.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("rueckblick.sheet")
    }

    private func zahl(_ wert: String, _ einheit: String) -> some View {
        VStack(spacing: 2) {
            Text(wert).font(.system(size: 28, weight: .heavy)).foregroundStyle(RB.gold).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(einheit).font(.system(size: 12)).foregroundStyle(Theme.sub).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func ueberschrift(_ t: String) -> some View {
        Text(t).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text).padding(.top, 10)
    }

    private func zeile(_ nr: Int, _ bild: String?, rund: Bool, _ titel: String, _ unter: String?, _ wert: String) -> some View {
        HStack(spacing: 10) {
            Text("\(nr)").font(.system(size: 13)).foregroundStyle(Theme.sub).monospacedDigit()
                .frame(width: 20, alignment: .trailing)
            Artwork(url: bild, size: 44, corner: rund ? 22 : 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(titel).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                if let u = unter, !u.isEmpty {
                    Text(u).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(wert).font(.system(size: 13)).foregroundStyle(Theme.sub).monospacedDigit()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func monat(_ m: Rueckblick.Monat, _ maxMin: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(m.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    .frame(width: 96, alignment: .leading)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(RB.gold)
                            .frame(width: max(6, g.size.width * CGFloat(m.minuten) / CGFloat(maxMin)))
                    }
                }.frame(height: 8)
                Text(RB.kurz(m.minuten)).font(.system(size: 13)).foregroundStyle(Theme.sub).monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
            }
            if let k = m.top_kuenstler, !k.isEmpty {
                Text(k).font(.system(size: 12)).foregroundStyle(Theme.sub).lineLimit(1).padding(.leading, 106)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}
