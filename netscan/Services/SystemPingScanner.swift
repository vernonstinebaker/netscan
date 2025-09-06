import Foundation

/// A simple ICMP ping implementation using the system ping command
public actor SystemPingScanner {
    public struct Progress: Sendable {
        public let scanned: Int
        public let total: Int
    }
    
    private let timeout: TimeInterval
    
    public init(timeout: TimeInterval = 1.0) {
        self.timeout = timeout
    }
    
    public func ping(host: String) async -> (Bool, Double)? {
        // Delegate to the SimplePing helper which runs the system ping in a sandbox-friendly way.
        return await SimplePing.ping(host: host, timeout: timeout)
    }
    
    public func scanSubnet(info: NetworkInfo, concurrency: Int = 16, skipIPs: Set<String> = [], onProgress: ((Progress) -> Void)? = nil, onDeviceFound: ((Device) -> Void)? = nil) async throws -> [Device] {
        // Parse and compute network/hosts on the main actor
        let parsed = await MainActor.run { (IPv4.parse(info.ip), IPv4.parse(info.netmask)) }
        guard let ip = parsed.0, let mask = parsed.1 else {
            print("[SystemPingScanner] Failed to parse IP or netmask: ip=\(info.ip) mask=\(info.netmask)")
            return []
        }
        let network = await MainActor.run { IPv4.network(ip: ip, mask: mask) }
        let hosts = await MainActor.run { IPv4.hosts(inNetwork: network, mask: mask) }
        let total = hosts.count
        let header: String = await MainActor.run {
            "[SystemPingScanner] Starting ICMP ping scan: network=\(IPv4.format(network)) mask=/\(IPv4.netmaskPrefix(mask)) totalHosts=\(total) skipping=\(skipIPs.count)"
        }
        print(header)
        
        var scanned = 0
        
        // Create a channel to collect results progressively
        let resultChannel = AsyncStream<Device> { continuation in
            Task {
                var index = 0
                while index < total {
                    if Task.isCancelled { 
                        continuation.finish()
                        break 
                    }
                    
                    let upper = min(index + max(1, concurrency), total)
                    
                    await withTaskGroup(of: Device?.self) { group in
                        for i in index..<upper {
                            if Task.isCancelled { break }
                            
                            let ipStr = await MainActor.run { IPv4.format(hosts[i]) }
                            
                            // Skip scanning our own IP address and already discovered IPs
                            if ipStr == info.ip || skipIPs.contains(ipStr) {
                                scanned += 1
                                onProgress?(Progress(scanned: scanned, total: total))
                                continue
                            }
                            
                            group.addTask { [weak self] in
                                guard let self = self else { return nil }
                                if Task.isCancelled { return nil }
                                
                                if let (isAlive, rtt) = await self.ping(host: ipStr) {
                                    if isAlive {
                                        return await MainActor.run { Device(ip: ipStr, rttMillis: rtt) }
                                    }
                                }
                                return nil
                            }
                        }
                        
                        // Process results as they complete
                        for await maybe in group {
                            scanned += 1
                            if let d = maybe {
                                print("[SystemPingScanner] Alive host \(d.ipAddress) rtt=\(d.rttMillis ?? -1) ms")
                                continuation.yield(d)
                                onDeviceFound?(d)
                            }
                            onProgress?(Progress(scanned: scanned, total: total))
                        }
                    }
                    
                    index = upper
                }
                
                continuation.finish()
            }
        }
        
        // Collect all results
        var results: [Device] = []
        for await device in resultChannel {
            results.append(device)
        }
        
        let snapshot = results
        let sorted: [Device] = await MainActor.run {
            snapshot.sorted { (a: Device, b: Device) in
                guard let aa = IPv4.parse(a.ipAddress)?.raw, let bb = IPv4.parse(b.ipAddress)?.raw else { return a.ipAddress < b.ipAddress }
                return aa < bb
            }
        }
        
        return sorted
    }
}
