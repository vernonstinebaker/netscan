import XCTest
@testable import netscan

final class DeviceClassifierTests: XCTestCase {
    var classifier: DeviceClassifier!

    override func setUp() async throws {
        classifier = DeviceClassifier()
    }

    override func tearDown() async throws {
        classifier = nil
    }

    func testClassifyByHostname() async {
        // Router
        let router = await classifier.classify(hostname: "myrouter", vendor: nil, openPorts: [])
        XCTAssertEqual(router, .router)

        // TV
        let tv = await classifier.classify(hostname: "chromecast", vendor: nil, openPorts: [])
        XCTAssertEqual(tv, .tv)

        // Printer
        let printer = await classifier.classify(hostname: "printer", vendor: nil, openPorts: [])
        XCTAssertEqual(printer, .printer)

        // Computer
        let computer = await classifier.classify(hostname: "desktop", vendor: nil, openPorts: [])
        XCTAssertEqual(computer, .computer)

        // Unknown
        let unknown = await classifier.classify(hostname: "unknown", vendor: nil, openPorts: [])
        XCTAssertEqual(unknown, .unknown)
    }

    func testClassifyByVendor() async {
        // Router
        let router = await classifier.classify(hostname: nil, vendor: "netgear", openPorts: [])
        XCTAssertEqual(router, .router)

        // Printer
        let printer = await classifier.classify(hostname: nil, vendor: "hp", openPorts: [])
        XCTAssertEqual(printer, .printer)

        // TV
        let tv = await classifier.classify(hostname: nil, vendor: "samsung", openPorts: [])
        XCTAssertEqual(tv, .tv)

        // Computer
        let computer = await classifier.classify(hostname: nil, vendor: "microsoft", openPorts: [])
        XCTAssertEqual(computer, .computer)
    }

    func testClassifyByPorts() async {
        // Router
        let router = await classifier.classify(hostname: nil, vendor: nil, openPorts: [Port(number: 53, serviceName: "dns", description: "DNS", status: .open)])
        XCTAssertEqual(router, .router)

        // Printer
        let printer = await classifier.classify(hostname: nil, vendor: nil, openPorts: [Port(number: 631, serviceName: "ipp", description: "IPP", status: .open)])
        XCTAssertEqual(printer, .printer)

        // TV
        let tv = await classifier.classify(hostname: nil, vendor: nil, openPorts: [Port(number: 8008, serviceName: "http", description: "HTTP", status: .open)])
        XCTAssertEqual(tv, .tv)

        // Computer
        let computer = await classifier.classify(hostname: nil, vendor: nil, openPorts: [Port(number: 445, serviceName: "smb", description: "SMB", status: .open)])
        XCTAssertEqual(computer, .computer)
    }

    func testClassifyPriority() async {
        // Hostname should take priority over vendor
        let result = await classifier.classify(hostname: "router", vendor: "apple", openPorts: [])
        XCTAssertEqual(result, .router)
    }

    func testClassifyWithConfidence() async {
        let (type, confidence) = await classifier.classifyWithConfidence(hostname: "router", vendor: nil, openPorts: [])
        XCTAssertEqual(type, .router)
        XCTAssertGreaterThan(confidence, 0.7)

        let (unknownType, unknownConfidence) = await classifier.classifyWithConfidence(hostname: nil, vendor: nil, openPorts: [])
        XCTAssertEqual(unknownType, .unknown)
        XCTAssertEqual(unknownConfidence, 0.0)
    }

    func testClassifyWithConfidenceWithServices() async {
        let services = [NetworkService(name: "http", type: .http, port: 80)]
        let (type, confidence) = await classifier.classifyWithConfidence(hostname: nil, vendor: nil, openPorts: [], services: services)
        // Should classify based on port 80, but since 80 not in rules, unknown
        XCTAssertEqual(type, .unknown)
        XCTAssertGreaterThan(confidence, 0.0)
    }

    func testFingerprintServices() async {
        let services = [NetworkService(name: "http", type: .http, port: 80)]
        let ports = [Port(number: 443, serviceName: "https", description: "HTTPS", status: .open)]
        let fingerprints = await classifier.fingerprintServices(services: services, openPorts: ports)

        XCTAssertEqual(fingerprints["http"], "port:80")
        XCTAssertEqual(fingerprints["port:443"], "open")
    }
}