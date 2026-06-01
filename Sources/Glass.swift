import SwiftUI

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
}
