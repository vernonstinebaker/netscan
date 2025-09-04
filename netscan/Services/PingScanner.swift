import Foundation
import Network

/// A network scanner that uses TCP port checking across multiple common ports
public actor PingScanner {
    public struct Progress: Sendable {
        public let scanned: Int
        public let total: Int
    }
    
    public struct PingResult: Sendable {
        public let isOnline: Bool
        public let rtt: Double?
    }
    
    // Collection of commonly open ports to check
    private let portsToCheck: [UInt16]
    private let timeout: TimeInterval
    private let requiredPortResponses: Int
    
    public init(
        ports: [UInt16] = [80, 443, 22, 445, 139, 53, 3389, 8080],
        timeout: TimeInterval = 0.3,
        requiredPortResponses: Int = 1
    ) {
        self.portsToCheck = ports
        self.timeout = timeout
        self.requiredPortResponses = requiredPortResponses
    }
    
    /// Performs a quick check on a single host to see if it's online.
    public func ping(host: String) async throws -> PingResult {
        for port in portsToCheck.prefix(5) { // Check a few common ports quickly
            try Task.checkCancellation()
            if let (isAlive, rtt) = try await Self.checkPort(host, port: port, timeout: timeout) {
                if isAlive {
                    return PingResult(isOnline: true, rtt: rtt)
                }
            }
        }
        return PingResult(isOnline: false, rtt: nil)
    }
    
    public func scanSubnet(info: NetworkInfo, concurrency: Int = 32, skipIPs: Set<String> = [], onProgress: ((Progress) -> Void)? = nil, onDeviceFound: ((Device) -> Void)? = nil) async throws -> [Device] {
        let parsed = await MainActor.run { (IPv4.parse(info.ip), IPv4.parse(info.netmask)) }
        guard let ip = parsed.0, let mask = parsed.1 else {
            return []
        }
        
        let network = await MainActor.run { IPv4.network(ip: ip, mask: mask) }
        let hosts = await MainActor.run { IPv4.hosts(inNetwork: network, mask: mask) }
        let total = hosts.count
        var scanned = 0
        
        let resultChannel = AsyncStream<Device> { continuation in
            Task {
                var index = 0
                while index < total {
                    try Task.checkCancellation()
                    let upper = min(index + max(1, concurrency), total)
                    
                    try await withThrowingTaskGroup(of: (String, Double?, [Int])?.self) { group in
                        for i in index..<upper {
                            try Task.checkCancellation()
                            let ipStr = await MainActor.run { IPv4.format(hosts[i]) }

                            if ipStr == info.ip || skipIPs.contains(ipStr) {
                                scanned += 1
                                onProgress?(Progress(scanned: scanned, total: total))
                                continue
                            }

                            group.addTask { [timeout, portsToCheck, requiredPortResponses] in
                                try Task.checkCancellation()

                                var foundPortNumbers: [Int] = []
                                var bestRtt: Double = Double.infinity

                                let toAttempt = portsToCheck.prefix(min(24, portsToCheck.count))
                                for port in toAttempt {
                                    try Task.checkCancellation()
                                    if let (isAlive, rtt) = try await Self.checkPort(ipStr, port: port, timeout: timeout) {
                                        if isAlive {
                                            // Collect primitive port numbers here; construct Port on MainActor later
                                            foundPortNumbers.append(Int(port))
                                            bestRtt = min(bestRtt, rtt)
                                            if foundPortNumbers.count >= requiredPortResponses { break }
                                        }
                                    }
                                }

                                if !foundPortNumbers.isEmpty {
                                    let finalRtt: Double? = (bestRtt == Double.infinity) ? nil : bestRtt
                                    return (ipStr, finalRtt, foundPortNumbers)
                                } else {
                                    return nil
                                }
                            }
                        }

                        for try await maybeResult in group {
                            scanned += 1
                            if let (ipFound, rttFound, portNumbers) = maybeResult {
                                // Construct Port and Device on the MainActor to avoid actor-isolation/concurrency issues
                                let device = await MainActor.run {
                                    let ports: [Port] = portNumbers.map { Port(number: $0, serviceName: "unknown", description: "", status: .open) }
                                    return Device(ip: ipFound, rttMillis: rttFound, openPorts: ports)
                                }
                                continuation.yield(device)
                                onDeviceFound?(device)
                            }
                            onProgress?(Progress(scanned: scanned, total: total))
                        }
                    }
                    
                    index = upper
                }
                
                continuation.finish()
            }
        }
        
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
    
    private static func checkPort(_ host: String, port: UInt16, timeout: TimeInterval) async throws -> (Bool, Double)? {
        do {
            let res = try await HostProber.probe(ip: host, port: port, timeout: timeout)
            switch res {
            case .alive(let ms):
                return (true, ms ?? 0)
            case .dead:
                return nil
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }
}
