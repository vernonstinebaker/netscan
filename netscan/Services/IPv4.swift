import Foundation

public enum IPv4 {
    public struct Address: Hashable, Codable, Sendable {
        public var raw: UInt32
        public init(raw: UInt32) { self.raw = raw }
    }

    public static func parse(_ string: String) -> Address? {
        var addr = in_addr()
        guard inet_pton(AF_INET, string, &addr) == 1 else { return nil }
        return Address(raw: addr.s_addr.bigEndian)
    }

    public static func format(_ address: Address) -> String {
        var addr = in_addr(s_addr: address.raw.bigEndian)
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buffer)
    }

    public static func network(ip: Address, mask: Address) -> Address {
        return Address(raw: ip.raw & mask.raw)
    }

    public static func broadcast(ip: Address, mask: Address) -> Address {
        return Address(raw: ip.raw | ~mask.raw)
    }

    public static func hosts(inNetwork network: Address, mask: Address) -> [Address] {
        let start = network.raw + 1
        let end = (network.raw | ~mask.raw) - 1
        guard end >= start else { return [] }
        return (start...end).map { Address(raw: $0) }
    }
    
    public static func netmaskPrefix(_ mask: Address) -> Int {
        return 32 - (mask.raw ^ 0xffffffff).nonzeroBitCount
    }
}
