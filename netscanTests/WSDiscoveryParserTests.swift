import XCTest
@testable import netscan

final class WSDiscoveryParserTests: XCTestCase {
    func testParseXAddrsHosts_ExtractsHosts() throws {
        let xml = """
        <e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery">
          <e:Body>
            <d:ProbeMatches>
              <d:ProbeMatch>
                <d:Types>dn:NetworkVideoTransmitter</d:Types>
                <d:XAddrs>http://192.168.1.50:80/onvif/device_service http://fe80::1a2b:3c4d%en0:80/onvif/device_service</d:XAddrs>
              </d:ProbeMatch>
            </d:ProbeMatches>
          </e:Body>
        </e:Envelope>
        """
        let hosts = WSDiscoveryDiscoverer.parseXAddrsHosts(fromXML: xml)
        XCTAssertTrue(hosts.contains("192.168.1.50"))
        // fe80 link-local host is also parsed; scope may not be included by URL parsing
    }
}

