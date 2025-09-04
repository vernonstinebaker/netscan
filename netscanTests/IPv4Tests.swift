import Testing
@testable import netscan

struct IPv4Tests {
    @Test func parseAndFormat() async throws {
        #expect(IPv4.parse("192.168.1.10") != nil)
        #expect(IPv4.format(IPv4.parse("10.0.0.1")!) == "10.0.0.1")
        #expect(IPv4.parse("256.0.0.1") == nil)
        #expect(IPv4.parse("1.2.3") == nil)
    }

    @Test func netmaskPrefixCalc() async throws {
        #expect(IPv4.netmaskPrefix(IPv4.parse("255.255.255.0")!) == 24)
        #expect(IPv4.netmaskPrefix(IPv4.parse("255.255.0.0")!) == 16)
        #expect(IPv4.netmaskPrefix(IPv4.parse("255.255.255.252")!) == 30)
    }

    @Test func networkAndBroadcast() async throws {
        let ip = IPv4.parse("192.168.1.34")!
        let mask = IPv4.parse("255.255.255.0")!
        #expect(IPv4.format(IPv4.network(ip: ip, mask: mask)) == "192.168.1.0")
        #expect(IPv4.format(IPv4.broadcast(ip: ip, mask: mask)) == "192.168.1.255")
    }

    @Test func hostEnumeration() async throws {
        // /30 -> 2 usable hosts
        let net = IPv4.parse("192.168.2.0")!
        let mask = IPv4.parse("255.255.255.252")!
        let hosts = IPv4.hosts(inNetwork: net, mask: mask)
        #expect(hosts.count == 2)
        #expect(IPv4.format(hosts[0]) == "192.168.2.1")
        #expect(IPv4.format(hosts[1]) == "192.168.2.2")

        // /31 or /32 -> 0 usable hosts
        let net31 = IPv4.parse("10.0.0.0")!
        let mask31 = IPv4.parse("255.255.255.254")!
        #expect(IPv4.hosts(inNetwork: net31, mask: mask31).isEmpty)
        let net32 = IPv4.parse("10.0.0.1")!
        let mask32 = IPv4.parse("255.255.255.255")!
        #expect(IPv4.hosts(inNetwork: net32, mask: mask32).isEmpty)
    }
}
