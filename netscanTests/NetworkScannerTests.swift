import XCTest
@testable import netscan

final class NetworkScannerTests: XCTestCase {
    func testScanSubnet_EnumeratesHosts_ReportsProgress_AndSorts() async {
        // Subnet: 192.168.1.0/30 -> hosts: 192.168.1.1, 192.168.1.2
        let info = NetworkInfo(
            ip: "192.168.1.1",
            netmask: "255.255.255.252",
            cidr: 30,
            network: "192.168.1.0",
            broadcast: "192.168.1.3"
        )

        // Pretend only 192.168.1.2 is alive
        let aliveSet: Set<String> = ["192.168.1.2"]
        let fakeProbe: NetworkScanner.ProbeFunc = { ip, _ in
            if aliveSet.contains(ip) { return .alive(1.0) }
            return .dead
        }
        
        // Mock port scanner that returns quickly
        let fakePortScan: NetworkScanner.PortScanFunc = { host in
            return await MainActor.run {
                [Port(number: 80, serviceName: "http", description: "HTTP", status: .open)]
            }
        }

        let scanner = NetworkScanner(timeout: 0.1, probe: fakeProbe, portScan: fakePortScan)
        var progressEvents: [NetworkScanner.Progress] = []

        let devices = await scanner.scanSubnet(info: info, concurrency: 2, onProgress: { p in
            progressEvents.append(p)
        })

        // Assert only the alive host is returned
        XCTAssertEqual(devices.map { $0.ipAddress }, ["192.168.1.2"]) 

        // Assert progress reached total host count (2 for /30)
        XCTAssertEqual(progressEvents.last?.total, 2)
        XCTAssertEqual(progressEvents.last?.scanned, 2)

        // Ensure devices are sorted (trivial here with 1 entry)
        XCTAssertEqual(devices, devices.sorted { (a: Device, b: Device) in
            guard let aa = IPv4.parse(a.ipAddress)?.raw, let bb = IPv4.parse(b.ipAddress)?.raw else { return a.ipAddress < b.ipAddress }
            return aa < bb
        })
    }
}
