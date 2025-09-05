import Foundation
import Darwin

public struct DeviceFilterOptions: Sendable, Equatable {
    public var searchText: String = ""
    public var onlineOnly: Bool = false
    public var deviceType: DeviceType? = nil
    public var source: DiscoverySource? = nil

    public init(searchText: String = "", onlineOnly: Bool = false, deviceType: DeviceType? = nil, source: DiscoverySource? = nil) {
        self.searchText = searchText
        self.onlineOnly = onlineOnly
        self.deviceType = deviceType
        self.source = source
    }

    public func apply(to devices: [Device]) -> [Device] {
    var list = devices
    // DEBUG: log incoming devices and filter options when running tests
    #if DEBUG
    print("[DeviceFilterOptions] apply called with onlineOnly=\(onlineOnly), deviceType=\(String(describing: deviceType)), source=\(String(describing: source)), searchText='\(searchText)'")
    print("[DeviceFilterOptions] incoming device ids=\(devices.map { $0.id }) types=\(devices.map { $0.deviceType.rawValue })")
    #endif
        if onlineOnly { list = list.filter { $0.isOnline } }
        if let t = deviceType { list = list.filter { $0.deviceType == t } }
        if let s = source { list = list.filter { $0.discoverySource == s } }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let lower = q.lowercased()

            // Helpers for IP/CIDR detection and matching
            func ipv4AddressValue(_ s: String) -> UInt32? {
                var addr = in_addr()
                if inet_pton(AF_INET, s, &addr) == 1 {
                    return UInt32(bigEndian: addr.s_addr)
                }
                return nil
            }

            func ipv6Bytes(_ s: String) -> [UInt8]? {
                var addr = in6_addr()
                if inet_pton(AF_INET6, s, &addr) == 1 {
                    // return the 16 raw bytes of the IPv6 address in network order
                    return withUnsafeBytes(of: addr) { Array($0) }
                }
                return nil
            }

            func ipv4InCIDR(ipStr: String, cidrStr: String) -> Bool {
                guard let ip = ipv4AddressValue(ipStr) else { return false }
                let parts = cidrStr.split(separator: "/")
                guard parts.count == 2, let base = ipv4AddressValue(String(parts[0])), let plen = Int(parts[1]), plen >= 0 && plen <= 32 else { return false }
                let mask: UInt32 = plen == 0 ? 0 : (~UInt32(0)) << (32 - UInt32(plen))
                return (ip & mask) == (base & mask)
            }

            func ipv6InCIDR(ipStr: String, cidrStr: String) -> Bool {
                // parse 'addr/prefix'
                let parts = cidrStr.split(separator: "/")
                guard parts.count == 2, let plen = Int(parts[1]), plen >= 0 && plen <= 128 else { return false }
                guard let ipBytes = ipv6Bytes(ipStr), let baseBytes = ipv6Bytes(String(parts[0])) else { return false }
                let fullBytes = 16
                var bits = plen
                for i in 0..<fullBytes {
                    if bits <= 0 { break }
                    let take = min(8, bits)
                    let mask: UInt8 = take == 8 ? 0xFF : UInt8((0xFF << (8 - take)) & 0xFF)
                    if (ipBytes[i] & mask) != (baseBytes[i] & mask) { return false }
                    bits -= take
                }
                return true
            }

            // CIDR query detection
            let isCIDRQuery = q.contains("/") && (q.range(of: "^[0-9.]+/[0-9]{1,2}$", options: .regularExpression) != nil || q.range(of: "^[0-9a-fA-F:]+/[0-9]{1,3}$", options: .regularExpression) != nil)
            // IPv4 exact dotted-quad
            let isIPv4Exact = ipv4AddressValue(q) != nil
            // IPv6 exact
            let isIPv6Exact = ipv6Bytes(q) != nil
            // IPv4 prefix like '192.168.1' (less than 4 octets)
                let isIPv4Prefix = q.range(of: #"^(?:[0-9]{1,3}\.){1,3}[0-9]{1,3}$"#, options: .regularExpression) != nil && q.split(separator: ".").count < 4

            list = list.filter { d in
                if d.name.lowercased().contains(lower) { return true }

                // Handle CIDR membership (IPv4 or IPv6)
                if isCIDRQuery {
                    if d.ipAddress.contains(":") {
                        if ipv6InCIDR(ipStr: d.ipAddress, cidrStr: q) { return true }
                    } else {
                        if ipv4InCIDR(ipStr: d.ipAddress, cidrStr: q) { return true }
                    }
                } else if isIPv4Exact || isIPv6Exact {
                    // Exact IP address match
                    if d.ipAddress == q { return true }
                } else if isIPv4Prefix {
                    if d.ipAddress.hasPrefix(q) { return true }
                } else {
                    if d.ipAddress.lowercased().contains(lower) { return true }
                }

                if (d.manufacturer ?? "").lowercased().contains(lower) { return true }
                if (d.hostname ?? "").lowercased().contains(lower) { return true }
                if (d.macAddress ?? "").lowercased().contains(lower) { return true }
                if d.displayServices.contains(where: { $0.type.rawValue.lowercased().contains(lower) || $0.name.lowercased().contains(lower) || (String($0.port ?? -1).contains(lower) && $0.port != nil) }) { return true }
                return false
            }
        }
        return list
    }
}

