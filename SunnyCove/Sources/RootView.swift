import SwiftUI

struct RootView: View {
    @EnvironmentObject private var game: GameStore
    @AppStorage("sunnycove.hasStarted") private var hasStarted = false

    var body: some View {
        ZStack {
            if hasStarted {
                GameView()
            } else {
                SunnyCoveTitleScreen { hasStarted = true }
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct SunnyCoveTitleScreen: View {
    let start: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GameAssetImage(path: "appstore/splash_portrait.svg", contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [.clear, .clear, Color(red: 0.08, green: 0.34, blue: 0.48).opacity(0.42)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    Button(action: start) {
                        Text("SPIELEN")
                            .font(.system(size: 25, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .background(
                                LinearGradient(colors: [Color(hex: 0x68D84E), Color(hex: 0x28A94B)],
                                               startPoint: .top, endPoint: .bottom),
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(.white, lineWidth: 4))
                            .shadow(color: Color(hex: 0x176D45).opacity(0.8), radius: 0, y: 6)
                    }
                    .buttonStyle(CovePressButtonStyle())
                    .padding(.horizontal, 48)
                    .padding(.bottom, max(36, proxy.safeAreaInsets.bottom + 18))
                }
            }
        }
    }
}

struct GameView: View {
    @EnvironmentObject private var game: GameStore

    var body: some View {
        ZStack {
            SunnyCoveBackground()

            VStack(spacing: 7) {
                GameHUD()
                    .frame(height: 68)

                if let order = game.activeOrder {
                    OrderStrip(order: order)
                        .frame(height: 106)
                } else {
                    CampaignCompleteStrip()
                        .frame(height: 92)
                }

                GameBoardView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                SelectedItemStrip()
                    .frame(height: 55)

                GameNavigationBar()
                    .frame(height: 65)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 3)

            if let tutorial = game.activeTutorial {
                TutorialCoachmark(step: tutorial)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 76)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .zIndex(4)
            }

            if let level = game.levelUpNotice {
                LevelUpOverlay(level: level)
                    .zIndex(5)
            }

            if let message = game.message {
                GameToast(message: message)
                    .padding(.top, 72)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(6)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: game.tutorialStep)
        .animation(.spring(response: 0.3, dampingFraction: 0.76), value: game.levelUpNotice)
        .animation(.easeInOut(duration: 0.2), value: game.message)
        .onChange(of: game.message) { _, newValue in
            guard let newValue else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.2))
                if game.message == newValue { game.message = nil }
            }
        }
        .sheet(isPresented: $game.showRestoration) { RestorationView() }
        .sheet(isPresented: $game.showSettings) { SettingsView() }
    }
}

private struct SunnyCoveBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x73D9F5), Color(hex: 0xC8F3F6), Color(hex: 0xFFE9A0)],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(Color(hex: 0xFFE36E).opacity(0.85))
                .frame(width: 170, height: 170)
                .blur(radius: 1)
                .offset(x: 145, y: -345)
            WaveShape()
                .fill(Color.white.opacity(0.34))
                .frame(height: 130)
                .offset(y: 130)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
    }
}

private struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.45))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.35),
            control1: CGPoint(x: rect.width * 0.28, y: 0),
            control2: CGPoint(x: rect.width * 0.68, y: rect.height * 0.8)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct CovePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}
