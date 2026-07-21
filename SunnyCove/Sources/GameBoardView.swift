import SwiftUI

struct GameBoardView: View {
    @EnvironmentObject private var game: GameStore
    private let columns = 7
    private let rows = 9
    private let spacing: CGFloat = 2.5
    private let inset: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(1, proxy.size.width - inset * 2)
            let availableHeight = max(1, proxy.size.height - inset * 2)
            let boardWidth = min(availableWidth, availableHeight * CGFloat(columns) / CGFloat(rows))
            let cellSize = (boardWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let boardHeight = cellSize * CGFloat(rows) + spacing * CGFloat(rows - 1)
            let gridColumns = Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: columns)

            LazyVGrid(columns: gridColumns, spacing: spacing) {
                ForEach(game.cells) { cell in
                    GameBoardCell(cell: cell)
                        .frame(width: cellSize, height: cellSize)
                }
            }
            .frame(width: boardWidth, height: boardHeight)
            .padding(inset)
            .background(
                LinearGradient(colors: [Color(hex: 0x24A8C7), Color(hex: 0x137B9C)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.8), lineWidth: 3))
            .shadow(color: Color(hex: 0x07566D).opacity(0.42), radius: 0, y: 5)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: game.cells)
    }
}

private struct GameBoardCell: View {
    @EnvironmentObject private var game: GameStore
    let cell: BoardCell
    @State private var pulse = false

    private var isTutorialTarget: Bool { game.isTutorialTarget(cell) }
    private var isSelected: Bool { game.selectedCellID == cell.id }

    var body: some View {
        interactiveCell
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .onTapGesture { game.tapCell(cell.id) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .onAppear { updatePulse(isTutorialTarget) }
            .onChange(of: isTutorialTarget) { _, focused in updatePulse(focused) }
    }

    @ViewBuilder
    private var interactiveCell: some View {
        let target = cellBody.dropDestination(for: String.self) { values, _ in
            guard let raw = values.first,
                  let sourceID = Int(raw), sourceID != cell.id else { return false }
            game.moveOrMerge(from: sourceID, to: cell.id)
            return true
        }

        if cell.state == .item {
            target.draggable(String(cell.id)) {
                cellBody.frame(width: 58, height: 58)
            }
        } else {
            target
        }
    }

    private var cellBody: some View {
        ZStack {
            GameAssetImage(path: tileAsset, fallbackSystemName: "square.fill")

            switch cell.state {
            case .item:
                if let item = game.item(for: cell) {
                    GameAssetImage(path: item.asset, fallbackSystemName: "shippingbox.fill")
                        .padding(1)
                        .transition(.scale.combined(with: .opacity))
                }
            case .generator:
                generatorContent
            case .locked:
                lockedContent
            case .sand:
                sandCost
            case .cobweb:
                cobwebCost
            case .empty:
                EmptyView()
            }

            if cell.bubble {
                GameAssetImage(path: "board/bubble_item.svg", fallbackSystemName: "circle")
                    .padding(1)
                    .allowsHitTesting(false)
            }

            if isSelected {
                GameAssetImage(path: "board/tile_selected.svg", fallbackSystemName: "square.dashed")
                    .allowsHitTesting(false)
            }

            if isTutorialTarget {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: 0xFFE550), lineWidth: pulse ? 5 : 2)
                    .shadow(color: Color(hex: 0xFFE550), radius: pulse ? 8 : 2)
                    .scaleEffect(pulse ? 1.05 : 0.96)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var generatorContent: some View {
        if let definition = game.generator(for: cell), let generatorID = cell.generator {
            let runtime = game.generatorRuntime[generatorID]
            let locked = !game.canUseGenerator(generatorID)

            ZStack(alignment: .bottomTrailing) {
                GameAssetImage(
                    path: runtime?.upgraded == true ? definition.assetUpgraded : definition.assetReady,
                    fallbackSystemName: "shippingbox.fill"
                )
                .padding(1)
                .saturation(locked ? 0.15 : 1)
                .opacity(locked ? 0.5 : 1)

                if locked {
                    VStack(spacing: 0) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .black))
                        Text("LV \(game.generatorUnlockLevel(generatorID))")
                            .font(.system(size: 7, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color(hex: 0x4A5866).opacity(0.9), in: RoundedRectangle(cornerRadius: 7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("\(runtime?.charges ?? 0)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 19, minHeight: 19)
                        .background((runtime?.charges ?? 0) > 0 ? Color(hex: 0x1688B8) : Color(hex: 0x7B8790), in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .padding(2)
                }
            }
        }
    }

    private var lockedContent: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .black))
            Text("LV \(cell.unlockLevel ?? 1)")
                .font(.system(size: 7, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.92))
    }

    private var sandCost: some View {
        Text("\(game.catalog.rules.sandCoinsPerLayer)")
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(hex: 0xB77931).opacity(0.9), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(3)
    }

    private var cobwebCost: some View {
        Text("\(game.catalog.rules.cobwebCoins)")
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(hex: 0x4A5866).opacity(0.9), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(3)
    }

    private var tileAsset: String {
        switch cell.state {
        case .locked: return "board/tile_locked.svg"
        case .sand: return "board/tile_sand_\(cell.sandLevel ?? 1).svg"
        case .cobweb: return "board/tile_cobweb.svg"
        default: return "board/tile_empty.svg"
        }
    }

    private var accessibilityText: String {
        if let item = game.item(for: cell) { return "\(item.displayName), Stufe \(item.stage)" }
        if let generator = game.generator(for: cell) {
            return game.canUseGenerator(generator.id)
                ? "\(generator.displayName), Generator"
                : "\(generator.displayName), ab Level \(game.generatorUnlockLevel(generator.id))"
        }
        switch cell.state {
        case .empty: return "Leeres Feld"
        case .locked: return "Gesperrtes Feld, ab Level \(cell.unlockLevel ?? 1)"
        case .sand: return "Sand, Freiräumen kostet \(game.catalog.rules.sandCoinsPerLayer) Münzen"
        case .cobweb: return "Spinnweben, Entfernen kostet \(game.catalog.rules.cobwebCoins) Münzen"
        default: return cell.state.rawValue
        }
    }

    private func updatePulse(_ focused: Bool) {
        guard focused else { pulse = false; return }
        pulse = false
        withAnimation(.easeInOut(duration: 0.78).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}
