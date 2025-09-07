import XCTest
@testable import netscan

final class OperatingSystemTests: XCTestCase {
    func testRawValues() {
        XCTAssertEqual(OperatingSystem.unknown.rawValue, "unknown")
        XCTAssertEqual(OperatingSystem.linux.rawValue, "linux")
        XCTAssertEqual(OperatingSystem.windows.rawValue, "windows")
        XCTAssertEqual(OperatingSystem.macOS.rawValue, "macOS")
        XCTAssertEqual(OperatingSystem.iOS.rawValue, "iOS")
        XCTAssertEqual(OperatingSystem.android.rawValue, "android")
        XCTAssertEqual(OperatingSystem.router.rawValue, "router")
        XCTAssertEqual(OperatingSystem.printer.rawValue, "printer")
        XCTAssertEqual(OperatingSystem.tv.rawValue, "tv")
    }

    func testCaseIterable() {
        let allCases = OperatingSystem.allCases
        XCTAssertEqual(allCases.count, 9)
        XCTAssertTrue(allCases.contains(.unknown))
        XCTAssertTrue(allCases.contains(.macOS))
    }

    func testInitFromRawValue() {
        XCTAssertEqual(OperatingSystem(rawValue: "linux"), .linux)
        XCTAssertEqual(OperatingSystem(rawValue: "invalid"), nil)
    }
}