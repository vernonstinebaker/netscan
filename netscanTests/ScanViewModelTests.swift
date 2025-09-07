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

    func testUpdateCounts() async {
        let vm = ScanViewModel()

        await vm.updateDevice(ipAddress: "192.168.1.1", arpMap: [:], isOnline: true, services: [NetworkService(name: "http", type: .http, port: 80)])
        await vm.updateDevice(ipAddress: "192.168.1.2", arpMap: [:], isOnline: false)

        XCTAssertEqual(vm.deviceCount, 2)
        XCTAssertEqual(vm.onlineCount, 1)
        XCTAssertEqual(vm.servicesCount, 1)
    }

    func testClearDevices() async {
        let vm = ScanViewModel()

        await vm.updateDevice(ipAddress: "192.168.1.1", arpMap: [:], isOnline: true)
        XCTAssertEqual(vm.devices.count, 1)

        vm.clearDevices()
        XCTAssertEqual(vm.devices.count, 0)
        XCTAssertEqual(vm.deviceCount, 0)
        XCTAssertEqual(vm.onlineCount, 0)
        XCTAssertEqual(vm.servicesCount, 0)
    }

    func testSortedDevices() async {
        let vm = ScanViewModel()

        await vm.updateDevice(ipAddress: "192.168.1.10", arpMap: [:], isOnline: true)
        await vm.updateDevice(ipAddress: "192.168.1.2", arpMap: [:], isOnline: true)

        let sorted = vm.sortedDevices
        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted[0].ipAddress, "192.168.1.2")
        XCTAssertEqual(sorted[1].ipAddress, "192.168.1.10")
    }

    func testDetectNetwork() {
        let vm = ScanViewModel()

        vm.detectNetwork()
        // Assuming NetworkInterface.currentIPv4() returns a valid NetworkInfo
        XCTAssertNotNil(vm.networkInfo)
    }

    func testCancelScan() async {
        let vm = ScanViewModel()

        vm.startScan()
        XCTAssertTrue(vm.isScanning)

        vm.cancelScan()
        // Wait a bit for cancellation
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        // Note: In a real test, might need to check if tasks are cancelled, but for now, just ensure no crash
        XCTAssertFalse(vm.isScanning) // May not be false immediately, but eventually
    }
}
