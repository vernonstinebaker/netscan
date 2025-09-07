import XCTest
@testable import netscan

final class NetworkInfoTests: XCTestCase {
    func testInit() {
        let info = NetworkInfo(ip: "192.168.1.1", netmask: "255.255.255.0", cidr: 24, network: "192.168.1.0", broadcast: "192.168.1.255")
        XCTAssertEqual(info.ip, "192.168.1.1")
        XCTAssertEqual(info.netmask, "255.255.255.0")
        XCTAssertEqual(info.cidr, 24)
        XCTAssertEqual(info.network, "192.168.1.0")
        XCTAssertEqual(info.broadcast, "192.168.1.255")
    }

    func testDescription() {
        let info = NetworkInfo(ip: "192.168.1.1", netmask: "255.255.255.0", cidr: 24, network: "192.168.1.0", broadcast: "192.168.1.255")
        let desc = info.description
        XCTAssertTrue(desc.contains("192.168.1.1"))
        XCTAssertTrue(desc.contains("192.168.1.0"))
        XCTAssertTrue(desc.contains("24"))
    }

    func testEquatable() {
        let info1 = NetworkInfo(ip: "192.168.1.1", netmask: "255.255.255.0", cidr: 24, network: "192.168.1.0", broadcast: "192.168.1.255")
        let info2 = NetworkInfo(ip: "192.168.1.1", netmask: "255.255.255.0", cidr: 24, network: "192.168.1.0", broadcast: "192.168.1.255")
        let info3 = NetworkInfo(ip: "192.168.1.2", netmask: "255.255.255.0", cidr: 24, network: "192.168.1.0", broadcast: "192.168.1.255")

        XCTAssertEqual(info1, info2)
        XCTAssertNotEqual(info1, info3)
    }
}