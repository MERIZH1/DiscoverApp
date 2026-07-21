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
        XCTAssertEqual(ContentCatalog.bundled().orders.count, 30)
        XCTAssertEqual(ContentCatalog.bundled().orders.last?.id, "order_30")
        XCTAssertEqual(ContentCatalog.bundled().tutorialSteps.count, 3)
    }

    func testCatalogLoaderAlwaysReturnsPlayableContent() {
        let catalog = ContentCatalog.load()
        XCTAssertEqual(catalog.items.count, 40)
        XCTAssertEqual(catalog.generators.count, 5)
        XCTAssertGreaterThanOrEqual(catalog.orders.count, 30)
        XCTAssertFalse(catalog.tutorialSteps.isEmpty)
    }

    func testContentManifestHashIsDeterministic() {
        let first = ContentUpdateService.sha256(of: Data("sunny-cove".utf8))
        let second = ContentUpdateService.sha256(of: Data("sunny-cove".utf8))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
    }
}
