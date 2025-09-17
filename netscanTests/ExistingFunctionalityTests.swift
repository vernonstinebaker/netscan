import XCTest
@testable import netscan

@MainActor
final class ExistingFunctionalityTests: XCTestCase {

    // MARK: - Ping Functionality Tests

    func testSimplePing() async throws {
        // Test basic ping functionality
        let result = await SimplePing.ping(host: "127.0.0.1", timeout: 1.0)

        // Should complete without crashing
        XCTAssertNotNil(result) // Could be nil, but method should work
    }

    func testSimplePingNonExistentHosts() async throws {
        // Test with non-existing IPs to ensure they return nil (dead)
        let testIPs = [
            "192.168.255.254",  // Last IP in 192.168.x.x range (likely unused)
            "10.255.255.254",   // Last IP in 10.x.x.x range (likely unused)
            "172.31.255.254"    // Last IP in 172.16-31.x.x range (likely unused)
        ]

        for ip in testIPs {
            let result = await SimplePing.ping(host: ip, timeout: 2.0)
            // Non-existing hosts should return nil
            XCTAssertNil(result, "SimplePing should return nil for non-existing host \(ip)")
        }
    }

    func testHostProberNonExistentHosts() async throws {
        // Test with non-existing IPs to ensure they return .dead
        let testIPs = [
            "192.168.255.254",  // Last IP in 192.168.x.x range (likely unused)
            "10.255.255.254",   // Last IP in 10.x.x.x range (likely unused)
            "172.31.255.254"    // Last IP in 172.16-31.x.x range (likely unused)
        ]

        for ip in testIPs {
            let result = try await HostProber.probe(ip: ip, port: 80, timeout: 2.0)
            // Non-existing hosts should return .dead
            switch result {
            case .alive:
                XCTFail("HostProber should return .dead for non-existing host \(ip)")
            case .dead:
                // Correct behavior
                break
            }
        }
    }

    func testSystemPingScanner() async throws {
        let scanner = SystemPingScanner(timeout: 1.0)

        // Test ping on localhost
        let result = await scanner.ping(host: "127.0.0.1")

        // Should complete
        XCTAssertNotNil(result)
    }

    // MARK: - Device Creation Tests

    func testDeviceCreation() throws {
        let device = Device(
            id: "test-1",
            name: "Test Device",
            ipAddress: "192.168.1.100",
            discoverySource: .ping,
            rttMillis: 10.5,
            hostname: "test.local",
            macAddress: "AA:BB:CC:DD:EE:FF",
            deviceType: .computer,
            manufacturer: "Apple",
            isOnline: true,
            services: [],
            firstSeen: Date(),
            lastSeen: Date(),
            openPorts: [
                Port(number: 80, serviceName: "HTTP", description: "Web Server", status: .open),
                Port(number: 443, serviceName: "HTTPS", description: "Secure Web Server", status: .open)
            ]
        )

        XCTAssertEqual(device.id, "test-1")
        XCTAssertEqual(device.name, "Test Device")
        XCTAssertEqual(device.ipAddress, "192.168.1.100")
        XCTAssertEqual(device.discoverySource, .ping)
        XCTAssertEqual(device.rttMillis, 10.5)
        XCTAssertEqual(device.hostname, "test.local")
        XCTAssertEqual(device.macAddress, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(device.deviceType, .computer)
        XCTAssertEqual(device.manufacturer, "Apple")
        XCTAssertTrue(device.isOnline)
        XCTAssertEqual(device.openPorts.count, 2)
        XCTAssertEqual(device.openPorts[0].number, 80)
        XCTAssertEqual(device.openPorts[1].number, 443)
    }

    // MARK: - ARP Table Tests

    func testARPTableParsing() async throws {
        let arpParser = ARPTableParser()

        // Test ARP table retrieval
        let arpTable = await arpParser.getARPTable()

        // Should complete without crashing
        // ARP table might be empty in test environment
        XCTAssertNotNil(arpTable)
    }

    // MARK: - Bonjour Discovery Tests

    func testBonjourDiscovery() async throws {
        let bonjourDiscoverer = BonjourDiscoverer()

        // Test service type discovery
        let serviceTypes = await bonjourDiscoverer.discoverServiceTypes(timeout: 1.0)

        // Should complete without crashing
        XCTAssertNotNil(serviceTypes)
    }

    // MARK: - Port Scanning Tests

    func testPortScanner() async throws {
        let portScanner = PortScanner(host: "127.0.0.1")

        // Test port scanning (should complete quickly for localhost)
        let ports = await portScanner.scanPorts(portRange: 1...10)

        // Should complete without crashing
        XCTAssertNotNil(ports)
    }

    // MARK: - Device Classification Tests

    func testDeviceClassifier() async throws {
        let classifier = DeviceClassifier()

        // Test classification with hostname
        let routerType = await classifier.classify(hostname: "myrouter", vendor: nil, openPorts: [])
        XCTAssertEqual(routerType, .router)

        let tvType = await classifier.classify(hostname: "chromecast", vendor: nil, openPorts: [])
        XCTAssertEqual(tvType, .tv)

        let computerType = await classifier.classify(hostname: "desktop", vendor: nil, openPorts: [])
        XCTAssertEqual(computerType, .computer)
    }

    // MARK: - OUI Lookup Tests

    func testOUILookup() async throws {
        let ouiService = OUILookupService.shared

        // Test vendor lookup (using a known Apple MAC prefix)
        let vendor = await ouiService.findVendor(for: "AC:BC:32:00:00:00")

        // Should complete without crashing
        // Vendor might be nil if OUI data not loaded
        XCTAssertNotNil(vendor) // Could be nil
    }

    // MARK: - Network Interface Tests

    func testNetworkInterface() async throws {
        // Test network info parsing
        let networkInfo = NetworkInfo(ip: "192.168.1.100", netmask: "255.255.255.0", cidr: 24, network: "192.168.1.0/24", broadcast: "192.168.1.255")

        let parsed = await NetworkInterface.parseNetworkInfo(networkInfo)

        XCTAssertNotNil(parsed)
        if let (_, _, network, hosts) = parsed {
            XCTAssertEqual(network, IPv4.Address(raw: 3232235776)) // 192.168.1.0 in big-endian
            XCTAssertTrue(hosts.count > 0)
        }
    }

    // MARK: - Device Filtering Tests

    func testDeviceFiltering() throws {
        let devices = [
            Device(id: "1", name: "Router", ipAddress: "192.168.1.1", discoverySource: .arp, deviceType: .router),
            Device(id: "2", name: "MacBook", ipAddress: "192.168.1.10", discoverySource: .mdns, deviceType: .laptop),
            Device(id: "3", name: "Printer", ipAddress: "192.168.1.20", discoverySource: .ping, deviceType: .printer)
        ]

        // Test filtering by device type
        let routers = devices.filter { $0.deviceType == .router }
        XCTAssertEqual(routers.count, 1)
        XCTAssertEqual(routers[0].name, "Router")

        let laptops = devices.filter { $0.deviceType == .laptop }
        XCTAssertEqual(laptops.count, 1)
        XCTAssertEqual(laptops[0].name, "MacBook")

        // Test filtering by discovery source
        let arpDevices = devices.filter { $0.discoverySource == .arp }
        XCTAssertEqual(arpDevices.count, 1)
        XCTAssertEqual(arpDevices[0].discoverySource, .arp)
    }

    // MARK: - ScanViewModel Tests

    @MainActor
    func testScanViewModelInitialization() throws {
        let viewModel = ScanViewModel()

        // Test initial state
        XCTAssertEqual(viewModel.devices.count, 0)
        XCTAssertEqual(viewModel.sortedDevices.count, 0)
        XCTAssertFalse(viewModel.isScanning)
    }

    @MainActor
    func testDeviceUpdate() async throws {
        let viewModel = ScanViewModel()

        // Test device update
        await viewModel.updateDevice(
            ipAddress: "192.168.1.100",
            arpMap: ["192.168.1.100": "AA:BB:CC:DD:EE:FF"],
            isOnline: true,
            discoverySource: .ping
        )

        // Should have added the device
        XCTAssertEqual(viewModel.devices.count, 1)
        XCTAssertEqual(viewModel.sortedDevices.count, 1)

        let device = viewModel.devices[0]
        XCTAssertEqual(device.ipAddress, "192.168.1.100")
        XCTAssertEqual(device.macAddress, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(device.discoverySource, .ping)
        XCTAssertTrue(device.isOnline)
    }

    // MARK: - Persistence Tests


}