import XCTest
@testable import netscan

final class BonjourDiscovererTests: XCTestCase {
    var discoverer: BonjourDiscoverer!

    override func setUp() async throws {
        discoverer = BonjourDiscoverer()
    }

    override func tearDown() async throws {
        discoverer = nil
    }

    func testDiscoverServiceTypesFallback() async {
        // With short timeout, should return fallback list
        let types = await discoverer.discoverServiceTypes(timeout: 0.1)
        XCTAssertFalse(types.isEmpty)
        XCTAssertTrue(types.contains("_http._tcp."))
    }

    func testDiscoverWithProvidedTypes() async {
        // Provide empty types, should return empty
        let result = await discoverer.discover(timeout: 0.1, serviceTypes: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testDiscoverWithDefaultTimeout() async {
        // Test with default timeout, may return empty if no services
        let result = await discoverer.discover(timeout: 0.1)
        // Can't assert much without real network
        XCTAssertNotNil(result)
    }

    func testBonjourHostResultInit() {
        let services = [NetworkService(name: "http", type: .http, port: 80)]
        let result = BonjourHostResult(hostname: "test.local", services: services)
        XCTAssertEqual(result.hostname, "test.local")
        XCTAssertEqual(result.services.count, 1)
    }
}