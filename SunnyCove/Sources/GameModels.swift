import Foundation

enum CellKind: String, Codable, Sendable {
    case empty, item, generator, locked, sand, cobweb
}

struct BoardCell: Identifiable, Codable, Equatable, Sendable {
    let row: Int
    let col: Int
    var state: CellKind
    var item: String?
    var generator: String?
    var bubble = false
    var sandLevel: Int?
    var unlockLevel: Int?

    var id: Int { row * 7 + col }
}

struct ItemDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let chainID: String
    let stage: Int
    let displayName: String
    let asset: String
    let sellValue: Int
    let xpValue: Int
    let mergeInto: String?
}

struct DropEntry: Codable, Hashable, Sendable {
    let stage: Int
    let weight: Double
}

struct GeneratorDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let chainID: String
    let assetReady: String
    let assetUpgraded: String
    let energyCost: Int
    let baseCharges: Int
    let upgradedCharges: Int
    let rechargeSeconds: TimeInterval
    let upgradedRechargeSeconds: TimeInterval
    let baseDrops: [DropEntry]
    let upgradedDrops: [DropEntry]
}

struct GeneratorRuntime: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var charges: Int
    var maxCharges: Int
    var produced: Int
    var upgraded: Bool
    var lastChargeDate: Date
}

struct OrderRequirement: Codable, Hashable, Sendable {
    let item: String
    let displayName: String
    let count: Int
}

struct OrderDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let sequence: Int
    let character: String
    let portrait: String
    let dialog: String
    let requirements: [OrderRequirement]
    let coins: Int
    let gems: Int
    let energy: Int
    let xp: Int
    let restorationActions: [String]
}

struct TutorialStep: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let character: String
    let portrait: String
    let text: String
}

struct PlayerState: Codable, Equatable, Sendable {
    var level = 1
    var xp = 0
    var energy = 120
    var coins = 50
    var gems = 5
}

struct GameRules: Codable, Sendable {
    var energyMax: Int
    var energyStart: Int
    var startCoins: Int
    var startGems: Int
    var energyRegenSeconds: TimeInterval
    var autoUpgradeAfterProduced: Int
    var levelThresholds: [Int]
    var rewardGemsPerLevel: Int
    var energyRefillOnLevelUp: Bool
    var rewardsMayOverfillEnergy: Bool
    var unlockRowAtLevel: [Int: Int]
    var sandCoinsPerLayer: Int
    var cobwebCoins: Int

    static let `default` = GameRules(energyMax: 120, energyStart: 120, startCoins: 50, startGems: 5, energyRegenSeconds: 15,
        autoUpgradeAfterProduced: 60,
        levelThresholds: [0, 50, 120, 210, 330, 480, 660, 880, 1140, 1450, 1810, 2230, 2720, 3290, 3950, 4680],
        rewardGemsPerLevel: 2, energyRefillOnLevelUp: true, rewardsMayOverfillEnergy: true,
        unlockRowAtLevel: [6: 3, 7: 6, 8: 10], sandCoinsPerLayer: 15, cobwebCoins: 30)
}

struct GameSave: Codable, Sendable {
    var saveVersion = 3
    var player: PlayerState
    var cells: [BoardCell]
    var generators: [GeneratorRuntime]
    var activeOrderIndex: Int
    var completedOrderIDs: [String]
    var restorationState: String
    var placedElements: [String]
    var tutorialStep: Int
    var lastSaved: Date
    var campaignComplete: Bool
}

enum GameError: LocalizedError, Equatable {
    case noEnergy, noCharge, boardFull, invalidMove, locked, contentMissing

    var errorDescription: String? {
        switch self {
        case .noEnergy: "Deine Energie lädt gerade auf."
        case .noCharge: "Der Generator lädt gerade auf."
        case .boardFull: "Auf dem Spielfeld ist kein Platz mehr."
        case .invalidMove: "Diese Gegenstände lassen sich nicht zusammenführen."
        case .locked: "Dieses Feld ist noch gesperrt."
        case .contentMissing: "Die Spieldaten konnten nicht geladen werden."
        }
    }
}
