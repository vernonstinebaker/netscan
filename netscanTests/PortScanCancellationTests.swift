import XCTest
@testable import netscan

private actor FakePortScannerFast: PortScanning {
    func scanPorts(portRange: ClosedRange<UInt16>) async -> [netscan.Port] {
        return [netscan.Port(number: 80, serviceName: "http", description: "Open", status: .open)]
    }
}

private actor FakePortScannerSlow: PortScanning {
    func scanPorts(portRange: ClosedRange<UInt16>) async -> [netscan.Port] {
        // Simulate a long-running scan that respects cancellation
        let start = Date()
        while Date().timeIntervalSince(start) < 1.0 {
            if Task.isCancelled { return [] }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms chunks
        }
        return [netscan.Port(number: 22, serviceName: "ssh", description: "Open", status: .open)]
    }
}

@MainActor
final class PortScanCancellationTests: XCTestCase {
    func testPortScanMergesResultsAndMapsService() async throws {
        let vm = ScanViewModel(modelContext: nil, portScannerFactory: { _ in FakePortScannerFast() })
        await vm.updateDevice(ipAddress: "192.168.1.30", arpMap: [:], isOnline: true, services: [], discoverySource: .nio)

        // Allow background task to run
        try? await Task.sleep(nanoseconds: 150_000_000)

        guard let device = vm.devices.first(where: { $0.ipAddress == "192.168.1.30" }) else {
            return XCTFail("Device not found")
        }
        XCTAssertTrue(device.openPorts.contains(where: { $0.number == 80 }))
        XCTAssertTrue(device.services.contains(where: { $0.type == .http }))
    }

    func testCancelScanStopsSlowPortScan() async throws {
        let vm = ScanViewModel(modelContext: nil, portScannerFactory: { _ in FakePortScannerSlow() })
        await vm.updateDevice(ipAddress: "192.168.1.40", arpMap: [:], isOnline: true, services: [], discoverySource: .nio)

        // Immediately cancel
        vm.cancelScan()
        // Give a short window to propagate cancellation
        try? await Task.sleep(nanoseconds: 150_000_000)

        guard let device = vm.devices.first(where: { $0.ipAddress == "192.168.1.40" }) else {
            return XCTFail("Device not found")
        }
        // Expect no ports added because the slow scan should be cancelled
        XCTAssertTrue(device.openPorts.isEmpty)
    }
}
