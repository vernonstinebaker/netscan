import XCTest
@testable import netscan

@MainActor
final class ScanViewModelTests: XCTestCase {
    func testUpdateDeviceRespectsDiscoveryPriority() async {
        let vm = ScanViewModel()

        // Start by adding a device discovered via ARP
        await vm.updateDevice(ipAddress: "192.168.1.10", arpMap: ["192.168.1.10": "aa:bb:cc:dd:ee:ff"], isOnline: true, discoverySource: .arp)
        XCTAssertEqual(vm.devices.count, 1)
        XCTAssertEqual(vm.devices.first?.discoverySource, .arp)

        // Lower-priority source (ping) should NOT overwrite discoverySource
        await vm.updateDevice(ipAddress: "192.168.1.10", arpMap: [:], isOnline: true, discoverySource: .ping)
        XCTAssertEqual(vm.devices.first?.discoverySource, .arp)

        // Higher-priority source (mdns) should overwrite discoverySource
        await vm.updateDevice(ipAddress: "192.168.1.10", arpMap: [:], isOnline: true, discoverySource: .mdns)
        XCTAssertEqual(vm.devices.first?.discoverySource, .mdns)
    }
}
