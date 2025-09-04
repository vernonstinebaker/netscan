import XCTest
@testable import netscan

final class ServiceMapperTests: XCTestCase {
    func testPortToServiceTypeMapping() throws {
        XCTAssertEqual(ServiceMapper.type(forPort: 80), .http)
        XCTAssertEqual(ServiceMapper.type(forPort: 443), .https)
        XCTAssertEqual(ServiceMapper.type(forPort: 22), .ssh)
        XCTAssertEqual(ServiceMapper.type(forPort: 53), .dns)
        XCTAssertEqual(ServiceMapper.type(forPort: 445), .smb)
        XCTAssertEqual(ServiceMapper.type(forPort: 12345), .unknown)
    }

    func testBonjourTypeMapping() throws {
        XCTAssertEqual(ServiceMapper.type(forBonjour: "_http._tcp."), .http)
        XCTAssertEqual(ServiceMapper.type(forBonjour: "_https._tcp."), .https)
        XCTAssertEqual(ServiceMapper.type(forBonjour: "_ssh._tcp."), .ssh)
        XCTAssertEqual(ServiceMapper.type(forBonjour: "_afpovertcp._tcp."), .smb)
        XCTAssertEqual(ServiceMapper.type(forBonjour: "_googlecast._tcp."), .chromecast)
        XCTAssertEqual(ServiceMapper.type(forBonjour: "_unknown._tcp."), .unknown)
    }
}

