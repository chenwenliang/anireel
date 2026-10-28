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

    func testShippingRegistryListsThreeStylesInPickerOrder() {
        XCTAssertEqual(
            StyleRegistry.shipping.packs.map(\.descriptor.id),
            [GhibliStylePack.id, ChibiStylePack.id, NPRStylePack.id]
        )
    }

    func testStyleTitlesAvoidStudioTrademark() {
        for pack in StyleRegistry.shipping.packs {
            let copy = (pack.descriptor.title + " " + pack.descriptor.subtitle).lowercased()
            XCTAssertFalse(copy.contains("ghibli"), copy)
            XCTAssertFalse(copy.contains("吉卜力"), copy)
            XCTAssertFalse(copy.contains("hayao"), copy)
        }
    }
}
