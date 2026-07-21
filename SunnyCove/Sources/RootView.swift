import SwiftUI
import UIKit
import WebKit

struct RootView: View {
    @EnvironmentObject private var game: GameStore
    @State private var started = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.42, green: 0.84, blue: 0.97), Color(red: 1, green: 0.91, blue: 0.62)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if started { GameView() } else { titleScreen }
        }
        .alert("Sunny Cove", isPresented: Binding(get: { game.message != nil }, set: { if !$0 { game.message = nil } })) {
            Button("OK") { game.message = nil }
        } message: { Text(game.message ?? "") }
    }

    private var titleScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            AssetImage(path: "appstore/logo_full.svg", fallback: "☀️")
                .frame(maxWidth: 280, maxHeight: 180)
            Text("Baue Marinas Strandparadies wieder auf").font(.headline).foregroundStyle(.blue.opacity(0.8))
            Spacer()
            Button { started = true } label: {
                Text("SPIELEN").font(.title2.bold()).frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent).tint(.green).padding(.horizontal, 44)
            Spacer().frame(height: 40)
        }
    }
}

struct GameView: View {
    @EnvironmentObject private var game: GameStore
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            hud
            if let tutorial = game.activeTutorial { TutorialCard(step: tutorial) }
            if let order = game.activeOrder { OrderCard(order: order) }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(game.cells) { cell in BoardCellView(cell: cell).onTapGesture { game.tapCell(cell.id) }
                }
                .padding(6).background(.blue.opacity(0.22), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 6)
            }
            HStack {
                if game.canUndo {
                    Button("Rückgängig") { game.undoLastAction() }
                        .buttonStyle(.bordered).tint(.purple)
                }
                if game.selectedCellID != nil {
                    Button("Verkaufen") { game.sellSelectedItem() }
                        .buttonStyle(.borderedProminent).tint(.red)
                }
                Button("Strandbar") { game.showRestoration = true }.buttonStyle(.borderedProminent).tint(.orange)
                Spacer()
                Button { game.showSettings = true } label: { Image(systemName: "gearshape.fill") }.buttonStyle(.bordered)
            }.padding(.horizontal)
        }
        .sheet(isPresented: $game.showRestoration) { RestorationView() }
        .sheet(isPresented: $game.showSettings) { SettingsView() }
    }

    private var hud: some View {
        HStack(spacing: 10) {
            Label("\(game.player.level)", systemImage: "star.fill")
            Spacer()
            Label("\(game.player.energy)", systemImage: "bolt.fill")
            Label("\(game.player.coins)", systemImage: "circle.fill")
            Label("\(game.player.gems)", systemImage: "diamond.fill")
        }
        .font(.subheadline.bold()).foregroundStyle(.white).padding(10)
        .background(.blue.opacity(0.72), in: Capsule()).padding(.horizontal, 8)
    }
}

struct TutorialCard: View {
    @EnvironmentObject private var game: GameStore
    let step: TutorialStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AssetImage(path: step.portrait, fallback: "🌴")
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(step.text).font(.caption).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Überspringen") { game.skipTutorial() }.font(.caption2)
                    Spacer()
                    Button("Weiter") { game.advanceTutorial() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 8)
    }
}

struct OrderCard: View {
    @EnvironmentObject private var game: GameStore
    let order: OrderDefinition

    var body: some View {
        HStack(spacing: 10) {
            AssetImage(path: order.portrait, fallback: characterEmoji)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(order.dialog).font(.caption).lineLimit(2)
                ForEach(order.requirements, id: \.self) { requirement in
                    let owned = game.cells.filter { $0.item == requirement.item }.count
                    Text("\(game.catalog.items[requirement.item]?.displayName ?? requirement.displayName): \(owned)/\(requirement.count)")
                        .font(.caption2.bold()).foregroundStyle(owned >= requirement.count ? .green : .primary)
                }
            }
            Spacer()
            Button("Abgeben") { game.completeActiveOrder() }.buttonStyle(.borderedProminent).tint(.green).disabled(!game.canComplete(order))
        }
        .padding(8).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 8)
    }

    private var characterEmoji: String { ["marina": "👩🏽‍🌾", "kai": "🏄🏽‍♂️", "shelly": "🐢", "gull": "🕊️"][order.character] ?? "🌴" }
}

struct BoardCellView: View {
    @EnvironmentObject private var game: GameStore
    let cell: BoardCell

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(background).overlay(RoundedRectangle(cornerRadius: 8).stroke(game.selectedCellID == cell.id ? .yellow : .white.opacity(0.45), lineWidth: game.selectedCellID == cell.id ? 4 : 1))
            content
            if cell.bubble { Circle().stroke(.cyan, lineWidth: 3).padding(3) }
        }
        .aspectRatio(1, contentMode: .fit).contentShape(Rectangle())
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        switch cell.state {
        case .empty: EmptyView()
        case .item:
            VStack(spacing: 0) {
                AssetImage(path: game.item(for: cell)?.asset ?? "", fallback: itemEmoji)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("\(game.item(for: cell)?.stage ?? 1)").font(.system(size: 8, weight: .bold))
            }
        case .generator:
            VStack(spacing: 0) {
                AssetImage(path: game.generator(for: cell)?.assetReady ?? "", fallback: generatorEmoji)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("\(game.generatorRuntime[cell.generator ?? ""]?.charges ?? 0)").font(.system(size: 9, weight: .black))
            }
        case .locked: Image(systemName: "lock.fill").foregroundStyle(.gray)
        case .sand: Text(String(repeating: "🏖️", count: min(2, cell.sandLevel ?? 1))).font(.caption)
        case .cobweb: Text("🕸️").font(.title2)
        }
    }

    private var background: Color { cell.state == .locked ? .gray.opacity(0.35) : .white.opacity(0.72) }
    private var itemEmoji: String {
        guard let item = game.item(for: cell) else { return "❔" }
        return ["chain_beach": "🐚", "chain_bar": "🍹", "chain_surf": "🏄", "chain_tool": "🧰", "chain_garden": "🌺"][item.chainID] ?? "✨"
    }
    private var generatorEmoji: String { ["gen1_beach_crate": "📦", "gen2_bar_cart": "🧃", "gen3_surf_locker": "🗄️", "gen4_tool_chest": "🧰", "gen5_garden_basket": "🧺"][cell.generator ?? ""] ?? "⚙️" }
    private var accessibilityText: String {
        if let item = game.item(for: cell) { return "\(item.displayName), Stufe \(item.stage)" }
        if let generator = game.generator(for: cell) { return generator.displayName }
        return cell.state.rawValue
    }
}

struct RestorationView: View {
    @EnvironmentObject private var game: GameStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            LinearGradient(colors: [.cyan.opacity(0.6), .yellow.opacity(0.5)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 24) {
                HStack { Text("Marinas Strandbar").font(.title.bold()); Spacer(); Button("Fertig") { dismiss() } }
                Spacer()
                AssetImage(path: restorationAsset, fallback: game.restorationState == "damaged" ? "🏚️" : game.restorationState == "partial" ? "🏗️" : "🏖️🍹")
                    .frame(maxWidth: 320, maxHeight: 240)
                Text(game.restorationState == "damaged" ? "Der Sturm hat deutliche Spuren hinterlassen." : game.restorationState == "partial" ? "Die Strandbar nimmt wieder Gestalt an." : "Sunny Cove strahlt wieder!").font(.headline).multilineTextAlignment(.center)
                Spacer()
            }.padding()
        }
    }

    private var restorationAsset: String {
        switch game.restorationState {
        case "partial": "restoration/beachbar_partial.svg"
        case "restored": "restoration/beachbar_restored.svg"
        default: "restoration/beachbar_damaged.svg"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var game: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @StateObject private var updates = ContentUpdateService()
    @AppStorage("sunnycove.musicEnabled") private var musicEnabled = true
    @AppStorage("sunnycove.soundEnabled") private var soundEnabled = true
    @AppStorage("sunnycove.hapticsEnabled") private var hapticsEnabled = true
    var body: some View {
        NavigationStack {
            Form {
                Section("Spiel") {
                    Toggle("Musik", isOn: $musicEnabled)
                    Toggle("Soundeffekte", isOn: $soundEnabled)
                    Toggle("Haptisches Feedback", isOn: $hapticsEnabled)
                }
                Section("Version") {
                    LabeledContent("App", value: "0.1.0 Beta")
                    LabeledContent("Inhalte", value: "2026.07.0")
                    Button("Nach neuen Inhalten suchen") {
                        Task { await updates.checkForUpdates() }
                    }
                    if case .available = updates.status {
                        Button("Neue Inhalte laden") {
                            Task { await updates.applyLatestIfAvailable() }
                        }
                    }
                    Text(updates.status.displayText).font(.caption).foregroundStyle(.secondary)
                }
                Section { Button("Spielstand zurücksetzen", role: .destructive) { confirmReset = true } }
            }
            .navigationTitle("Einstellungen").toolbar { Button("Fertig") { dismiss() } }
            .confirmationDialog("Wirklich neu beginnen?", isPresented: $confirmReset) { Button("Zurücksetzen", role: .destructive) { game.reset(); dismiss() } }
        }
    }
}

struct AssetImage: View {
    let path: String
    let fallback: String
    @State private var assetURL: URL?

    var body: some View {
        Group {
            if let assetURL {
                SVGWebView(url: assetURL)
            } else {
                Text(fallback).font(.system(size: 26))
            }
        }
        .task(id: path) { assetURL = AssetLocator.url(for: path) }
    }
}

private enum AssetLocator {
    static func url(for path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        if let current = ContentUpdateStorage.currentURL {
            let override = current.appendingPathComponent(normalized)
            if FileManager.default.fileExists(atPath: override.path) { return override }
        }
        let parts = normalized.split(separator: "/")
        guard let file = parts.last else { return nil }
        let folder = parts.dropLast().joined(separator: "/")
        let name = String(file).replacingOccurrences(of: ".svg", with: "")
        let locations = [
            Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "GameContent/\(folder)"),
            Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: folder),
            Bundle.main.url(forResource: name, withExtension: "svg")
        ]
        return locations.compactMap { $0 }.first
    }
}

private struct SVGWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard view.url != url else { return }
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}
