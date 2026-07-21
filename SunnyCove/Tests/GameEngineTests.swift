import XCTest
@testable import SunnyCove

final class GameEngineTests: XCTestCase {
    func testCatalogContainsFiveCompleteChains() {
        let catalog = ContentCatalog.bundled()
        XCTAssertEqual(catalog.items.count, 40)
        XCTAssertEqual(Set(catalog.items.values.map(\.chainID)).count, 5)
        for chain in Set(catalog.items.values.map(\.chainID)) {
            XCTAssertEqual(catalog.items.values.filter { $0.chainID == chain }.count, 8)
        }
    }

    func testEveryMergeTargetExists() {
        let catalog = ContentCatalog.bundled()
        for item in catalog.items.values {
            if let next = item.mergeInto { XCTAssertNotNil(catalog.items[next]) }
        }
    }

    func testDropTablesSumToOne() {
        let catalog = ContentCatalog.bundled()
        for generator in catalog.generators.values {
            XCTAssertEqual(generator.baseDrops.reduce(0) { $0 + $1.weight }, 1, accuracy: 0.0001)
            XCTAssertEqual(generator.upgradedDrops.reduce(0) { $0 + $1.weight }, 1, accuracy: 0.0001)
        }
    }

    func testFallbackContainsFullCampaign() {
        let catalog = ContentCatalog.bundled()
        XCTAssertEqual(catalog.orders.count, 30)
        XCTAssertEqual(catalog.orders.last?.id, "order_30")
        XCTAssertEqual(catalog.tutorialSteps.count, 3)
        XCTAssertEqual(catalog.tutorialSteps[1].completion.type, "item_produced")
        XCTAssertEqual(catalog.restorationElements.count, 9)
    }

    func testCatalogLoaderAlwaysReturnsPlayableContent() {
        let catalog = ContentCatalog.load()
        XCTAssertEqual(catalog.items.count, 40)
        XCTAssertEqual(catalog.generators.count, 5)
        XCTAssertGreaterThanOrEqual(catalog.orders.count, 30)
        XCTAssertEqual(catalog.tutorialSteps.count, 11)
        XCTAssertEqual(catalog.restorationElements.count, 9)
    }

    func testContentManifestHashIsDeterministic() {
        let first = ContentUpdateService.sha256(of: Data("sunny-cove".utf8))
        let second = ContentUpdateService.sha256(of: Data("sunny-cove".utf8))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
    }

    func testFirstFiveLevelsHaveVerticalSlicePacing() {
        XCTAssertEqual(Array(GameRules.default.levelThresholds.prefix(5)), [0, 20, 60, 120, 220])
    }

    @MainActor
    func testInitialBoardCanPerformFirstMerge() {
        let game = GameStore()
        game.reset()
        game.moveOrMerge(from: 8, to: 11)
        XCTAssertEqual(game.cells.first(where: { $0.id == 11 })?.item, "chain1_beach_2_small_shell")
        XCTAssertEqual(game.cells.first(where: { $0.id == 8 })?.state, .empty)
    }

    @MainActor
    func testGeneratorsUnlockAcrossFirstFiveLevels() {
        let game = GameStore()
        game.reset()
        XCTAssertTrue(game.canUseGenerator("gen1_beach_crate"))
        XCTAssertFalse(game.canUseGenerator("gen2_bar_cart"))
        XCTAssertEqual(game.generatorUnlockLevel("gen3_surf_locker"), 5)
    }

    func testRasterizedGameAssetsAreBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "chain1_beach_1_shell_shard", withExtension: "png"))
        XCTAssertNotNil(Bundle.main.url(forResource: "gen1_beach_crate_ready", withExtension: "png"))
        XCTAssertNotNil(Bundle.main.url(forResource: "char_marina_friendly", withExtension: "png"))
    }
}
