import XCTest
@testable import netscan

final class DiscoveryServicesTests: XCTestCase {

    // MARK: - HTTPInfoGatherer Tests

    func testHTTPInfoGatherer() async throws {
        let gatherer = HTTPInfoGatherer(timeout: 5.0)

        // Test with a known HTTP server (httpbin.org)
        let info = await gatherer.gatherInfo(host: "httpbin.org", port: 80, useHTTPS: false)

        // Should get some response (even if it's an error)
        XCTAssertNotNil(info)

        if let info = info {
            // Should have server header or some device info
            XCTAssertTrue(info.serverHeader != nil || !info.deviceInfo.isEmpty)
        }
    }

    func testHTTPInfoGathererTimeout() async throws {
        let gatherer = HTTPInfoGatherer(timeout: 0.1)

        // Test with non-existent host - should timeout quickly
        let info = await gatherer.gatherInfo(host: "192.168.255.254", port: 80, useHTTPS: false)

        // Should return nil for non-existent host
        XCTAssertNil(info)
    }

    // MARK: - MACAddressDiscoverer Tests

    func testMACAddressDiscovery() async throws {
        let discoverer = MACAddressDiscoverer(timeout: 3.0)

        // Test with localhost (should have a MAC)
        let mac = await discoverer.discoverMACAddress(for: "127.0.0.1")

        // Localhost might not have a meaningful MAC, but the method should complete
        // This is more of a smoke test to ensure the method doesn't crash
        XCTAssertNotNil(mac) // Could be nil, but method should complete
    }

    func testMACAddressDiscoveryNonExistent() async throws {
        let discoverer = MACAddressDiscoverer(timeout: 1.0)

        // Test with non-existent IP
        let mac = await discoverer.discoverMACAddress(for: "192.168.255.254")

        // Should return nil for non-existent IP
        XCTAssertNil(mac)
    }

    // MARK: - DNSReverseLookupService Tests

    func testDNSReverseLookup() async throws {
        let dnsService = DNSReverseLookupService(timeout: 3.0)

        // Test with localhost
        let result = await dnsService.reverseLookup("127.0.0.1")

        // Should get some result (even if it's just "resolved: false")
        XCTAssertNotNil(result)
    }

    func testDNSReverseLookupNonExistent() async throws {
        let dnsService = DNSReverseLookupService(timeout: 1.0)

        // Test with non-existent IP
        let result = await dnsService.reverseLookup("192.168.255.254")

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.resolved)
        XCTAssertNil(result!.hostname)
    }



    // MARK: - SSHFingerprintService Tests

    func testSSHFingerprint() async throws {
        let sshService = SSHFingerprintService(timeout: 3.0)

        // Test with localhost (might not have SSH)
        let result = await sshService.getSSHInfo(for: "127.0.0.1", port: 22)

        // Should complete without crashing
        // Result might be nil if no SSH server
        XCTAssertNotNil(result) // Could be nil, but method should complete
    }

    // MARK: - Integration Tests

    func testDeviceInfoGathering() async throws {
        let macDiscoverer = MACAddressDiscoverer(timeout: 2.0)

        // Test gathering comprehensive device info
        let (macAddress, vendor, deviceInfo) = await macDiscoverer.gatherDeviceInfo(for: "127.0.0.1")

        // Should complete without crashing
        // Values might be nil, but method should work
        XCTAssertNotNil(macAddress) // Could be nil
        XCTAssertNotNil(vendor) // Could be nil
        XCTAssertNotNil(deviceInfo) // Should be empty dict at minimum
    }

    // MARK: - Batch Operations Tests

    func testDNSBatchLookup() async throws {
        let dnsService = DNSReverseLookupService(timeout: 2.0)

        let ips = ["127.0.0.1", "192.168.255.254"]
        let results = await dnsService.batchReverseLookup(ips)

        XCTAssertEqual(results.count, 2)
        XCTAssertNotNil(results["127.0.0.1"])
        XCTAssertNotNil(results["192.168.255.254"])
    }

    // MARK: - Error Handling Tests

    func testInvalidHostHandling() async throws {
        let gatherer = HTTPInfoGatherer(timeout: 1.0)

        // Test with invalid host
        let result = await gatherer.gatherInfo(host: "invalid.host.name", port: 80, useHTTPS: false)

        // Should handle gracefully
        XCTAssertNil(result)
    }

    func testTimeoutHandling() async throws {
        let gatherer = HTTPInfoGatherer(timeout: 0.001) // Very short timeout

        // Test with slow/unresponsive host
        let result = await gatherer.gatherInfo(host: "httpbin.org", port: 80, useHTTPS: false)

        // Might return nil due to timeout, but shouldn't crash
        // This is more of a smoke test
        XCTAssertNotNil(result) // Could be nil due to timeout
    }
}