import Foundation
import Network
import NIO
import NIOCore
import Dispatch

/// A network scanner that tries to find devices on the network using multiple methods
public actor NIOPingScanner {
    public struct Progress: Sendable {
        public let scanned: Int
        public let total: Int
    }
    
    // Collection of commonly open ports to check
    private let portsToCheck: [UInt16]
    private let timeout: TimeInterval
    
    /// Creates a new ping scanner with smart port detection
    /// - Parameters:
    ///   - ports: Ports to check on each host (default: common service ports)
    ///   - timeout: Timeout in seconds for each connection attempt (default: 0.3)
    public init(
        ports: [UInt16] = [
            80, 443, 22, 445, 139, 53, 3389, 8080,
            8008, 8009, 8443, 5357, 554, 32400, 7000, 9100,
            81, 82, 5000, 5001, 1723, 21, 23
        ],
        timeout: TimeInterval = 0.4
    ) {
        self.portsToCheck = ports
        self.timeout = timeout
    }
    
    public func scanSubnet(info: NetworkInfo, concurrency: Int = 32, skipIPs: Set<String> = [], onProgress: ((Progress) -> Void)? = nil, onDeviceFound: ((Device) -> Void)? = nil) async throws -> [Device] {
        let parsed = await MainActor.run { (IPv4.parse(info.ip), IPv4.parse(info.netmask)) }
        guard let ip = parsed.0, let mask = parsed.1 else {
            print("[NIOPingScanner] Failed to parse IP or netmask: ip=\(info.ip) mask=\(info.netmask)")
            return []
        }
        
        let network = await MainActor.run { IPv4.network(ip: ip, mask: mask) }
        let hosts = await MainActor.run { IPv4.hosts(inNetwork: network, mask: mask) }
        let total = hosts.count
        
        let header: String = await MainActor.run {
            "[NIOPingScanner] Starting scan: network=\(IPv4.format(network)) mask=/\(IPv4.netmaskPrefix(mask)) totalHosts=\(total) skipping=\(skipIPs.count)"
        }
        print(header)
        
        var scanned = 0
        
        // Use a more conservative concurrency for network operations
        let effectiveConcurrency = max(1, min(32, concurrency))
        
        // Create a channel to collect results progressively
        let resultChannel = AsyncStream<Device> { continuation in
            Task {
                var index = 0
                while index < total {
                    if Task.isCancelled {
                        continuation.finish()
                        break
                    }
                    let upper = min(index + max(1, effectiveConcurrency), total)
                    try await withThrowingTaskGroup(of: Device?.self) { group in
                        for i in index..<upper {
                            try Task.checkCancellation()
                            let ipStr = await MainActor.run { IPv4.format(hosts[i]) }
                            if ipStr == info.ip || skipIPs.contains(ipStr) {
                                scanned += 1
                                onProgress?(Progress(scanned: scanned, total: total))
                                continue
                            }
                            group.addTask { [weak self] in
                                guard let self = self else { return nil }
                                try Task.checkCancellation()
                                return try await self.tryTCPPortScan(host: ipStr, ports: self.portsToCheck, timeout: self.timeout)
                            }
                        }
                        for try await maybe in group {
                            scanned += 1
                            if let d = maybe {
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
        for await device in resultChannel { results.append(device) }
        
        let snapshot = results
        let sorted: [Device] = await MainActor.run {
            snapshot.sorted { (a: Device, b: Device) in
                guard let aa = IPv4.parse(a.ipAddress)?.raw, let bb = IPv4.parse(b.ipAddress)?.raw else { return a.ipAddress < b.ipAddress }
                return aa < bb
            }
        }
        return sorted
    }
    
    // Helper method for TCP port scanning
    private func tryTCPPortScan(host: String, ports: [UInt16], timeout: TimeInterval) async throws -> Device? {
        var foundPorts = 0
        var bestRtt: Double = Double.infinity
        
        let toCheck = ports.prefix(min(24, ports.count))
        for port in toCheck {
            try Task.checkCancellation()
            print("[NIOPingScanner] Checking host \(host) port \(port)")
            if let (isAlive, rtt) = await checkPort(host, port: port, timeout: timeout) {
                print("[NIOPingScanner] Result for \(host):port\(port) -> alive=\(isAlive) rtt=\(rtt)")
                if isAlive {
                    foundPorts += 1
                    bestRtt = Swift.min(bestRtt, rtt)
                    break // early exit on first sign of life
                }
            }
        }
        
        if foundPorts >= 1 {
            let finalRtt: Double? = (bestRtt == Double.infinity) ? nil : bestRtt
            return await MainActor.run { Device(ip: host, rttMillis: finalRtt) }
        } else {
            return nil
        }
    }
    
    // Helper method to check if a TCP port is open or responds with "connection refused"
    private func checkPort(_ host: String, port: UInt16, timeout: TimeInterval) async -> (Bool, Double)? {
        // Create TCP connection to the specific port
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        
        let parameters = NWParameters.tcp
        parameters.prohibitExpensivePaths = false
        parameters.allowLocalEndpointReuse = true
        
        // Create a connection
        let connection = NWConnection(to: endpoint, using: parameters)
        
        return await withCheckedContinuation { continuation in
            let start = DispatchTime.now().uptimeNanoseconds
            let actor = ContinuationActor(continuation: continuation)
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Connection succeeded - port is open
                    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
                    connection.cancel()
                    print("[NIOPingScanner] Connection ready for \(host):\(port) (rtt=\(elapsedMs)ms)")
                    Task { await actor.resume(with: (true, elapsedMs)) }
                    
                case .failed(let error):
                    connection.cancel()
                    
                    // Check for connection refused - this means host exists but port is closed
                    if case .posix(let code) = error, code == .ECONNREFUSED {
                        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
                        print("[NIOPingScanner] Connection refused for \(host):\(port) (treated as alive) rtt=\(elapsedMs)ms)")
                        Task { await actor.resume(with: (true, elapsedMs)) }
                    } else {
                        print("[NIOPingScanner] Connection failed for \(host):\(port): \(error)")
                        Task { await actor.resume(with: nil) }
                    }
                    
                case .cancelled:
                    print("[NIOPingScanner] Connection cancelled for \(host):\(port)")
                    Task { await actor.resume(with: nil) }
                    
                default:
                    break
                }
            }
            
            // Set up a timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
                Task { await actor.resume(with: nil) }
            }
            
            // Start the connection
            connection.start(queue: .global(qos: .utility))
        }
    }
}

// Thread-safe actor for managing continuations
private actor ContinuationActor<T> {
    private var continuation: CheckedContinuation<T, Never>
    private var hasResumed = false
    
    init(continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }
    
    func resume(with value: T) {
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(returning: value)
    }
}
