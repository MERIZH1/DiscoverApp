import SwiftUI

struct RestorationView: View {
    @EnvironmentObject private var game: GameStore
    @Environment(\.dismiss) private var dismiss
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x72D9F5), Color(hex: 0xFFF0B0)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    restorationScene
                    progressPanel
                    elementsGrid
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MARINAS STRANDBAR")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: Color(hex: 0x146680), radius: 0, y: 2)
                Text("Baue Sunny Cove Stück für Stück wieder auf")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x255D66))
            }
            Spacer()
            Button { dismiss() } label: {
                GameAssetImage(path: "ui/btn_close_normal.svg", fallbackSystemName: "xmark.circle.fill")
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(CovePressButtonStyle())
            .accessibilityLabel("Schließen")
        }
        .padding(.top, 12)
    }

    private var restorationScene: some View {
        ZStack(alignment: .bottom) {
            GameAssetImage(path: restorationAsset, fallbackSystemName: "building.2.fill", contentMode: .fill)
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .clipped()

            Text(restorationText)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 15)
                .frame(minHeight: 42)
                .frame(maxWidth: .infinity)
                .background(Color(hex: 0x0D607A).opacity(0.84))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white, lineWidth: 3))
        .shadow(color: Color(hex: 0x155C71).opacity(0.35), radius: 0, y: 5)
    }

    private var progressPanel: some View {
        VStack(spacing: 7) {
            HStack {
                Text("WIEDERAUFBAU")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0x79502B))
                Spacer()
                Text("\(game.placedElements.count)/\(game.catalog.restorationElements.count)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0x238F4A))
            }
            ProgressView(value: Double(game.placedElements.count), total: Double(max(1, game.catalog.restorationElements.count)))
                .tint(Color(hex: 0x37B954))
                .scaleEffect(x: 1, y: 1.7)
        }
        .padding(13)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white, lineWidth: 2))
    }

    private var elementsGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(game.catalog.restorationElements.sorted { $0.order < $1.order }) { element in
                let unlocked = game.placedElements.contains(element.id)
                VStack(spacing: 5) {
                    ZStack {
                        GameAssetImage(path: element.asset, fallbackSystemName: "sparkles")
                            .saturation(unlocked ? 1 : 0)
                            .opacity(unlocked ? 1 : 0.22)
                            .frame(height: 62)
                        if !unlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 23, weight: .black))
                                .foregroundStyle(Color(hex: 0x65757C))
                        }
                    }
                    Text(unlocked ? element.displayName : unlockLabel(element))
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(unlocked ? Color(hex: 0x6F4A2C) : Color(hex: 0x68767A))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(height: 24)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.white.opacity(unlocked ? 0.94 : 0.68), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(unlocked ? Color(hex: 0xFFD45F) : .white, lineWidth: 2))
            }
        }
    }

    private func unlockLabel(_ element: RestorationElementDefinition) -> String {
        let number = Int(element.unlockOrder.replacingOccurrences(of: "order_", with: "")) ?? 0
        return "Ab Auftrag \(number)"
    }

    private var restorationText: String {
        switch game.restorationState {
        case "partial": return "Die ersten Reparaturen sind geschafft – die Strandbar nimmt wieder Gestalt an."
        case "restored": return "Geschafft! Marinas Strandbar ist wieder das Herz von Sunny Cove."
        default: return "Der Sturm hat deutliche Spuren hinterlassen. Erfülle Aufträge für neue Bauteile."
        }
    }

    private var restorationAsset: String {
        switch game.restorationState {
        case "partial": return "restoration/beachbar_partial.svg"
        case "restored": return "restoration/beachbar_restored.svg"
        default: return "restoration/beachbar_damaged.svg"
        }
    }
}
