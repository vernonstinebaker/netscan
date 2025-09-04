import XCTest
@testable import netscan

final class DeviceFilterTests: XCTestCase {
    func testFilterByOnlineAndTypeAndQuery() throws {
        let devices: [Device] = [
            Device(id: "1", name: "Router", ipAddress: "192.168.1.1", discoverySource: .arp, rttMillis: nil, hostname: "router.local", macAddress: "aa:bb:cc:00:00:01", deviceType: .router, manufacturer: "Netgear", isOnline: true),
            Device(id: "2", name: "MacBook", ipAddress: "192.168.1.10", discoverySource: .mdns, rttMillis: nil, hostname: "mbp.local", macAddress: "aa:bb:cc:00:00:02", deviceType: .laptop, manufacturer: "Apple", isOnline: true),
            Device(id: "3", name: "Old PC", ipAddress: "192.168.1.20", discoverySource: .ping, rttMillis: nil, hostname: nil, macAddress: nil, deviceType: .computer, manufacturer: nil, isOnline: false)
        ]

        var opts = DeviceFilterOptions(onlineOnly: true, deviceType: .laptop)
        var result = opts.apply(to: devices)
        XCTAssertEqual(result.map { $0.id }, ["2"]) // only online laptop

        opts = DeviceFilterOptions(searchText: "192.168.1.1")
        result = opts.apply(to: devices)
        XCTAssertEqual(result.map { $0.id }, ["1"]) // query by ip

        opts = DeviceFilterOptions(searchText: "apple")
        result = opts.apply(to: devices)
        XCTAssertEqual(result.map { $0.id }, ["2"]) // manufacturer match
    }
}

