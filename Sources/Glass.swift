import SwiftUI
import UIKit

// Helligkeit einer Farbe (fuer Kontrast: helles Hero-Cover -> dunkle Buttons).
extension Color {
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.62
    }
}

// MARK: - Liquid Glass (iOS 26) — app-weiter Schalter via Environment
//
// `glassEffect` existiert erst ab dem iOS-26-SDK (Xcode 26). Der CI-Build
// laeuft daher auf macos-26. Auf aelteren Geraeten (< iOS 26) faellt alles
// automatisch auf die solide Fallback-Farbe zurueck (#available-Check).

private struct LiquidGlassKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var liquidGlass: Bool {
        get { self[LiquidGlassKey.self] }
        set { self[LiquidGlassKey.self] = newValue }
    }
}

extension View {
    /// Flaeche mit Liquid Glass, wenn `on` und iOS 26 — sonst solide Farbe.
    @ViewBuilder
    func glassSurface(_ on: Bool, shape: some Shape, fallback: Color) -> some View {
        if on, #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }

    /// Interaktiver Button (Tint-Glas), wenn `on` und iOS 26 — sonst solide Farbe.
    @ViewBuilder
    func glassButton(_ on: Bool, shape: some Shape, fallback: Color) -> some View {
        if on, #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }

    /// Runder Icon-Button im iOS-26-Stil (Glas-Kreis), sonst nur das Icon.
    /// Fuer die kleinen Kopf-Icons im Player (Chevron/Mond/Geraet/⋯).
    func glassIconCircle(_ on: Bool, size: CGFloat = 36) -> some View {
        self.frame(width: size, height: size)
            .glassButton(on, shape: Circle(), fallback: .clear)
            .contentShape(Circle())
    }
}

/// Gruppiert mehrere benachbarte Glas-Elemente, damit sie auf iOS 26 fluessig
/// ineinander verschmelzen und beim Erscheinen/Verschwinden morphen (das eigentliche
/// „Liquid"-Verhalten) — statt als einzelne Glas-Blasen nebeneinander zu stehen.
/// Ohne Glas oder unter iOS 26 ist es nur ein transparenter Pass-Through.
struct GlassCluster<Content: View>: View {
    let on: Bool
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if on, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
