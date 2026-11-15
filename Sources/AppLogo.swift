import SwiftUI
import UIKit

/// App-Logo je Profil. Dieselbe Auswahl wie in der PWA und im Programm für Windows
/// (Profil bearbeiten → „App-Logo“), gespeichert als `app_logo` in `/api/me/settings`.
/// Katalog wie `static/logos/logos.json` auf dem Server. „f“ (Regenbogen) ist das Hauptsymbol
/// der App, die anderen sind alternative Symbole (`AppIcon-<id>` im Asset-Katalog).
enum AppLogo {
    static let defaultID = "f"
    static let storeKey = "appLogo"
    static let all: [(id: String, name: String)] = [
        ("f", "Regenbogen"), ("g", "Regenbogen-Verlauf"), ("h", "Pastell dunkel"), ("i", "Pastell hell"),
        ("j4", "Blau-Rosa"), ("j1", "Rosa und Blau"), ("j2", "Rosa-Blau-Verlauf"), ("j3", "Rosa-Blau je Strich"),
        ("a", "Grün"), ("b", "Weiß"), ("c", "Schwarz auf Grün"), ("d", "Cyan-Violett"), ("e", "Sonnenuntergang"),
    ]

    static func valid(_ id: String) -> Bool { all.contains { $0.id == id } }

    /// Zuletzt gewähltes Logo (für Ladebild und Auswahl, auch ohne Netz).
    static var current: String {
        let id = UserDefaults.standard.string(forKey: storeKey) ?? defaultID
        return valid(id) ? id : defaultID
    }

    /// Bild für die Anzeige in der App (Ladebild, Auswahl).
    static func imageName(_ id: String) -> String { "Logo-\(valid(id) ? id : defaultID)" }

    /// Symbol auf dem Home-Bildschirm setzen. iOS zeigt beim Wechsel selbst einen kurzen Hinweis,
    /// darum nur, wenn sich wirklich etwas ändert.
    @MainActor
    static func apply(_ id: String) {
        guard valid(id) else { return }
        UserDefaults.standard.set(id, forKey: storeKey)
        let want: String? = id == defaultID ? nil : "AppIcon-\(id)"
        let ui = UIApplication.shared
        guard ui.supportsAlternateIcons, ui.alternateIconName != want else { return }
        ui.setAlternateIconName(want) { err in
            if let err { print("[logo] Symbol nicht gesetzt: \(err.localizedDescription)") }
        }
    }
}

/// Auswahl des App-Logos in den Einstellungen.
struct AppLogoPicker: View {
    @Binding var selected: String
    let pick: (String) -> Void
    private let cols = [GridItem(.adaptive(minimum: 56), spacing: 12)]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App-Logo").font(.system(size: 15)).foregroundStyle(Theme.text)
            Text("Symbol auf dem Home-Bildschirm. Gilt für dein Profil, auch am PC.")
                .font(.caption2).foregroundStyle(Theme.mute)
            LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
                ForEach(AppLogo.all, id: \.id) { logo in
                    let on = logo.id == selected
                    // Logo ohne Hintergrund auf dezenter Fläche (wie im Web); das Home-Symbol selbst hat den Grund
                    Image(AppLogo.imageName(logo.id))
                        .resizable().scaledToFit()
                        .padding(9)
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(on ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(on ? Theme.accent : .clear, lineWidth: 2.5).padding(-4))
                        .contentShape(Rectangle())
                        .onTapGesture { Haptics.tap(); pick(logo.id) }
                        .accessibilityLabel(logo.name)
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier("logo-\(logo.id)")
                }
            }.padding(.top, 2)
        }
    }
}
