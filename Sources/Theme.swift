import SwiftUI

/// Farben aus der PWA (Spotify-Style).
enum Theme {
    static let bg     = Color.black
    static let elev   = Color(hex6: 0x121212)
    static let card   = Color(hex6: 0x1A1A1A)
    static let input  = Color(hex6: 0x2A2A2A)
    static let text   = Color.white
    static let sub    = Color(hex6: 0xB3B3B3)
    static let mute   = Color(hex6: 0x7A7A7A)
    static let accent = Color(hex6: 0x1ED760)
}

/// App-Version aus dem Bundle (fuer Server-/Account-Menue).
enum AppInfo {
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(v) (Build \(b))"
    }
}

extension Color {
    init(hex6: UInt) {
        self = Color(
            red:   Double((hex6 >> 16) & 0xFF) / 255,
            green: Double((hex6 >> 8) & 0xFF) / 255,
            blue:  Double(hex6 & 0xFF) / 255
        )
    }
}

// Schwarzer Hintergrund, der die Safe-Area fuellt.
struct DarkBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack { Theme.bg.ignoresSafeArea(); content }
    }
}
extension View {
    func darkBg() -> some View { modifier(DarkBackground()) }
}
