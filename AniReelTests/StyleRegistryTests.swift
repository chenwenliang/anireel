import XCTest
@testable import AniReel

final class StyleRegistryTests: XCTestCase {
    func testShippingRegistryResolvesEveryPackByID() {
        let registry = StyleRegistry.shipping
        XCTAssertFalse(registry.packs.isEmpty)
        for pack in registry.packs {
            XCTAssertEqual(registry.pack(for: pack.descriptor.id)?.descriptor.id, pack.descriptor.id)
        }
    }

    func testUnknownIDResolvesToNil() {
        XCTAssertNil(StyleRegistry.shipping.pack(for: StyleID(rawValue: "does-not-exist")))
    }

    func testRegistryKeepsDeclaredOrder() {
        let registry = StyleRegistry([NPRStylePack()])
        XCTAssertEqual(registry.packs.map(\.descriptor.id), [NPRStylePack.id])
    }
}
