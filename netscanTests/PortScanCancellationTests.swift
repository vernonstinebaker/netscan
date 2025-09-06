import XCTest
@testable import netscan

@MainActor
final class PortScanCancellationTests: XCTestCase {
    func testCancelScanStopsScanning() async throws {
        let vm = ScanViewModel()
        vm.networkInfo = NetworkInfo(ip: "192.168.1.1", netmask: "255.255.255.0", cidr: 24, network: "192.168.1.0", broadcast: "192.168.1.255")
        
        // Start a scan
        vm.startScan()
        XCTAssertTrue(vm.isScanning)
        
        // Immediately cancel
        vm.cancelScan()
        
        // Give a short window to propagate cancellation
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Check that scanning stopped
        XCTAssertFalse(vm.isScanning)
    }
    
    func testScanUpdatesProgress() async throws {
        let vm = ScanViewModel()
        vm.networkInfo = NetworkInfo(ip: "192.168.1.1", netmask: "255.255.255.0", cidr: 24, network: "192.168.1.0", broadcast: "192.168.1.255")
        
        // Start a scan
        vm.startScan()
        XCTAssertTrue(vm.isScanning)
        
        // Wait a bit for progress to update
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Progress text should be updated
        XCTAssertFalse(vm.progressText.isEmpty)
        
        // Cancel the scan
        vm.cancelScan()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(vm.isScanning)
    }
}
