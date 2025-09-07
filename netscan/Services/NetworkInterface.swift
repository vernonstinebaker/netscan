import Foundation
import Darwin

public enum NetworkInterface {
    public static func currentIPv4() -> NetworkInfo? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        func isRFC1918(_ ip: IPv4.Address) -> Bool {
            let v = ip.raw
            // 10.0.0.0/8 -> 0x0A000000 .. 0x0AFFFFFF
            if (v & 0xFF00_0000) == 0x0A00_0000 { return true }
            // 172.16.0.0/12 -> 0xAC10_0000 .. 0xAC1F_FFFF
            if (v & 0xFFF0_0000) == 0xAC10_0000 { return true }
            // 192.168.0.0/16 -> 0xC0A8_0000 .. 0xC0A8_FFFF
            if (v & 0xFFFF_0000) == 0xC0A8_0000 { return true }
            return false
        }

        var candidates = [NetworkInfo]()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor?.pointee {
            defer { cursor = ifa.ifa_next }
            let flags = Int32(ifa.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard isUp && !isLoopback, let addr = ifa.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let ifname = String(cString: ifa.ifa_name)
            let addr_in = UnsafeRawPointer(ifa.ifa_addr).assumingMemoryBound(to: sockaddr_in.self).pointee
            let mask_in = UnsafeRawPointer(ifa.ifa_netmask).assumingMemoryBound(to: sockaddr_in.self).pointee

            var ipBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var maskBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            _ = getnameinfo(UnsafePointer(ifa.ifa_addr), socklen_t(addr_in.sin_len), &ipBuf, socklen_t(ipBuf.count), nil, 0, NI_NUMERICHOST)
            _ = getnameinfo(UnsafePointer(ifa.ifa_netmask), socklen_t(mask_in.sin_len), &maskBuf, socklen_t(maskBuf.count), nil, 0, NI_NUMERICHOST)
            let ipStr = String(cString: ipBuf)
            let maskStr = String(cString: maskBuf)
            guard let ip = IPv4.parse(ipStr), let mask = IPv4.parse(maskStr) else { continue }
            let net = IPv4.network(ip: ip, mask: mask)
            let bcast = IPv4.broadcast(ip: ip, mask: mask)
            let prefix = IPv4.netmaskPrefix(mask)
            
            let info = NetworkInfo(ip: ipStr, netmask: maskStr, cidr: prefix, network: IPv4.format(net), broadcast: IPv4.format(bcast))
            candidates.append(info)
            
            if isRFC1918(ip) {
                print("[NetworkInterface] Found RFC1918 interface \(ifname): \(ipStr). Using it.")
                return info
            }
        }
        
        if let best = candidates.first {
            print("[NetworkInterface] No RFC1918 interface found. Using the first available one.")
            return best
        }

        return nil
    }

    /// Parses network info and returns the parsed IP, mask, network, and hosts
    public static func parseNetworkInfo(_ info: NetworkInfo) async -> (ip: IPv4.Address, mask: IPv4.Address, network: IPv4.Address, hosts: [IPv4.Address])? {
        let parsed = await MainActor.run { (IPv4.parse(info.ip), IPv4.parse(info.netmask)) }
        guard let ip = parsed.0, let mask = parsed.1 else {
            return nil
        }
        let network = await MainActor.run { IPv4.network(ip: ip, mask: mask) }
        let hosts = await MainActor.run { IPv4.hosts(inNetwork: network, mask: mask) }
        return (ip, mask, network, hosts)
    }
}
