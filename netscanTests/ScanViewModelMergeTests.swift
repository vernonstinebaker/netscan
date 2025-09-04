import XCTest
@testable import netscan

@MainActor
final class ScanViewModelMergeTests: XCTestCase {
    func testUpdateDevice_MergesOpenPortsWithoutClobbering() async {
        let vm = ScanViewModel()

        // Initial add with port 22
        await vm.updateDevice(
            ipAddress: "192.168.1.10",
            arpMap: [:],
            isOnline: true,
            services: [],
            openPorts: [22],
            discoverySource: .nio
        )
        XCTAssertEqual(vm.devices.count, 1)
        XCTAssertEqual(Set(vm.devices[0].openPorts.map { $0.number }), Set([22]))

        // Update with no new ports should keep existing
        await vm.updateDevice(
            ipAddress: "192.168.1.10",
            arpMap: [:],
            isOnline: true,
            services: [],
            openPorts: [],
            discoverySource: .arp
        )
        XCTAssertEqual(Set(vm.devices[0].openPorts.map { $0.number }), Set([22]))

        // Update with a new port should merge (22 + 80)
        await vm.updateDevice(
            ipAddress: "192.168.1.10",
            arpMap: [:],
            isOnline: true,
            services: [],
            openPorts: [80],
            discoverySource: .ping
        )
        XCTAssertEqual(Set(vm.devices[0].openPorts.map { $0.number }), Set([22, 80]))
    }

    func testUpdateDevice_MergesServices_DedupesByTypeAndName() async {
        let vm = ScanViewModel()

        // Add a device with one service
        await vm.updateDevice(
            ipAddress: "192.168.1.20",
            arpMap: [:],
            isOnline: true,
            services: [NetworkService(name: "HTTP", type: .http)],
            discoverySource: .mdns
        )
        XCTAssertEqual(vm.devices.count, 1)
        XCTAssertEqual(vm.devices[0].services.count, 1)

        // Add the same service again (should not duplicate)
        await vm.updateDevice(
            ipAddress: "192.168.1.20",
            arpMap: [:],
            isOnline: true,
            services: [NetworkService(name: "HTTP", type: .http)],
            discoverySource: .mdns
        )
        XCTAssertEqual(vm.devices[0].services.count, 1)

        // Add a different service type
        await vm.updateDevice(
            ipAddress: "192.168.1.20",
            arpMap: [:],
            isOnline: true,
            services: [NetworkService(name: "SSH", type: .ssh)],
            discoverySource: .mdns
        )
        XCTAssertEqual(Set(vm.devices[0].services.map { $0.type }), Set([.http, .ssh]))
    }

    func testServicesWithDifferentPortsAreNotMerged() async {
        let vm = ScanViewModel()
        // Insert device with HTTP:80
        await vm.updateDevice(
            ipAddress: "192.168.1.50",
            arpMap: [:],
            isOnline: true,
            services: [NetworkService(name: "Web", type: .http, port: 80)],
            discoverySource: .mdns
        )
        // Update with HTTP:8080, should not merge with the HTTP:80 tag
        await vm.updateDevice(
            ipAddress: "192.168.1.50",
            arpMap: [:],
            isOnline: true,
            services: [NetworkService(name: "Web-Alt", type: .http, port: 8080)],
            discoverySource: .mdns
        )
        let httpServices = vm.devices[0].services.filter { $0.type == .http }
        XCTAssertEqual(httpServices.count, 2)
        XCTAssertTrue(httpServices.contains(where: { $0.port == 80 }))
        XCTAssertTrue(httpServices.contains(where: { $0.port == 8080 }))
    }
}
