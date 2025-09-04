import XCTest
@testable import netscan

final class NetworkFrameworkProberTests: XCTestCase {
    func testProbeInvalidIPReturnsDead() async {
        // Invalid IP should short-circuit at parse and return .dead without network activity
        let res = await NetworkFrameworkProber.probe(ip: "not.an.ip", port: 80, timeout: 0.1)
        switch res {
        case .dead: XCTAssertTrue(true)
        case .alive(_): XCTFail("Expected .dead for invalid IP")
        }
    }
}

