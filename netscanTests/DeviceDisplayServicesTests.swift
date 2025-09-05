import XCTest
@testable import netscan

final class DeviceDisplayServicesTests: XCTestCase {
    func testDisplayServicesIncludesNonStandardPortsAndDedupesByTypeAndPort() throws {
        // Device has a discovery service for HTTP (bonjour) and open ports including non-standard HTTP
        let discoveryServices: [NetworkService] = [
            NetworkService(name: "Web UI", type: ServiceType.http, port: nil),
            NetworkService(name: "SSH Service", type: ServiceType.ssh, port: nil)
        ]

        let openPorts: [netscan.Port] = [
            netscan.Port(number: 8080, serviceName: "http-alt", description: "Alt HTTP", status: .open),
            netscan.Port(number: 22, serviceName: "ssh", description: "Secure Shell", status: .open),
            netscan.Port(number: 80, serviceName: "http", description: "Standard HTTP", status: .open),
            netscan.Port(number: 8443, serviceName: "https-alt", description: "Alt HTTPS", status: .open)
        ]

        let device = Device(
            id: "test-device",
            name: "Test Device",
            ipAddress: "10.0.0.5",
            rttMillis: nil,
            hostname: "test.local",
            macAddress: nil,
            deviceType: .unknown,
            manufacturer: "TestCo",
            isOnline: true,
            services: discoveryServices,
            firstSeen: nil,
            lastSeen: nil,
            openPorts: openPorts,
            confidence: nil,
            fingerprints: nil
        )

        let display = device.displayServices

        // Expect at least http (for port 80), http for 8080, https for 8443, ssh for 22
        // displayServices dedupes by (type, port) so we should see distinct entries for http:80 and http:8080
    let httpPorts = display.filter { $0.type == ServiceType.http }.compactMap { $0.port }
        XCTAssertTrue(httpPorts.contains(80), "displayServices should contain HTTP on port 80")
        XCTAssertTrue(httpPorts.contains(8080), "displayServices should contain HTTP on port 8080")

        // HTTPS on 8443 should be present as https type with port 8443
    let httpsPorts = display.filter { $0.type == ServiceType.https }.compactMap { $0.port }
        XCTAssertTrue(httpsPorts.contains(8443), "displayServices should contain HTTPS on port 8443")

        // SSH should be present with port 22
    let sshPorts = display.filter { $0.type == ServiceType.ssh }.compactMap { $0.port }
        XCTAssertTrue(sshPorts.contains(22), "displayServices should contain SSH on port 22")

        // Ensure that the discovery service 'Web UI' (no port) doesn't shadow the port-specific http entries
        let webUIDisplay = display.first { $0.name == "Web UI" }
        XCTAssertNotNil(webUIDisplay, "Discovery service should be present in displayServices")
    }
}
