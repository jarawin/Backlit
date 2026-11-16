import XCTest
@testable import Backlit

final class MCPPreferenceDomainTests: XCTestCase {
    func testBundledClientReadsItsStandardApplicationDomainWithoutOpeningASuite() {
        var standardReads = 0
        let access = MCPBridgeClient.localAccess(bundleIdentifier: "local.backlit", standard: {
            standardReads += 1
            return "control"
        }, suite: {
            XCTFail("Foundation rejects the current bundle identifier as a suite")
            return nil
        })
        XCTAssertEqual(access, "control")
        XCTAssertEqual(standardReads, 1)
    }

    func testUnbundledAndTestClientsReadTheGUIsNamedDomain() {
        for bundleIdentifier in [nil, "local.backlit.tests"] {
            var suiteReads = 0
            let access = MCPBridgeClient.localAccess(bundleIdentifier: bundleIdentifier, standard: {
                XCTFail("An unbundled client's standard domain is not the GUI's preferences")
                return "off"
            }, suite: {
                suiteReads += 1
                return "status"
            })
            XCTAssertEqual(access, "status")
            XCTAssertEqual(suiteReads, 1)
        }
    }

    func testMissingPreferenceInEitherDomainDefaultsToOff() {
        for bundleIdentifier in [nil, "local.backlit", "local.backlit.tests"] {
            XCTAssertEqual(MCPBridgeClient.localAccess(bundleIdentifier: bundleIdentifier,
                standard: { nil }, suite: { nil }), "off")
        }
    }
}
