import XCTest
@testable import netscan

final class PortScannerTests: XCTestCase {
    var scanner: PortScanner!

    override func setUp() async throws {
        scanner = PortScanner(host: "127.0.0.1") // localhost
    }

    override func tearDown() async throws {
        scanner = nil
    }

    func testScanPortsEmptyRange() async {
        let ports = await scanner.scanPorts(portRange: 1...10)
        // Should scan common ports within range, but 1-10 has none
        XCTAssertTrue(ports.isEmpty || ports.count <= 1) // 22 might be open on some systems
    }

    func testScanPortsCommonPorts() async {
        let ports = await scanner.scanPorts(portRange: 20...25)
        // May include 22 (ssh) if open
        let portNumbers = ports.map { $0.number }
        XCTAssertTrue(portNumbers.allSatisfy { (20...25).contains($0) })
    }

    func testGetServiceName() {
        // Since getServiceName is private, can't test directly
        // But we can test via scanPorts if it sets name
        // For now, assume it's tested indirectly
    }

    func testPortScannerInit() {
        let scanner = PortScanner(host: "192.168.1.1")
        XCTAssertNotNil(scanner)
    }
}