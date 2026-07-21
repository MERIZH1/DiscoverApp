import Foundation
import SwiftUI

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var player = PlayerState()
    @Published private(set) var cells: [BoardCell] = []
    @Published private(set) var generatorRuntime: [String: GeneratorRuntime] = [:]
    @Published private(set) var activeOrderIndex = 0
    @Published private(set) var completedOrderIDs: [String] = []
    @Published private(set) var restorationState = "damaged"
    @Published private(set) var tutorialStep = 0
    @Published var selectedCellID: Int?
    @Published var message: String?
    @Published var showRestoration = false
    @Published var showSettings = false
    @Published private(set) var canUndo = false

    let catalog: ContentCatalog
    private let saveURL: URL
    private var lastEnergyUpdate = Date()
    private var ticker: Timer?
    private var undoState: UndoState?

    private struct UndoState {
        let player: PlayerState
        let cells: [BoardCell]
        let generators: [String: GeneratorRuntime]
        let selectedCellID: Int?
        let createdAt: Date
    }

    var activeOrder: OrderDefinition? {
        guard catalog.orders.indices.contains(activeOrderIndex) else { return nil }
        return catalog.orders[activeOrderIndex]
    }

    init() {
        catalog = ContentCatalog.load()
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        saveURL = folder.appendingPathComponent("sunny-cove-save-v3.json")
        if !load() { reset() }
        applyOfflineProgress()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit { ticker?.invalidate() }

    func reset() {
        player = PlayerState(level: 1, xp: 0, energy: catalog.rules.energyStart,
            coins: catalog.rules.startCoins, gems: catalog.rules.startGems)
        cells = Self.initialCells(rules: catalog.rules)
        generatorRuntime = Dictionary(uniqueKeysWithValues: catalog.generators.values.map {
            ($0.id, GeneratorRuntime(id: $0.id, charges: $0.baseCharges, maxCharges: $0.baseCharges,
                produced: 0, upgraded: false, lastChargeDate: Date()))
        })
        activeOrderIndex = 0
        completedOrderIDs = []
        restorationState = "damaged"
        tutorialStep = 0
        selectedCellID = nil
        lastEnergyUpdate = Date()
        save()
    }

    func tapCell(_ id: Int) {
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return }
        switch cells[index].state {
        case .generator:
            produce(from: cells[index].generator)
        case .item:
            if let selected = selectedCellID, selected != id { moveOrMerge(from: selected, to: id) }
            else { selectedCellID = selectedCellID == id ? nil : id }
        case .empty:
            if let selected = selectedCellID { moveOrMerge(from: selected, to: id) }
        case .sand:
            clearSand(at: index)
        case .cobweb:
            clearCobweb(at: index)
        case .locked:
            message = "Dieses Feld wird mit Level \(cells[index].unlockLevel ?? 1) freigeschaltet."
        }
    }

    func produce(from generatorID: String?) {
        guard let generatorID, let definition = catalog.generators[generatorID], var runtime = generatorRuntime[generatorID] else { return }
        refill(&runtime, definition: definition)
        guard player.energy >= definition.energyCost else { message = GameError.noEnergy.localizedDescription; return }
        guard runtime.charges > 0 else { message = GameError.noCharge.localizedDescription; return }
        guard let empty = cells.firstIndex(where: { $0.state == .empty }) else { message = GameError.boardFull.localizedDescription; return }
        let drops = runtime.upgraded ? definition.upgradedDrops : definition.baseDrops
        let stage = weightedStage(drops)
        guard let item = catalog.items.values.first(where: { $0.chainID == definition.chainID && $0.stage == stage }) else { return }
        cells[empty].state = .item
        cells[empty].item = item.id
        cells[empty].bubble = Double.random(in: 0...1) < (runtime.upgraded ? 0.12 : 0.08)
        player.energy -= definition.energyCost
        runtime.charges -= 1
        runtime.produced += 1
        if runtime.produced >= catalog.rules.autoUpgradeAfterProduced && !runtime.upgraded {
            runtime.upgraded = true
            runtime.maxCharges = definition.upgradedCharges
            runtime.charges = min(runtime.charges + 4, runtime.maxCharges)
            message = "\(definition.displayName) wurde verbessert!"
        }
        generatorRuntime[generatorID] = runtime
        save()
    }

    func moveOrMerge(from sourceID: Int, to targetID: Int) {
        guard let source = cells.firstIndex(where: { $0.id == sourceID }),
              let target = cells.firstIndex(where: { $0.id == targetID }),
              cells[source].state == .item else { selectedCellID = nil; return }
        captureUndo()
        if cells[target].state == .empty {
            cells[target] = BoardCell(row: cells[target].row, col: cells[target].col, state: .item,
                item: cells[source].item, bubble: cells[source].bubble)
            cells[source] = BoardCell(row: cells[source].row, col: cells[source].col, state: .empty)
        } else if cells[target].state == .item, cells[target].item == cells[source].item,
                  let itemID = cells[source].item, let next = catalog.items[itemID]?.mergeInto {
            cells[target].item = next
            cells[target].bubble = false
            cells[source] = BoardCell(row: cells[source].row, col: cells[source].col, state: .empty)
            player.xp += catalog.items[next]?.xpValue ?? 1
            updateLevel()
        } else {
            message = GameError.invalidMove.localizedDescription
        }
        selectedCellID = nil
        save()
    }

    func completeActiveOrder() {
        guard let order = activeOrder, canComplete(order) else { message = "Die benötigten Gegenstände fehlen noch."; return }
        for requirement in order.requirements {
            var remaining = requirement.count
            for index in cells.indices where remaining > 0 && cells[index].item == requirement.item {
                cells[index] = BoardCell(row: cells[index].row, col: cells[index].col, state: .empty)
                remaining -= 1
            }
        }
        player.coins += order.coins
        player.gems += order.gems
        player.energy += order.energy
        if !catalog.rules.rewardsMayOverfillEnergy {
            player.energy = min(catalog.rules.energyMax, player.energy)
        }
        player.xp += order.xp
        completedOrderIDs.append(order.id)
        apply(actions: order.restorationActions)
        activeOrderIndex += 1
        updateLevel()
        message = "Auftrag geschafft! +\(order.coins) Münzen"
        save()
    }

    func canComplete(_ order: OrderDefinition) -> Bool {
        order.requirements.allSatisfy { requirement in
            cells.filter { $0.item == requirement.item }.count >= requirement.count
        }
    }

    func item(for cell: BoardCell) -> ItemDefinition? { cell.item.flatMap { catalog.items[$0] } }
    func generator(for cell: BoardCell) -> GeneratorDefinition? { cell.generator.flatMap { catalog.generators[$0] } }

    var activeTutorial: TutorialStep? {
        catalog.tutorialSteps.indices.contains(tutorialStep) ? catalog.tutorialSteps[tutorialStep] : nil
    }

    func advanceTutorial() {
        tutorialStep = min(tutorialStep + 1, catalog.tutorialSteps.count)
        save()
    }

    func skipTutorial() {
        tutorialStep = catalog.tutorialSteps.count
        save()
    }

    func sellSelectedItem() {
        guard let selectedCellID,
              let index = cells.firstIndex(where: { $0.id == selectedCellID }),
              cells[index].state == .item,
              let itemID = cells[index].item,
              let item = catalog.items[itemID] else { return }
        captureUndo()
        cells[index] = BoardCell(row: cells[index].row, col: cells[index].col, state: .empty)
        player.coins += item.sellValue
        self.selectedCellID = nil
        message = "+\(item.sellValue) Münzen"
        save()
    }

    func undoLastAction() {
        guard let undoState else { return }
        guard Date().timeIntervalSince(undoState.createdAt) <= 5 else {
            self.undoState = nil
            canUndo = false
            message = "Die Rückgängig-Frist ist abgelaufen."
            return
        }
        player = undoState.player
        cells = undoState.cells
        generatorRuntime = undoState.generators
        selectedCellID = undoState.selectedCellID
        self.undoState = nil
        canUndo = false
        save()
    }

    private func captureUndo() {
        undoState = UndoState(player: player, cells: cells, generators: generatorRuntime,
            selectedCellID: selectedCellID, createdAt: Date())
        canUndo = true
    }

    private func clearSand(at index: Int) {
        guard player.coins >= catalog.rules.sandCoinsPerLayer else { message = "Du brauchst \(catalog.rules.sandCoinsPerLayer) Münzen."; return }
        player.coins -= catalog.rules.sandCoinsPerLayer
        let level = cells[index].sandLevel ?? 1
        if level > 1 { cells[index].sandLevel = level - 1 }
        else { cells[index] = BoardCell(row: cells[index].row, col: cells[index].col, state: .empty) }
        save()
    }

    private func clearCobweb(at index: Int) {
        guard player.coins >= catalog.rules.cobwebCoins else { message = "Du brauchst \(catalog.rules.cobwebCoins) Münzen."; return }
        player.coins -= catalog.rules.cobwebCoins
        cells[index] = BoardCell(row: cells[index].row, col: cells[index].col, state: .empty)
        save()
    }

    private func updateLevel() {
        let thresholds = catalog.rules.levelThresholds
        let newLevel = max(1, thresholds.lastIndex(where: { player.xp >= $0 }).map { $0 + 1 } ?? 1)
        if newLevel > player.level {
            player.level = newLevel
            player.gems += catalog.rules.rewardGemsPerLevel
            if catalog.rules.energyRefillOnLevelUp { player.energy = catalog.rules.energyMax }
            for index in cells.indices where cells[index].state == .locked && (cells[index].unlockLevel ?? 999) <= newLevel {
                cells[index] = BoardCell(row: cells[index].row, col: cells[index].col, state: .empty)
            }
            message = "Level \(newLevel) erreicht!"
        }
    }

    private func apply(actions: [String]) {
        for action in actions {
            if action == "set_state:partial" { restorationState = "partial" }
            if action == "set_state:restored" { restorationState = "restored" }
        }
    }

    private func tick() {
        let now = Date()
        let energySteps = Int(now.timeIntervalSince(lastEnergyUpdate) / catalog.rules.energyRegenSeconds)
        if energySteps > 0 && player.energy < catalog.rules.energyMax {
            player.energy = min(catalog.rules.energyMax, player.energy + energySteps)
            lastEnergyUpdate = lastEnergyUpdate.addingTimeInterval(Double(energySteps) * catalog.rules.energyRegenSeconds)
        }
        for definition in catalog.generators.values {
            guard var runtime = generatorRuntime[definition.id] else { continue }
            refill(&runtime, definition: definition)
            generatorRuntime[definition.id] = runtime
        }
    }

    private func refill(_ runtime: inout GeneratorRuntime, definition: GeneratorDefinition) {
        guard runtime.charges < runtime.maxCharges else { runtime.lastChargeDate = Date(); return }
        let total = runtime.upgraded ? definition.upgradedRechargeSeconds : definition.rechargeSeconds
        let perCharge = total / Double(runtime.maxCharges)
        let count = Int(Date().timeIntervalSince(runtime.lastChargeDate) / perCharge)
        if count > 0 {
            runtime.charges = min(runtime.maxCharges, runtime.charges + count)
            runtime.lastChargeDate = runtime.lastChargeDate.addingTimeInterval(Double(count) * perCharge)
        }
    }

    private func weightedStage(_ drops: [DropEntry]) -> Int {
        let roll = Double.random(in: 0..<1)
        var sum = 0.0
        for drop in drops { sum += drop.weight; if roll < sum { return drop.stage } }
        return drops.last?.stage ?? 1
    }

    private func applyOfflineProgress() {
        guard let data = try? Data(contentsOf: saveURL), let save = try? JSONDecoder().decode(GameSave.self, from: data) else { return }
        let elapsed = min(Date().timeIntervalSince(save.lastSaved), 24 * 3600)
        if elapsed > 0 {
            player.energy = min(catalog.rules.energyMax,
                player.energy + Int(elapsed / catalog.rules.energyRegenSeconds))
        }
    }

    private func save() {
        let save = GameSave(player: player, cells: cells, generators: Array(generatorRuntime.values),
            activeOrderIndex: activeOrderIndex, completedOrderIDs: completedOrderIDs,
            restorationState: restorationState, placedElements: [], tutorialStep: tutorialStep,
            lastSaved: Date(), campaignComplete: activeOrderIndex >= catalog.orders.count)
        guard let data = try? JSONEncoder().encode(save) else { return }
        let temporary = saveURL.appendingPathExtension("tmp")
        do { try data.write(to: temporary, options: .atomic); try? FileManager.default.removeItem(at: saveURL); try FileManager.default.moveItem(at: temporary, to: saveURL) }
        catch { message = "Der Spielstand konnte nicht gespeichert werden." }
    }

    private func load() -> Bool {
        guard let data = try? Data(contentsOf: saveURL), let save = try? JSONDecoder().decode(GameSave.self, from: data), save.saveVersion == 3 else { return false }
        player = save.player
        cells = save.cells
        generatorRuntime = Dictionary(uniqueKeysWithValues: save.generators.map { ($0.id, $0) })
        activeOrderIndex = save.activeOrderIndex
        completedOrderIDs = save.completedOrderIDs
        restorationState = save.restorationState
        tutorialStep = save.tutorialStep
        return cells.count == 63
    }

    private static func initialCells(rules: GameRules) -> [BoardCell] {
        var cells = (0..<9).flatMap { row in
            let unlockLevel = rules.unlockRowAtLevel[row]
            return (0..<7).map { BoardCell(row: row, col: $0,
                state: unlockLevel == nil ? .empty : .locked, unlockLevel: unlockLevel) }
        }
        let generators = [(0, "gen1_beach_crate"), (3, "gen2_bar_cart"), (6, "gen3_surf_locker"), (14, "gen4_tool_chest"), (19, "gen5_garden_basket")]
        for value in generators { cells[value.0].state = .generator; cells[value.0].generator = value.1 }
        cells[8].state = .item; cells[8].item = "chain1_beach_1_shell_shard"
        cells[11].state = .item; cells[11].item = "chain1_beach_1_shell_shard"
        cells[16].state = .sand; cells[16].sandLevel = 2
        cells[23].state = .sand; cells[23].sandLevel = 2
        cells[24].state = .cobweb
        cells[29].state = .item; cells[29].item = "chain2_bar_1_lime_slice"
        cells[33].state = .item; cells[33].item = "chain4_tool_1_screw"
        cells[38].state = .sand; cells[38].sandLevel = 1
        return cells
    }
}
